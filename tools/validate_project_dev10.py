from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LEGACY_VALIDATOR = ROOT / "tools" / "validate_project.py"

# validate_project.py predates dev.10 and still contains two dev.8 wording checks plus
# a hard-coded BUILD_INFO version. Keep all of its other assertions active and
# suppress only these exact obsolete failures until the monolithic validator is
# version-neutralized in a later cleanup.
OBSOLETE_FAILURES = {
    'Project dev8 autoloads missing token: config/version="0.16.0-dev.8"',
    "Original RA2 ore overlay missing token: 使用《红色警戒2》温带 TIB Overlay",
    "BUILD_INFO version must be 0.16.0-dev.8",
}


def fail(message: str) -> None:
    print(f" - {message}", file=sys.stderr)


def require_token(path: Path, token: str, errors: list[str]) -> None:
    if not path.is_file():
        errors.append(f"Missing file: {path.relative_to(ROOT)}")
        return
    source = path.read_text(encoding="utf-8")
    if token not in source:
        errors.append(f"{path.relative_to(ROOT)} missing token: {token}")


def run_legacy_validator(errors: list[str]) -> None:
    result = subprocess.run(
        [sys.executable, str(LEGACY_VALIDATOR)],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode == 0:
        return
    output = "\n".join(part for part in [result.stdout, result.stderr] if part).strip()
    failures = {
        line.removeprefix(" - ").strip()
        for line in output.splitlines()
        if line.startswith(" - ")
    }
    unexpected = sorted(failures - OBSOLETE_FAILURES)
    missing_expected_format = not failures and result.returncode != 0
    if unexpected or missing_expected_format:
        if output:
            print(output, file=sys.stderr)
        if missing_expected_format:
            errors.append(
                f"Legacy validator exited {result.returncode} without parseable failures"
            )
        else:
            errors.extend(f"Legacy validator: {failure}" for failure in unexpected)


def validate_dev10_contract(errors: list[str]) -> None:
    require_token(ROOT / "project.godot", 'config/version="0.16.0-dev.10"', errors)
    require_token(
        ROOT / "project.godot",
        'RuntimeRA2MapInjection="*res://scripts/core/runtime_ra2_map_injection.gd"',
        errors,
    )
    require_token(
        ROOT / "scripts/game/ore_entity.gd",
        "使用《红色警戒2》原始 TIB/GEM Overlay",
        errors,
    )
    require_token(
        ROOT / "scripts/core/game_config.gd", "func _ra2_map_bundle_ready", errors
    )
    require_token(
        ROOT / "scripts/game/ra2_iso_grid_world.gd",
        '"ra2-godot-runtime-v2"',
        errors,
    )
    require_token(
        ROOT / "scripts/ra2/ra2_original_texture_library.gd",
        'RESOURCE_MANIFEST_PATH := "res://data/ra2_embedded/temperate_resources_v2.json"',
        errors,
    )
    for relative in [
        "tools/ra2_shp_ts.py",
        "tools/build_ra2_runtime_bundle.py",
        "tools/validate_ra2_runtime_bundle.py",
        "docs/V0_16_0_DEV10_RA2_RUNTIME_MAP.md",
    ]:
        if not (ROOT / relative).is_file():
            errors.append(f"Missing dev10 file: {relative}")

    try:
        build_info = json.loads((ROOT / "BUILD_INFO.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        errors.append(f"Invalid BUILD_INFO.json: {exc}")
    else:
        if build_info.get("version") != "0.16.0-dev.10":
            errors.append("BUILD_INFO version must be 0.16.0-dev.10")
        required_flags = {
            "runtime_ra2_map_runtime_v2": True,
            "runtime_ra2_map_bundle_builder": True,
            "runtime_ra2_map_bundle_validator": True,
            "runtime_ra2_resource_palette_manifest": True,
            "runtime_ra2_map_bundle_committed": False,
            "runtime_ra2_runtime_map_available": False,
            "runtime_ra2_map_roundtrip_writer": False,
            "runtime_ra2_zdata_entity_occlusion": False,
        }
        for key, expected in required_flags.items():
            if build_info.get(key) is not expected:
                errors.append(
                    f"BUILD_INFO {key} must be {expected!r}, got {build_info.get(key)!r}"
                )

    try:
        maps_ra2 = json.loads(
            (ROOT / "data/maps_ra2.json").read_text(encoding="utf-8")
        )
    except (OSError, json.JSONDecodeError) as exc:
        errors.append(f"Invalid data/maps_ra2.json: {exc}")
    else:
        definition = maps_ra2.get("ra2_mymap1", {})
        if definition.get("format") != "ra2_runtime_v2":
            errors.append("ra2_mymap1 must use ra2_runtime_v2")
        if definition.get("runtime_manifest") != "res://data/ra2_maps/mymap1_runtime.json":
            errors.append("ra2_mymap1 runtime manifest path is inconsistent")


def main() -> int:
    errors: list[str] = []
    run_legacy_validator(errors)
    validate_dev10_contract(errors)
    if errors:
        print("Dev10 validation failed:", file=sys.stderr)
        for message in errors:
            fail(message)
        return 1
    print(
        "Dev10 validation passed. Legacy checks remain active except three exact "
        "obsolete dev.8 assertions."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

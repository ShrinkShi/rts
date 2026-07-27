from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ERRORS: list[str] = []


def require(condition: bool, message: str) -> None:
    if not condition:
        ERRORS.append(message)


def load_json(relative: str):
    path = ROOT / relative
    require(path.is_file(), f"Missing JSON: {relative}")
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        ERRORS.append(f"Invalid JSON {relative}: {exc}")
        return {}


def check_layered_vehicle(entity_id: str) -> None:
    directory = ROOT / "assets/ra2_preview" / entity_id.lower()
    manifest = load_json(f"assets/ra2_preview/{entity_id.lower()}/manifest.json")
    layered = manifest.get("layered_vehicle", {})
    require(isinstance(layered, dict) and layered, f"{entity_id}: no layered_vehicle manifest")
    stand = layered.get("stand", {}) if isinstance(layered, dict) else {}
    require(len(stand) == 64, f"{entity_id}: expected 64 body/turret facing pairs, got {len(stand)}")
    for key, definition in stand.items():
        if not isinstance(definition, dict):
            ERRORS.append(f"{entity_id}:{key}: invalid layer definition")
            continue
        for field in ("body", "body_remap"):
            value = str(definition.get(field, ""))
            require(value != "" and (directory / value).is_file(), f"{entity_id}:{key}: missing {field} {value}")
        for field in ("turret", "turret_remap"):
            values = definition.get(field, [])
            require(isinstance(values, list) and values, f"{entity_id}:{key}: empty {field}")
            if isinstance(values, list):
                for value in values:
                    require((directory / str(value)).is_file(), f"{entity_id}:{key}: missing {field} {value}")


def main() -> int:
    project_text = (ROOT / "project.godot").read_text(encoding="utf-8")
    require('config/version="0.15.0"' in project_text, "project.godot is not version 0.15.0")

    terrain = load_json("assets/ra2_terrain/manifest.json")
    atlas_path = ROOT / "assets/ra2_terrain/temperate_atlas.png"
    require(atlas_path.is_file(), "Missing RA2 terrain atlas")
    if atlas_path.is_file():
        with Image.open(atlas_path) as image:
            require(image.size == (1280, 32), f"Unexpected terrain atlas size: {image.size}")
    require(int(terrain.get("columns", 0)) == 40, "Terrain manifest must contain 40 tiles")

    profiles = load_json("data/ra2/runtime_profiles.json")
    mapped_ids: set[str] = set()
    for kind in ("units", "buildings"):
        for faction in profiles.get(kind, {}).values():
            for profile in faction.values():
                entity_id = str(profile.get("ra2_id", "")).upper()
                if entity_id:
                    mapped_ids.add(entity_id)
                    require(
                        (ROOT / "assets/ra2_preview" / entity_id.lower() / "manifest.json").is_file(),
                        f"Mapped entity has no preview manifest: {entity_id}",
                    )

    for entity_id in ("MTNK", "FV", "HTNK", "HTK", "LTNK", "YTNK", "HARV", "SMIN"):
        check_layered_vehicle(entity_id)

    e1 = load_json("assets/ra2_preview/e1/manifest.json")
    e1_animations = e1.get("animations", {})
    for animation in ("Deploy", "Deployed", "DeployedFire"):
        require(animation in e1_animations, f"E1 missing deployment animation: {animation}")

    units = load_json("data/units.json")
    buildings = load_json("data/buildings.json")
    tank = units.get("tank", {})
    require(tank.get("projectile_type") == "shell", "Tank is not configured for ballistic shells")
    tank_range = float(tank.get("range", 0.0))
    for building_id in ("turret", "bunker"):
        require(float(buildings.get(building_id, {}).get("range", -1.0)) == tank_range,
                f"{building_id} range differs from tank range")

    advisor_numbers = (35, 37, 48, 49, 50, 51, 52, 53, 54, 56, 57, 62, 63, 64)
    for prefix in ("ceva", "csof", "cyur"):
        for number in advisor_numbers:
            sample = f"{prefix}{number:03d}.wav"
            found = any(
                (ROOT / "assets/ra2_audio" / bank / "standalone" / sample).is_file()
                for bank in ("ra2md", "ra2")
            )
            require(found, f"Missing advisor sample: {sample}")

    required_scripts = {
        "scripts/game/projectile.gd": ("sin(progress * PI)", "_impact"),
        "scripts/game/ai_controller.gd": ("_next_structure_choice", "get_debug_snapshot"),
        "scripts/game/rts_match.gd": ("toggle_ai_debug", "toggle_reveal_all", "spawn_projectile"),
        "scripts/game/unit.gd": ("command_deploy", "RA2LayeredVehicleVisual", 'projectile_type'),
    }
    for relative, tokens in required_scripts.items():
        text = (ROOT / relative).read_text(encoding="utf-8")
        for token in tokens:
            require(token in text, f"{relative} missing expected token: {token}")

    if ERRORS:
        print("v0.15 runtime validation failed:")
        for error in ERRORS:
            print(" -", error)
        return 1
    print(
        "v0.15 runtime validation passed: "
        f"{len(mapped_ids)} mapped entities, 8 layered vehicles, 3 advisor banks, RA2 terrain, GI deploy and shell projectile configuration."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

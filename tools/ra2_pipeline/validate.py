#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import gzip
from pathlib import Path
import py_compile
import re
import sys
import struct


def fail(message: str) -> None:
    raise AssertionError(message)


def validate_json(project: Path) -> dict:
    data_root = project / "data" / "ra2"
    for path in data_root.rglob("*.json"):
        json.loads(path.read_text(encoding="utf-8"))
    database_path = data_root / "database.json"
    if database_path.exists():
        database = json.loads(database_path.read_text(encoding="utf-8"))
    else:
        compressed = data_root / "database.json.gz"
        if not compressed.exists():
            fail("Missing database.json and database.json.gz")
        with gzip.open(compressed, "rt", encoding="utf-8") as handle:
            database = json.load(handle)
    summary = database["summary"]
    if int(summary["asset_count"]) < 11000:
        fail("Asset index unexpectedly small")
    if int(summary["entity_count"]) < 550:
        fail("Entity registry unexpectedly small")
    expected = {"E1", "HTNK", "GAPOWR", "GAWEAP", "YAPOWR"}
    actual = {str(item.get("id", "")) for item in database["entities"]}
    missing = expected - actual
    if missing:
        fail(f"Representative entities missing: {sorted(missing)}")
    return database


def validate_previews(project: Path) -> None:
    root = project / "assets" / "ra2_preview"
    catalog_path = root / "catalog.json"
    issues_path = root / "issues.json"
    if not catalog_path.exists():
        fail("Missing RA2 preview catalog")
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    if len(catalog) < 170:
        fail(f"RA2 preview catalog unexpectedly small: {len(catalog)}")
    preview_ids = {str(item.get("entity_id", "")).upper() for item in catalog}
    required_ids = {"E1", "E2", "SHK", "HTNK", "GAPOWR", "GAWEAP", "YAPOWR"}
    missing_ids = sorted(required_ids - preview_ids)
    if missing_ids:
        fail("Representative v0.13 previews missing: " + ", ".join(missing_ids))

    checked_frames = 0
    for entity_id in required_ids:
        entity_dir = root / entity_id.lower()
        manifest_path = entity_dir / "manifest.json"
        if not manifest_path.exists():
            fail(f"Missing preview manifest for {entity_id}")
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        animation_sets = []
        base_dir = entity_dir
        if isinstance(manifest.get("theaters"), dict):
            for theater_name, theater_data in manifest["theaters"].items():
                if isinstance(theater_data, dict):
                    animation_sets.append((entity_dir / str(theater_name), theater_data.get("animations", {})))
        else:
            animation_sets.append((base_dir, manifest.get("animations", {})))
        found_frame = False
        for frame_root, animations in animation_sets:
            if not isinstance(animations, dict):
                continue
            for animation in animations.values():
                if not isinstance(animation, dict):
                    continue
                frame_names = animation.get("frames")
                if isinstance(frame_names, list):
                    candidates = frame_names
                else:
                    candidates = []
                    directions = animation.get("directions", {})
                    if isinstance(directions, dict):
                        for direction in directions.values():
                            if isinstance(direction, dict) and isinstance(direction.get("frames"), list):
                                candidates.extend(direction["frames"])
                for frame_name in candidates[:1]:
                    if not (frame_root / str(frame_name)).exists():
                        fail(f"Missing generated frame for {entity_id}: {frame_root / str(frame_name)}")
                    checked_frames += 1
                    found_frame = True
                    break
                if found_frame:
                    break
            if found_frame:
                break
        if not found_frame:
            fail(f"Preview manifest contains no playable frame for {entity_id}")

    issues = json.loads(issues_path.read_text(encoding="utf-8")) if issues_path.exists() else []
    if len(issues) > 5:
        fail(f"Too many preview-generation issues: {len(issues)}")
    if checked_frames < len(required_ids):
        fail("Representative preview frame validation did not cover every entity")


def validate_python(project: Path) -> None:
    for path in (project / "tools" / "ra2_pipeline").glob("*.py"):
        py_compile.compile(str(path), doraise=True)


def validate_resource_paths(project: Path) -> None:
    pattern = re.compile(r'res://[^"\']+')
    missing: list[str] = []
    for path in list(project.rglob("*.gd")) + list(project.rglob("*.tscn")) + list(project.rglob("*.tres")):
        text = path.read_text(encoding="utf-8", errors="ignore")
        for match in pattern.findall(text):
            resource = match.split("?", 1)[0]
            local = project / resource.removeprefix("res://")
            # Runtime-generated visual paths are allowed to be absent.
            if "%" in resource or "{" in resource:
                continue
            if not local.exists() and not resource.endswith((".import", ".uid")):
                missing.append(f"{path.relative_to(project)} -> {resource}")
    if missing:
        fail("Missing res:// references:\n" + "\n".join(sorted(set(missing))[:50]))




def validate_supplemental(project: Path, database: dict) -> None:
    data_root = project / "data" / "ra2"
    summary = database["summary"]
    expected = {
        "localization_count": 5000,
        "audio_bank_count": 2,
        "audio_bag_entry_count": 3000,
        "standalone_wav_count": 1100,
        "sound_event_count": 500,
        "official_map_count": 10,
    }
    for key, minimum in expected.items():
        if int(summary.get(key, 0)) < minimum:
            fail(f"Supplemental count {key} is unexpectedly small")

    if int(summary.get("sound_sample_resolved_count", 0)) != int(summary.get("sound_sample_reference_count", -1)):
        fail("RA2/YR sound sample references are not fully resolved")
    if float(summary.get("sound_sample_resolution_ratio", 0.0)) != 1.0:
        fail("RA2/YR sound sample resolution ratio must be 1.0 with both audio banks")

    catalog = json.loads((data_root / "catalog.json").read_text(encoding="utf-8"))
    by_id = {str(item.get("id", "")): item for item in catalog}
    names = {"E1": "美國大兵", "HTNK": "犀牛坦克", "GAPOWR": "發電廠"}
    for entity_id, expected_name in names.items():
        if str(by_id.get(entity_id, {}).get("display_name", "")) != expected_name:
            fail(f"CSF name mismatch for {entity_id}")

    sound_events = json.loads((data_root / "sound_events.json").read_text(encoding="utf-8"))
    gi_select = next((item for item in sound_events if str(item.get("id", "")).casefold() == "giselect"), None)
    if not gi_select or int(gi_select.get("resolved_sample_count", 0)) < 1:
        fail("GISelect did not resolve to playable samples")
    missing_paths: list[str] = []
    for event in sound_events:
        for sample in event.get("samples", []):
            resource_path = str(sample.get("resource_path", ""))
            local = project / resource_path.removeprefix("res://")
            if not local.is_file():
                missing_paths.append(resource_path)
    if missing_paths:
        fail("Missing resolved sound samples: " + ", ".join(missing_paths[:10]))

    audio_manifest = json.loads((data_root / "audio_manifest.json").read_text(encoding="utf-8"))
    if int(audio_manifest.get("bank_count", 0)) != 2:
        fail("Expected separate RA2 and YR audio banks")
    if [str(item.get("id", "")) for item in audio_manifest.get("banks", [])] != ["ra2", "ra2md"]:
        fail("Audio bank priority must be RA2 < RA2MD")
    for item in audio_manifest.get("bag_entries", []):
        path = project / str(item["resource_path"]).removeprefix("res://")
        data = path.read_bytes()
        if len(data) < 44 or data[:4] != b"RIFF" or data[8:12] != b"WAVE":
            fail(f"Invalid generated WAV: {path.relative_to(project)}")
        declared = struct.unpack_from("<I", data, 4)[0] + 8
        if declared != len(data):
            fail(f"WAV size mismatch: {path.relative_to(project)}")
        chunk_offset = 12
        format_tag = None
        bits_per_sample = None
        while chunk_offset + 8 <= len(data):
            chunk_id = data[chunk_offset:chunk_offset + 4]
            chunk_size = struct.unpack_from("<I", data, chunk_offset + 4)[0]
            chunk_offset += 8
            if chunk_id == b"fmt " and chunk_size >= 16:
                format_tag = struct.unpack_from("<H", data, chunk_offset)[0]
                bits_per_sample = struct.unpack_from("<H", data, chunk_offset + 14)[0]
                break
            chunk_offset += chunk_size + (chunk_size & 1)
        if format_tag != 1 or bits_per_sample != 16:
            fail(f"Godot WAV source must be PCM16: {path.relative_to(project)}")

    maps = json.loads((data_root / "maps_official.json").read_text(encoding="utf-8"))
    if not maps or any(int(item.get("width", 0)) <= 0 or int(item.get("height", 0)) <= 0 for item in maps):
        fail("Official map dimensions were not parsed from Map/Size")

    seal_path = data_root / "entities" / "seal.json"
    seal = json.loads(seal_path.read_text(encoding="utf-8")) if seal_path.exists() else {}
    provenance = seal.get("rules", {}).get("provenance", {})
    create_sound = provenance.get("CreateSound", {})
    origin = create_sound.get("origin", {}) if isinstance(create_sound, dict) else {}
    if create_sound and str(origin.get("layer", "")) != "expandmd01":
        fail("Official expandmd01 override provenance was not retained")


def validate_browser_scripts(project: Path) -> None:
    browser = (project / "scripts" / "ui" / "ra2_database_browser.gd").read_text(encoding="utf-8")
    if ":=" in browser:
        fail("Database browser must not rely on inferred declarations")
    helper = (project / "scripts" / "ra2" / "ra2_database.gd").read_text(encoding="utf-8")
    if ":=" in helper:
        fail("RA2 database helper must not rely on inferred declarations")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    project = args.project.resolve()
    database = validate_json(project)
    validate_previews(project)
    validate_python(project)
    validate_resource_paths(project)
    validate_browser_scripts(project)
    validate_supplemental(project, database)
    print(json.dumps({
        "status": "ok",
        "summary": database["summary"],
        "note": "Godot executable validation must still be run on a machine with Godot 4.7.1.",
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
import sys

PROJECT = Path(__file__).resolve().parents[1]
PREVIEW = PROJECT / "assets" / "ra2_preview"


def load_manifest(entity_id: str) -> dict:
    path = PREVIEW / entity_id.lower() / "manifest.json"
    if not path.is_file():
        raise AssertionError(f"missing preview manifest: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def first_indices(manifest: dict, animation_name: str) -> list[int]:
    animation = manifest["animations"][animation_name]
    return [int(animation["directions"][str(index)]["source_indices"][0]) for index in range(8)]


def main() -> int:
    # Godot order: E, SE, S, SW, W, NW, N, NE.
    expected_raw_facings = [6, 5, 4, 3, 2, 1, 0, 7]
    e1 = load_manifest("E1")
    assert first_indices(e1, "Ready") == expected_raw_facings, first_indices(e1, "Ready")

    dron = load_manifest("DRON")
    expected_dron_starts = [36, 30, 24, 18, 12, 6, 0, 42]
    actual_dron_starts = [
        int(dron["animations"]["Walk"]["directions"][str(index)]["source_indices"][0])
        for index in range(8)
    ]
    assert actual_dron_starts == expected_dron_starts, actual_dron_starts

    # VXL previews use their own correct projection direction and must not be remapped.
    htnk = load_manifest("HTNK")
    assert htnk.get("visual_kind") == "voxel"

    gapowr = load_manifest("GAPOWR")
    assert gapowr.get("available_theaters") == ["temperate", "snow"]
    assert gapowr["theaters"]["temperate"]["body_source"].lower() == "ggpowr.shp"
    assert gapowr["theaters"]["snow"]["body_source"].lower() == "gapowr.shp"
    assert "Operational" in gapowr["theaters"]["temperate"]["animations"]

    gaweap = load_manifest("GAWEAP")
    operational = gaweap["theaters"]["temperate"]["animations"]["Operational"]
    component_keys = {str(item.get("key", "")) for item in operational.get("components", [])}
    assert {"ActiveAnim", "ActiveAnimTwo"}.issubset(component_keys), component_keys

    for manifest_path in PREVIEW.glob("*/manifest.json"):
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        folders: list[tuple[Path, dict]] = []
        if manifest.get("visual_kind") == "building_shp":
            for theater, theater_data in manifest.get("theaters", {}).items():
                folders.append((manifest_path.parent / theater, theater_data.get("animations", {})))
        else:
            folders.append((manifest_path.parent, manifest.get("animations", {})))
        for folder, animations in folders:
            for animation in animations.values():
                if animation.get("directional"):
                    frame_sets = animation.get("directions", {}).values()
                else:
                    frame_sets = [animation]
                for frame_set in frame_sets:
                    for field in ("frames", "remap_masks"):
                        for relative in frame_set.get(field, []) or []:
                            path = folder / str(relative)
                            if not path.is_file():
                                raise AssertionError(f"missing {field}: {path}")

    print("RA2 preview regression validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

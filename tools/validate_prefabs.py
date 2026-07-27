from __future__ import annotations

import re
import sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ERRORS: list[str] = []


def fail(message: str) -> None:
    ERRORS.append(message)


def validate_spriteframes(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    ext = dict(re.findall(r'\[ext_resource type="Texture2D" path="([^"]+)" id="([^"]+)"\]', text))
    # Reverse to id -> path.
    ext_by_id = {resource_id: resource_path for resource_path, resource_id in ext.items()}
    current_id = None
    atlas_id = None
    regions: list[tuple[str, tuple[int, int, int, int]]] = []
    for line in text.splitlines():
        match = re.match(r'\[sub_resource type="AtlasTexture" id="([^"]+)"\]', line)
        if match:
            current_id = match.group(1)
            atlas_id = None
            continue
        match = re.match(r'atlas = ExtResource\("([^"]+)"\)', line)
        if match and current_id:
            atlas_id = match.group(1)
            continue
        match = re.match(r'region = Rect2\(([-0-9.]+), ([-0-9.]+), ([-0-9.]+), ([-0-9.]+)\)', line)
        if match and current_id and atlas_id:
            regions.append((atlas_id, tuple(int(float(value)) for value in match.groups())))
            current_id = None
            atlas_id = None
    for atlas_ref, (x, y, width, height) in regions:
        resource_path = ext_by_id.get(atlas_ref)
        if not resource_path:
            fail(f"{path.relative_to(ROOT)} references unknown texture id {atlas_ref}")
            continue
        image_path = ROOT / resource_path.removeprefix("res://")
        if not image_path.exists():
            fail(f"Missing texture {resource_path} for {path.relative_to(ROOT)}")
            continue
        image_width, image_height = Image.open(image_path).size
        if x < 0 or y < 0 or width <= 0 or height <= 0 or x + width > image_width or y + height > image_height:
            fail(f"Out-of-bounds atlas region in {path.relative_to(ROOT)}: {(x, y, width, height)} vs {(image_width, image_height)}")
    animation_names = re.findall(r'"name": &"([^"]+)"', text)
    if "stand_0" not in animation_names:
        fail(f"{path.relative_to(ROOT)} has no stand_0 animation")
    if len(animation_names) != len(set(animation_names)):
        fail(f"Duplicate animation names in {path.relative_to(ROOT)}")


def validate_scene(path: Path, required: list[str]) -> None:
    text = path.read_text(encoding="utf-8")
    for token in required:
        if token not in text:
            fail(f"{path.relative_to(ROOT)} missing {token}")
    for resource_path in re.findall(r'path="(res://[^"]+)"', text):
        target = ROOT / resource_path.removeprefix("res://")
        if not target.exists():
            fail(f"{path.relative_to(ROOT)} references missing {resource_path}")


def main() -> int:
    for path in sorted((ROOT / "resources" / "sprite_frames").glob("*.tres")):
        validate_spriteframes(path)
    for unit_id in ["rifle", "rocket", "tank", "scout", "harvester"]:
        required = ["VisualRoot", "Body", "CollisionShape2D", "DamageSmokeAnchor", "SelectionAnchor", "stand_0"]
        if unit_id == "tank":
            required.append("Turret")
        if unit_id == "harvester":
            required.append("CargoBarAnchor")
        validate_scene(ROOT / "scenes" / "entities" / "units" / f"{unit_id}.tscn", required)
    for building_id in ["command", "power", "barracks", "refinery", "war_factory", "repair_bay", "turret", "bunker"]:
        required = ["VisualRoot", "Body", "StaticBody2D", "CollisionShape2D", "DamageSmokeAnchor", "ServiceAnchor"]
        if building_id in ["turret", "bunker"]:
            required.append("Weapon")
        validate_scene(ROOT / "scenes" / "entities" / "buildings" / f"{building_id}.tscn", required)
    validate_scene(ROOT / "scenes" / "tools" / "prefab_gallery.tscn", ["PrefabGallery", "harvester.tscn", "command.tscn"])
    preview = (ROOT / "scenes" / "tools" / "visual_profile_preview.tscn").read_text(encoding="utf-8")
    if "visual_profile_preview.gd" in preview:
        fail("Deprecated preview scene still runs the broken @tool preview script")
    if ERRORS:
        print("Prefab validation failed:")
        for error in ERRORS:
            print(" -", error)
        return 1
    print("Prefab validation passed:", len(list((ROOT / "resources" / "sprite_frames").glob("*.tres"))), "SpriteFrames resources, 13 entity scenes.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

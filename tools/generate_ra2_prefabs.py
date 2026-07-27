#!/usr/bin/env python3
"""Generate one editable Godot scene per RA2/YR runtime entity."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data" / "ra2"
UNIT_DIR = ROOT / "scenes" / "entities" / "ra2" / "units"
BUILDING_DIR = ROOT / "scenes" / "entities" / "ra2" / "buildings"


def load(name: str) -> dict[str, Any]:
    return json.loads((DATA / name).read_text(encoding="utf-8"))


def q(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def unit_scene(entity_id: str, data: dict[str, Any]) -> str:
    body_path = str(data.get("ra2_body_frames") or data.get("ra2_sprite_frames") or "")
    turret_path = str(data.get("ra2_turret_frames") or "")
    if not body_path:
        raise ValueError(f"{entity_id}: missing unit body frames")
    ext = [
        '[ext_resource type="Script" path="res://scripts/game/unit.gd" id="1_script"]',
        f'[ext_resource type="SpriteFrames" path="{q(body_path)}" id="2_body"]',
    ]
    if turret_path:
        ext.append(f'[ext_resource type="SpriteFrames" path="{q(turret_path)}" id="3_turret"]')
    radius = max(7.0, float(data.get("collision_radius", data.get("radius", 12.0))) * 0.96)
    scale = float(data.get("ra2_visual_scale", 0.82 if data.get("category") == "infantry" else 0.56))
    turret_props = 'visible = false'
    if turret_path:
        turret_props = 'visible = true\nsprite_frames = ExtResource("3_turret")\nanimation = &"stand_0"'
    return f'''[gd_scene load_steps={5 if turret_path else 4} format=3]\n\n''' + "\n".join(ext) + f'''\n\n[sub_resource type="CircleShape2D" id="CircleShape2D_collision"]\nradius = {radius:.4f}\n\n[node name="{q(entity_id)}" type="CharacterBody2D"]\nscript = ExtResource("1_script")\npreset_unit_id = "{q(entity_id)}"\nauto_fit_ra2_visual = false\nuse_prefab_collision_shape = true\neditor_description = "RA2/YR 可视化单位预制场景。直接调整 VisualRoot、Body、Turret、碰撞体和挂点。"\n\n[node name="CollisionShape2D" type="CollisionShape2D" parent="."]\nshape = SubResource("CircleShape2D_collision")\n\n[node name="VisualRoot" type="Node2D" parent="."]\nposition = Vector2(0, -10)\nscale = Vector2({scale:.6f}, {scale:.6f})\n\n[node name="Body" type="AnimatedSprite2D" parent="VisualRoot"]\nsprite_frames = ExtResource("2_body")\nanimation = &"stand_0"\ncentered = true\ntexture_filter = 1\nshow_behind_parent = true\n\n[node name="Turret" type="AnimatedSprite2D" parent="VisualRoot"]\n{turret_props}\ncentered = true\ntexture_filter = 1\nz_index = 2\n\n[node name="DamageSmokeAnchor" type="Marker2D" parent="."]\nposition = Vector2(0, -26)\n\n[node name="SelectionAnchor" type="Marker2D" parent="."]\nposition = Vector2(0, 10)\n\n[node name="CargoBarAnchor" type="Marker2D" parent="."]\nposition = Vector2(0, 22)\n'''


def building_scene(entity_id: str, data: dict[str, Any]) -> str:
    shp_path = str(data.get("ra2_shp_resource") or "")
    if not shp_path:
        raise ValueError(f"{entity_id}: missing SHP resource")
    shp_file = ROOT / shp_path.removeprefix("res://")
    shp_text = shp_file.read_text(encoding="utf-8")
    import re
    atlas_match = re.search(r'path="([^"]+/atlas\.png)"', shp_text)
    size_match = re.search(r'frame_size = Vector2i\((\d+), (\d+)\)', shp_text)
    count_match = re.search(r'frame_count = (\d+)', shp_text)
    if not atlas_match or not size_match or not count_match:
        raise ValueError(f"{entity_id}: malformed SHP resource")
    atlas_path = atlas_match.group(1)
    frame_w, frame_h = map(int, size_match.groups())
    frame_count = int(count_match.group(1))
    turret_path = str(data.get("ra2_building_turret_frames") or "")
    ext = [
        '[ext_resource type="Script" path="res://scripts/game/building.gd" id="1_script"]',
        f'[ext_resource type="Resource" path="{q(shp_path)}" id="2_shp"]',
        f'[ext_resource type="Texture2D" path="{q(atlas_path)}" id="3_atlas"]',
    ]
    if turret_path:
        ext.append(f'[ext_resource type="SpriteFrames" path="{q(turret_path)}" id="4_turret"]')
    footprint = data.get("footprint", [1, 1])
    fw = max(1, int(footprint[0]))
    fh = max(1, int(footprint[1]))
    target_width = max(64.0, fw * 44.0 * 1.42)
    scale = float(data.get("ra2_visual_scale", target_width / max(1.0, frame_w)))
    y_offset = -max(12.0, fh * 44.0 * 0.34)
    damage1 = min(max(0, int(frame_count * 0.5)), frame_count - 1)
    damage2 = min(max(0, round((frame_count - 1) * 0.75)), frame_count - 1)
    destroyed = max(0, frame_count - 1)
    turret_props = 'visible = false'
    if turret_path:
        turret_props = 'visible = true\nsprite_frames = ExtResource("4_turret")\nanimation = &"stand_0"'
    return f'''[gd_scene load_steps={6 if turret_path else 5} format=3]\n\n''' + "\n".join(ext) + f'''\n\n[sub_resource type="AtlasTexture" id="AtlasTexture_preview"]\natlas = ExtResource("3_atlas")\nregion = Rect2(0, 0, {frame_w}, {frame_h})\nfilter_clip = true\n\n[node name="{q(entity_id)}" type="Node2D"]\nscript = ExtResource("1_script")\npreset_building_id = "{q(entity_id)}"\nauto_fit_ra2_visual = false\nexternal_shp_resource = ExtResource("2_shp")\nexternal_shp_healthy_frame = 0\nexternal_shp_damage_1_frame = {damage1}\nexternal_shp_damage_2_frame = {damage2}\nexternal_shp_destroyed_frame = {destroyed}\neditor_description = "RA2/YR 可视化建筑预制场景。直接调整 VisualRoot、Body、Weapon 和挂点。"\n\n[node name="VisualRoot" type="Node2D" parent="."]\nposition = Vector2(0, {y_offset:.4f})\nscale = Vector2({scale:.6f}, {scale:.6f})\n\n[node name="Body" type="Sprite2D" parent="VisualRoot"]\ntexture = SubResource("AtlasTexture_preview")\ncentered = true\ntexture_filter = 1\nshow_behind_parent = true\n\n[node name="Weapon" type="AnimatedSprite2D" parent="VisualRoot"]\n{turret_props}\ncentered = true\ntexture_filter = 1\nz_index = 2\n\n[node name="DamageSmokeAnchor" type="Marker2D" parent="."]\nposition = Vector2(0, -38)\n\n[node name="ServiceAnchor" type="Marker2D" parent="."]\nposition = Vector2(0, 28)\n'''


def main() -> int:
    units = load("runtime_units.json")
    buildings = load("runtime_buildings.json")
    UNIT_DIR.mkdir(parents=True, exist_ok=True)
    BUILDING_DIR.mkdir(parents=True, exist_ok=True)
    for old in UNIT_DIR.glob("*.tscn"):
        old.unlink()
    for old in BUILDING_DIR.glob("*.tscn"):
        old.unlink()
    for entity_id, data in units.items():
        (UNIT_DIR / f"{entity_id}.tscn").write_text(unit_scene(entity_id, data), encoding="utf-8")
    for entity_id, data in buildings.items():
        (BUILDING_DIR / f"{entity_id}.tscn").write_text(building_scene(entity_id, data), encoding="utf-8")
    print(json.dumps({"ok": True, "unit_scenes": len(units), "building_scenes": len(buildings)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

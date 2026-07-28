from __future__ import annotations

import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ERRORS: list[str] = []


def error(message: str) -> None:
    ERRORS.append(message)


def text(path: str) -> str:
    target = ROOT / path
    if not target.exists():
        error(f"Missing file: {path}")
        return ""
    return target.read_text(encoding="utf-8")


def require(source: str, tokens: list[str], label: str) -> None:
    for token in tokens:
        if token not in source:
            error(f"{label} missing token: {token}")


def validate_json() -> dict[str, object]:
    result: dict[str, object] = {}
    for name in ["units", "buildings", "maps", "factions", "modes"]:
        relative = f"data/{name}.json"
        try:
            result[name] = json.loads((ROOT / relative).read_text(encoding="utf-8"))
        except Exception as exc:
            error(f"Invalid JSON {relative}: {exc}")
    for relative in ["BUILD_INFO.json", "data/ra2/runtime_profiles.json"]:
        try:
            json.loads((ROOT / relative).read_text(encoding="utf-8"))
        except Exception as exc:
            error(f"Invalid JSON {relative}: {exc}")
    return result


def validate_gdscript_structure() -> None:
    func_pattern = re.compile(r"^func\s+([A-Za-z0-9_]+)\s*\(", re.MULTILINE)
    preload_pattern = re.compile(r'(?:preload|load)\("(res://[^"]+)"\)')
    for path in ROOT.rglob("*.gd"):
        source = path.read_text(encoding="utf-8")
        names = func_pattern.findall(source)
        duplicates = sorted({name for name in names if names.count(name) > 1})
        if duplicates:
            error(f"Duplicate functions in {path.relative_to(ROOT)}: {duplicates}")
        for left, right in [("(", ")"), ("[", "]"), ("{", "}")]:
            if source.count(left) != source.count(right):
                error(f"Unbalanced {left}{right} in {path.relative_to(ROOT)}")
        lines = source.splitlines()
        for index, line in enumerate(lines[:-1]):
            if re.match(r"^func\s+.*:\s*$", line):
                next_line = lines[index + 1]
                if next_line and not next_line.startswith((" ", "\t", "#")):
                    error(f"Unindented function body in {path.relative_to(ROOT)}:{index + 2}")
        for resource in preload_pattern.findall(source):
            if not (ROOT / resource.removeprefix("res://")).exists():
                error(f"Missing resource referenced by {path.relative_to(ROOT)}: {resource}")


def validate_features(data: dict[str, object]) -> None:
    project = text("project.godot")
    match = text("scripts/game/rts_match.gd")
    unit = text("scripts/game/unit.gd")
    building = text("scripts/game/building.gd")
    grid = text("scripts/game/grid_world_base.gd") + "\n" + text("scripts/game/grid_world.gd")
    runtime_tuning = text("scripts/core/runtime_tuning.gd")
    runtime_rules = "\n".join([
        text("scripts/core/runtime_movement_rules.gd"),
        text("scripts/core/runtime_production_rules.gd"),
        text("scripts/core/runtime_deployment_rules.gd"),
        text("scripts/core/runtime_defeat_rules.gd"),
    ])
    combat_effect = text("scripts/game/combat_effect.gd")
    layered_vehicle = text("scripts/ra2/ra2_layered_vehicle_visual.gd")
    hud = text("scripts/ui/match_hud.gd")
    tree = text("scripts/game/tree_entity.gd")
    campaign = text("scripts/ui/campaign_menu.gd")
    factory = text("scripts/game/sprite_sheet_factory.gd")
    asset_processor = text("tools/process_ai_assets.py")

    require(project, [
        'config/version="0.16.0-dev.4"',
        'RuntimeTuning="*res://scripts/core/runtime_tuning.gd"',
        'RuntimeMovementRules="*res://scripts/core/runtime_movement_rules.gd"',
        'RuntimeProductionRules="*res://scripts/core/runtime_production_rules.gd"',
        'RuntimeDeploymentRules="*res://scripts/core/runtime_deployment_rules.gd"',
        'RuntimeDefeatRules="*res://scripts/core/runtime_defeat_rules.gd"',
        '2d/snap/snap_2d_transforms_to_pixel=true',
    ], "Project version/runtime")
    require(match, [
        'structure_jobs = {"primary": {}, "defense": {}}', 'func repair_entity_step',
        'func sell_building', 'func apply_ground_damage', 'KEY_A and event.ctrl_pressed',
        'func notify_allies_under_attack', 'func _spawn_tree_entities',
        'func _formation_targets', 'max_radius * 2.0 + 10.0',
        'func query_units_in_radius', 'MAX_ACTIVE_TRACERS', 'MAX_ACTIVE_COMBAT_TEXTS',
    ], "RTS match")
    require(unit, [
        'func _resolve_unit_overlaps', 'Do not hard-snap every member of a formation',
        'func _calculate_separation_vector', 'query_units_in_radius',
        'order_queue.size() < 64', 'path.size() > 512', 'retaliate_enabled',
        'support_enabled', 'func cycle_behavior_policy', 'func command_force_attack',
        'func command_repair', 'get_cover_multiplier', 'turret_facing_direction',
        'get_tank_turret_frames',
    ], "Unit")
    require(building, [
        'func is_repair_facility', 'func accept_vehicle_for_repair',
        'func _process_vehicle_repair', 'func begin_sell', 'construction_progress',
        'SpriteSheetFactory.get_building_frame', 'func _update_turret_visual',
        'VisualRoot/Weapon', 'get_defense_head_frames',
    ], "Building")
    require(grid, [
        'balanced_land', 'ore_centers', 'astar_infantry', 'astar_vehicle',
        'func get_cover_multiplier', 'func get_movement_speed_multiplier',
        'or has_ore(cell)', 'Generate one quadrant and mirror it across both axes',
        'overlay_types', 'overlay_frames', 'height_levels', 'slope_types',
        'land_types', 'func get_overlay_asset_id', 'func get_cell_snapshot',
        'func get_ground_height', 'Extrude each tile',
    ], "Grid")
    require(runtime_tuning, [
        'collision_radius"] = 6.25', 'unit.stats["radius"] = 15.0',
        'ore_harvest', 'building._update_damage_visual()', '_remove_invalid_normal_tail',
    ], "Runtime tuning")
    require(runtime_rules, [
        'MAX_PRODUCTION_QUEUE := 30', '5 if bool(event.shift_pressed) else 1',
        'TREE_VEHICLE_RADIUS_FACTOR := 0.22', '_settle_occupied_move_destination',
        '_filter_deployed_units_from_right_click', '_pack_command_building',
        '_unpack_mcv', '_player_has_structure_presence', '_show_defeat_notice',
        '_requirements_met', '_raise_building_health_bar_once',
        '_stabilize_war_factory_production_visual_once',
        '_process_harvester_unload_visual', '"电力  %d / %d" % [consumed, produced]',
    ], "Runtime gameplay rules")
    require(combat_effect, ['effect_type == "ore_harvest"', '_spawn_ore_particles', 'effect_type == "muzzle"'], "Combat effects")
    require(layered_vehicle, ['_shadow_center', 'draw_set_transform(_shadow_center', 'position = (Vector2'], "Layered vehicle shadow")
    require(hud, ['SidebarToolButton', 'repair_building', 'sell_building', 'repair_bay', 'force_attack', 'behavior', 'get_structure_status'], "HUD")
    require(tree, ['dense', 'LAYER_TREE', '步兵可进入并获得25%减伤'], "Tree")
    require(campaign, ['MarginContainer.new()', 'size_flags_vertical = Control.SIZE_EXPAND_FILL'], "Campaign UI")
    require(factory, ['AtlasTexture.new()', 'filter_clip = true', 'tank_chassis.png', 'tank_turret.png', 'bunker_head', 'create_team_material'], "Sprite atlas")
    require(asset_processor, ['N, NW, W, SW, S, SE, E, NE', 'rows_from_specs', '[5, -5, 3, 1, 0, -2, -4, 4]', "split_grid(SOURCES['tank_chassis'], 8, 3, 26)", "split_grid(SOURCES['tank_turret'], 8, 2, 52)", '(224, 192)', '[4, 3, 2, 1, 0, 7, 6, 5]', '_tank_ring_anchor', '_turret_mount_anchor', '(128, 184)', 'clean_detached_fragments'], "AI asset alignment")

    for unit_id in ['rifle', 'rocket', 'tank', 'scout', 'harvester']:
        scene_path = ROOT / 'scenes' / 'entities' / 'units' / f'{unit_id}.tscn'
        if not scene_path.exists():
            error(f'Missing unit prefab: {scene_path.relative_to(ROOT)}')
        else:
            scene_text = scene_path.read_text(encoding='utf-8')
            for token in ['VisualRoot', 'CollisionShape2D', 'AnimatedSprite2D']:
                if token not in scene_text:
                    error(f'Unit prefab {unit_id} missing {token}')
    for building_id in ['command', 'power', 'barracks', 'refinery', 'war_factory', 'repair_bay', 'turret', 'bunker']:
        scene_path = ROOT / 'scenes' / 'entities' / 'buildings' / f'{building_id}.tscn'
        if not scene_path.exists():
            error(f'Missing building prefab: {scene_path.relative_to(ROOT)}')
        else:
            scene_text = scene_path.read_text(encoding='utf-8')
            for token in ['VisualRoot', 'StaticBody2D', 'CollisionShape2D', 'Sprite2D']:
                if token not in scene_text:
                    error(f'Building prefab {building_id} missing {token}')

    units = data.get("units", {})
    if not isinstance(units, dict) or int(units.get("harvester", {}).get("hp", 0)) != 3250:
        error("harvester hp must be 3250")
    if not isinstance(units, dict) or "mcv" not in units:
        error("mcv is missing from units.json")
    buildings = data.get("buildings", {})
    for required_building in ["repair_bay", "bunker"]:
        if not isinstance(buildings, dict) or required_building not in buildings:
            error(f"{required_building} is missing from buildings.json")

    maps = data.get("maps", {})
    if isinstance(maps, dict):
        for map_id, map_data in maps.items():
            if not isinstance(map_data, dict) or map_id == "frontier_expanse":
                continue
            size = map_data.get("size", [0, 0])
            if len(size) < 2 or not (50 <= int(size[0]) <= 100 and 50 <= int(size[1]) <= 100):
                error(f"Skirmish map {map_id} size must be within 50..100")
            if str(map_data.get("style", "")) != "balanced_land":
                error(f"Skirmish map {map_id} must be pure balanced land")
            positions = map_data.get("positions", [])
            ore_centers = map_data.get("ore_centers", [])
            if not positions or len(ore_centers) < len(positions) * 2:
                error(f"Skirmish map {map_id} lacks spawn-adjacent first/second ore centers")
                continue
            distance_rows = [sorted(math.dist((float(p[0]), float(p[1])), (float(c[0]), float(c[1]))) for c in ore_centers) for p in positions]
            if max(row[0] for row in distance_rows) - min(row[0] for row in distance_rows) > 1.0:
                error(f"Skirmish map {map_id} first-mine distance spread is too large")
            if max(row[1] for row in distance_rows) - min(row[1] for row in distance_rows) > 1.2:
                error(f"Skirmish map {map_id} second-mine distance spread is too large")


def main() -> int:
    data = validate_json()
    validate_gdscript_structure()
    validate_features(data)
    if ERRORS:
        print("Validation failed:")
        for item in ERRORS:
            print(" -", item)
        return 1
    gd_files = list(ROOT.rglob("*.gd"))
    gd_lines = sum(len(path.read_text(encoding="utf-8").splitlines()) for path in gd_files)
    print(f"Validation passed: {len(gd_files)} GDScript files, {gd_lines} lines, {len(data)} JSON datasets.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

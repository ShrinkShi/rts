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


def json_data(path: str):
    target = ROOT / path
    try:
        return json.loads(target.read_text(encoding="utf-8"))
    except Exception as exc:
        error(f"Invalid JSON {path}: {exc}")
        return {}


def require(source: str, tokens: list[str], label: str) -> None:
    for token in tokens:
        if token not in source:
            error(f"{label} missing token: {token}")


def validate_json() -> dict[str, object]:
    result: dict[str, object] = {}
    for name in ["units", "buildings", "maps", "factions", "modes"]:
        result[name] = json_data(f"data/{name}.json")
    json_data("BUILD_INFO.json")
    json_data("data/ra2/runtime_profiles.json")
    json_data("data/ra2/warheads.json")
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
        for resource in preload_pattern.findall(source):
            if not (ROOT / resource.removeprefix("res://")).exists():
                error(f"Missing resource referenced by {path.relative_to(ROOT)}: {resource}")


def validate_ra2_rules_data() -> None:
    warheads = json_data("data/ra2/warheads.json")
    by_id = {
        str(item.get("id", "")).upper(): item
        for item in warheads
        if isinstance(item, dict)
    } if isinstance(warheads, list) else {}
    ap = by_id.get("AP", {})
    verses = str(ap.get("values", {}).get("Verses", "")) if isinstance(ap, dict) else ""
    expected = "25%,25%,15%,75%,100%,100%,65%,45%,60%,60%,100%"
    if verses != expected:
        error(f"AP Verses mismatch: expected {expected!r}, got {verses!r}")

    profiles = json_data("data/ra2/runtime_profiles.json")
    buildings = profiles.get("buildings", {}) if isinstance(profiles, dict) else {}
    expected_slots = {
        ("union", "turret"): "NASAM",
        ("union", "bunker"): "GAPILL",
        ("dominion", "turret"): "NAFLAK",
        ("dominion", "bunker"): "NALASR",
        ("republic", "turret"): "YAGGUN",
        ("republic", "bunker"): "NATBNK",
    }
    for (faction, slot), entity_id in expected_slots.items():
        actual = str(buildings.get(faction, {}).get(slot, {}).get("ra2_id", ""))
        if actual != entity_id:
            error(f"Defense slot {faction}/{slot} must map to {entity_id}, got {actual}")
    allied_pillbox_cost = int(buildings.get("union", {}).get("bunker", {}).get("cost_override", 0))
    if allied_pillbox_cost != 650:
        error("Retained Allied pillbox cost_override must be 650")


def validate_features(data: dict[str, object]) -> None:
    project = text("project.godot")
    match = text("scripts/game/rts_match.gd")
    base_unit = text("scripts/game/unit.gd")
    base_building = text("scripts/game/building.gd")
    ra2_unit = text("scripts/game/ra2_unit.gd")
    ra2_building = text("scripts/game/ra2_building.gd")
    rules_adapter = text("scripts/ra2/ra2_rules_adapter.gd")
    audio_service = text("scripts/ra2/ra2_audio_service.gd")
    combat_audio = text("scripts/ra2/ra2_combat_audio.gd")
    ai_rules = text("scripts/core/runtime_ai_rules.gd")
    movement_rules = text("scripts/core/runtime_movement_rules.gd")
    production_rules = text("scripts/core/runtime_production_rules.gd")
    deployment_rules = text("scripts/core/runtime_deployment_rules.gd")
    defeat_rules = text("scripts/core/runtime_defeat_rules.gd")
    runtime_tuning = text("scripts/core/runtime_tuning.gd")
    tree = text("scripts/game/tree_entity.gd")
    grid = text("scripts/game/grid_world_base.gd") + "\n" + text("scripts/game/grid_world.gd")

    require(project, [
        'config/version="0.16.0-dev.5"',
        'RA2RulesAdapter="*res://scripts/ra2/ra2_rules_adapter.gd"',
        'RA2CombatAudio="*res://scripts/ra2/ra2_combat_audio.gd"',
        'RuntimeAIRules="*res://scripts/core/runtime_ai_rules.gd"',
        'RuntimeMovementRules="*res://scripts/core/runtime_movement_rules.gd"',
        'RuntimeProductionRules="*res://scripts/core/runtime_production_rules.gd"',
    ], "Project dev5 autoloads")

    require(rules_adapter, [
        'WARHEADS_PATH := "res://data/ra2/warheads.json"',
        'func build_runtime_stats', 'func parse_foundation',
        '"biological"', '"mechanical"', '"building"',
        'func damage_multiplier', 'warhead_verses', 'armor_value',
    ], "RA2 rules adapter")
    require(audio_service, [
        'func play_event_spatial', 'view_rect.has_point(world_position)',
        'MIN_EDGE_VOLUME', 'panning_strength = 1.0', 'player.attenuation = 0.0',
    ], "Spatial audio")
    require(combat_audio, ['func play_weapon_report', 'play_event_spatial'], "Combat audio router")
    require(ai_rules, ['func _repair_one_building', 'repair_entity_step', 'set_repair_active(true)'], "AI building repair")
    require(ra2_unit, [
        'RA2RulesAdapter.build_runtime_stats', 'RA2RulesAdapter.resolve_damage',
        'RA2CombatAudio.play_weapon_report', 'corpse_lifetime = 3.2',
        'func enter_tank_bunker', 'func exit_tank_bunker',
    ], "RA2 unit runtime")
    require(ra2_building, [
        'RA2RulesAdapter.build_runtime_stats', 'RA2RulesAdapter.resolve_damage',
        'destruction_lifetime = 3.8', 'func can_accept_tank',
        '"NAFLAK", "NASAM", "GAPATS"', '"YAGGUN"', '"NATBNK"',
        'target_domains = ["ground", "air"]',
    ], "RA2 building runtime")
    require(movement_rules, [
        'TREE_VEHICLE_RADIUS_FACTOR := 0.14',
        '_settle_occupied_move_destination', '_stabilize_stationary_tank_facing',
        'order_type in ["move", "attack_move"]',
    ], "Movement rules")
    require(production_rules, [
        'MAX_PRODUCTION_QUEUE := 30', '5 if bool(event.shift_pressed) else 1',
        'RA2RulesAdapter.build_runtime_stats', 'cost_override',
        'GameConfig.buildings[building_id]["footprint"]',
        '"电力  %d / %d" % [consumed, produced]',
    ], "Production rules")
    require(deployment_rules, ['_filter_deployed_units_from_right_click', '_pack_command_building', '_unpack_mcv'], "Deployment rules")
    require(defeat_rules, ['_player_has_structure_presence', '_show_defeat_notice'], "Defeat rules")
    require(runtime_tuning, ['UNIT_SCRIPT_PATHS', 'BUILDING_SCRIPT_PATHS', 'ore_harvest'], "Runtime tuning subclasses")
    require(tree, [
        'TREE_COLLISION_FACTOR := 0.14', 'RA2_TREE_PATHS',
        'ResourceLoader.exists(path)', '步兵可进入并获得25%减伤',
    ], "RA2 tree runtime")
    require(match, ['func _issue_targeted_command', 'elif mode == "rally"'], "Map-targeted command routing")
    require(base_unit, ['func command_attack_move', 'func command_patrol'], "Base unit commands")
    require(base_building, ['func repair_entity_step' if 'func repair_entity_step' in match else 'func set_repair_active'], "Base building repair visual")
    require(grid, ['func get_ground_height', 'height_levels', 'slope_types'], "Grid height metadata")

    for unit_id in ["rifle", "rocket", "tank", "scout", "harvester"]:
        source = text(f"scenes/entities/units/{unit_id}.tscn")
        require(source, ['res://scripts/game/ra2_unit.gd', 'CollisionShape2D', 'AnimatedSprite2D'], f"Unit prefab {unit_id}")
    for building_id in ["command", "power", "barracks", "refinery", "war_factory", "repair_bay", "turret", "bunker"]:
        source = text(f"scenes/entities/buildings/{building_id}.tscn")
        require(source, ['res://scripts/game/ra2_building.gd', 'StaticBody2D', 'CollisionShape2D', 'Sprite2D'], f"Building prefab {building_id}")
    turret_scene = text("scenes/entities/buildings/turret.tscn")
    require(turret_scene, ['position = Vector2(0, -38.0)'], "Raised sentry fallback turret")

    maps = data.get("maps", {})
    if isinstance(maps, dict):
        for map_id, map_data in maps.items():
            if not isinstance(map_data, dict) or map_id == "frontier_expanse":
                continue
            size = map_data.get("size", [0, 0])
            if len(size) < 2 or not (50 <= int(size[0]) <= 100 and 50 <= int(size[1]) <= 100):
                error(f"Skirmish map {map_id} size must be within 50..100")
            positions = map_data.get("positions", [])
            ore_centers = map_data.get("ore_centers", [])
            if not positions or len(ore_centers) < len(positions) * 2:
                error(f"Skirmish map {map_id} lacks spawn-adjacent ore centers")
                continue
            rows = [sorted(math.dist((float(p[0]), float(p[1])), (float(c[0]), float(c[1]))) for c in ore_centers) for p in positions]
            if max(row[0] for row in rows) - min(row[0] for row in rows) > 1.0:
                error(f"Skirmish map {map_id} first-mine distance spread is too large")


def main() -> int:
    data = validate_json()
    validate_gdscript_structure()
    validate_ra2_rules_data()
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

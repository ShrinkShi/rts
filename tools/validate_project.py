from __future__ import annotations

import json
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
    try:
        return json.loads((ROOT / path).read_text(encoding="utf-8"))
    except Exception as exc:
        error(f"Invalid JSON {path}: {exc}")
        return {}


def require(source: str, tokens: list[str], label: str) -> None:
    for token in tokens:
        if token not in source:
            error(f"{label} missing token: {token}")


def forbid(source: str, tokens: list[str], label: str) -> None:
    for token in tokens:
        if token in source:
            error(f"{label} contains forbidden token: {token}")


def validate_gdscript_structure() -> None:
    func_pattern = re.compile(r"^(?:static\s+)?func\s+([A-Za-z0-9_]+)\s*\(", re.MULTILINE)
    preload_pattern = re.compile(r'(?:preload|load)\("(res://[^"]+)"\)')
    reserved_variable_pattern = re.compile(r"\bvar\s+(class_name|extends|signal|static)\b")
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
        reserved_match = reserved_variable_pattern.search(source)
        if reserved_match:
            error(f"Reserved keyword used as variable in {path.relative_to(ROOT)}: {reserved_match.group(1)}")


def validate_json_and_ra2_data() -> None:
    for path in [
        "BUILD_INFO.json", "data/units.json", "data/buildings.json",
        "data/maps.json", "data/factions.json", "data/modes.json",
        "data/ra2/runtime_profiles.json", "data/ra2/warheads.json",
    ]:
        json_data(path)

    warheads = json_data("data/ra2/warheads.json")
    by_id = {
        str(item.get("id", "")).upper(): item
        for item in warheads
        if isinstance(item, dict)
    } if isinstance(warheads, list) else {}
    ap = by_id.get("AP", {})
    actual_verses = str(ap.get("values", {}).get("Verses", "")) if isinstance(ap, dict) else ""
    expected_verses = "25%,25%,15%,75%,100%,100%,65%,45%,60%,60%,100%"
    if actual_verses != expected_verses:
        error(f"AP Verses mismatch: expected {expected_verses!r}, got {actual_verses!r}")

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
    if int(buildings.get("union", {}).get("bunker", {}).get("cost_override", 0)) != 650:
        error("Retained Allied pillbox cost_override must be 650")


def validate_dev5_features() -> None:
    project = text("project.godot")
    require(project, [
        'config/version="0.16.0-dev.5"',
        'RuntimeAIRules="*res://scripts/core/runtime_ai_rules.gd"',
        'RuntimeMovementRules="*res://scripts/core/runtime_movement_rules.gd"',
        'RuntimeProductionRules="*res://scripts/core/runtime_production_rules.gd"',
    ], "Project dev5 autoloads")
    forbid(project, [
        'RA2RulesAdapter="*res://scripts/ra2/ra2_rules_adapter.gd"',
        'RA2CombatAudio="*res://scripts/ra2/ra2_combat_audio.gd"',
    ], "Static RA2 helper autoloads")

    rules = text("scripts/ra2/ra2_rules_adapter.gd")
    require(rules, [
        'extends RefCounted',
        'WARHEADS_PATH := "res://data/ra2/warheads.json"',
        'static func build_runtime_stats', 'static func parse_foundation',
        '"biological"', '"mechanical"', '"building"',
        'static func damage_multiplier', 'warhead_verses', 'armor_value',
        'var armor_class_name: String',
    ], "RA2 rules adapter")
    forbid(rules, ['var class_name'], "RA2 rules adapter reserved identifiers")

    audio = text("scripts/ra2/ra2_audio_service.gd")
    require(audio, [
        'func play_event_spatial', 'view_rect.has_point(world_position)',
        'MIN_EDGE_VOLUME', 'panning_strength = 1.0', 'player.attenuation = 0.0',
    ], "Screen-space combat audio")
    require(text("scripts/ra2/ra2_combat_audio.gd"), [
        'extends RefCounted', 'static func play_weapon_report',
        'audio_service.call("play_event_spatial"',
    ], "RA2 combat audio router")

    ai_rules = text("scripts/core/runtime_ai_rules.gd")
    require(ai_rules, [
        'func _repair_one_building', 'repair_entity_step', 'set_repair_active(true)',
    ], "AI building repair")

    ra2_unit = text("scripts/game/ra2_unit.gd")
    require(ra2_unit, [
        'const RA2Rules = preload("res://scripts/ra2/ra2_rules_adapter.gd")',
        'const RA2CombatAudioRouter = preload("res://scripts/ra2/ra2_combat_audio.gd")',
        'RA2Rules.build_runtime_stats', 'RA2Rules.resolve_damage',
        'RA2CombatAudioRouter.play_weapon_report', 'corpse_lifetime = 3.2',
        'var entry: Vector2', 'func enter_tank_bunker', 'func exit_tank_bunker',
    ], "RA2 unit runtime")

    ra2_building = text("scripts/game/ra2_building.gd")
    require(ra2_building, [
        'const RA2Rules = preload("res://scripts/ra2/ra2_rules_adapter.gd")',
        'const RA2CombatAudioRouter = preload("res://scripts/ra2/ra2_combat_audio.gd")',
        'RA2Rules.build_runtime_stats', 'RA2Rules.resolve_damage',
        'destruction_lifetime = 3.8', 'func can_accept_tank',
        '"NAFLAK", "NASAM", "GAPATS"', '"YAGGUN"', '"NATBNK"',
        'target_domains = ["ground", "air"]',
    ], "RA2 building runtime")

    movement = text("scripts/core/runtime_movement_rules.gd")
    require(movement, [
        'TREE_VEHICLE_RADIUS_FACTOR := 0.14',
        '_settle_occupied_move_destination', '_stabilize_stationary_tank_facing',
        'order_type in ["move", "attack_move"]',
    ], "Movement rules")

    production = text("scripts/core/runtime_production_rules.gd")
    require(production, [
        'const RA2Rules = preload("res://scripts/ra2/ra2_rules_adapter.gd")',
        'MAX_PRODUCTION_QUEUE := 30', '5 if bool(event.shift_pressed) else 1',
        'RA2Rules.build_runtime_stats', 'cost_override',
        'GameConfig.buildings[building_id]["footprint"]',
        '"电力  %d / %d" % [consumed, produced]',
    ], "Production rules")

    deployment = text("scripts/core/runtime_deployment_rules.gd")
    require(deployment, [
        'preload("res://scripts/game/ra2_unit.gd")',
        'const RA2Rules = preload("res://scripts/ra2/ra2_rules_adapter.gd")',
        '_filter_deployed_units_from_right_click', '_pack_command_building',
        'RA2Rules.build_runtime_stats', '_command_footprint', '_unpack_mcv',
    ], "Deployment and MCV Foundation rules")

    require(text("scripts/core/runtime_defeat_rules.gd"), [
        '_player_has_structure_presence', '_show_defeat_notice',
    ], "Defeat rules")
    require(text("scripts/core/runtime_tuning.gd"), [
        'UNIT_SCRIPT_PATHS', 'BUILDING_SCRIPT_PATHS', 'ore_harvest',
    ], "Runtime tuning subclasses")

    tree = text("scripts/game/tree_entity.gd")
    require(tree, [
        'TREE_COLLISION_FACTOR := 0.14', 'RA2_TREE_PATHS',
        'ResourceLoader.exists(path)', 'var index: int',
        '步兵可进入并获得25%减伤',
    ], "RA2 tree loader")

    match = text("scripts/game/rts_match.gd")
    require(match, ['func _issue_targeted_command', 'elif mode == "rally"'], "Map-targeted commands")
    require(text("scripts/game/unit.gd"), ['func command_attack_move', 'func command_patrol'], "Unit map commands")
    require(text("scripts/game/building.gd"), ['func set_repair_active'], "Building wrench visual")

    for unit_id in ["rifle", "rocket", "tank", "scout", "harvester"]:
        source = text(f"scenes/entities/units/{unit_id}.tscn")
        require(source, ['res://scripts/game/ra2_unit.gd', 'CollisionShape2D', 'AnimatedSprite2D'], f"Unit prefab {unit_id}")
    for building_id in ["command", "power", "barracks", "refinery", "war_factory", "repair_bay", "turret", "bunker"]:
        source = text(f"scenes/entities/buildings/{building_id}.tscn")
        require(source, ['res://scripts/game/ra2_building.gd', 'StaticBody2D', 'CollisionShape2D', 'Sprite2D'], f"Building prefab {building_id}")
    require(text("scenes/entities/buildings/turret.tscn"), [
        'position = Vector2(0, -38.0)',
    ], "Raised fallback turret")


def main() -> int:
    validate_gdscript_structure()
    validate_json_and_ra2_data()
    validate_dev5_features()
    if ERRORS:
        print("Validation failed:")
        for item in ERRORS:
            print(" -", item)
        return 1
    gd_files = list(ROOT.rglob("*.gd"))
    gd_lines = sum(len(path.read_text(encoding="utf-8").splitlines()) for path in gd_files)
    print(f"Validation passed: {len(gd_files)} GDScript files, {gd_lines} lines.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

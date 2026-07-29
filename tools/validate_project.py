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


def validate_json_data() -> None:
    for path in [
        "BUILD_INFO.json", "data/units.json", "data/buildings.json",
        "data/maps.json", "data/maps_height.json", "data/factions.json",
        "data/modes.json", "data/ra2/runtime_profiles.json",
        "data/ra2/warheads.json",
    ]:
        json_data(path)

    build_info = json_data("BUILD_INFO.json")
    if str(build_info.get("version", "")) != "0.16.0-dev.7":
        error("BUILD_INFO version must be 0.16.0-dev.7")

    height_maps = json_data("data/maps_height.json")
    highland = height_maps.get("highland_trial", {}) if isinstance(height_maps, dict) else {}
    rects = highland.get("height_rects", []) if isinstance(highland, dict) else []
    if not rects:
        error("highland_trial must include height_rects")
    else:
        first = rects[0]
        if not all(name in first.get("ramps", []) for name in ["north", "east", "south", "west"]):
            error("highland_trial must expose four directional ramps")
        if int(first.get("ramp_width", 0)) < 2:
            error("highland_trial ramp_width must be at least 2")

    profiles = json_data("data/ra2/runtime_profiles.json")
    dominion_bunker = profiles.get("buildings", {}).get("dominion", {}).get("bunker", {}) if isinstance(profiles, dict) else {}
    if dominion_bunker.get("ra2_id") != "NALASR":
        error("Soviet bunker slot must remain NALASR")
    if not bool(dominion_bunker.get("runtime_custom_turret", False)):
        error("NALASR profile must enable runtime_custom_turret")

    warheads = json_data("data/ra2/warheads.json")
    by_id = {
        str(item.get("id", "")).upper(): item
        for item in warheads
        if isinstance(item, dict)
    } if isinstance(warheads, list) else {}
    actual_verses = str(by_id.get("AP", {}).get("values", {}).get("Verses", ""))
    expected_verses = "25%,25%,15%,75%,100%,100%,65%,45%,60%,60%,100%"
    if actual_verses != expected_verses:
        error(f"AP Verses mismatch: expected {expected_verses!r}, got {actual_verses!r}")


def validate_runtime_integration() -> None:
    project = text("project.godot")
    require(project, [
        'config/version="0.16.0-dev.7"',
        'RuntimeHeightVisualRules="*res://scripts/core/runtime_height_visual_rules.gd"',
        'RuntimeSentryVisualRules="*res://scripts/core/runtime_sentry_visual_rules.gd"',
        'RuntimeMovementRules="*res://scripts/core/runtime_movement_rules.gd"',
        'RuntimeProductionRules="*res://scripts/core/runtime_production_rules.gd"',
        'RuntimeAIRules="*res://scripts/core/runtime_ai_rules.gd"',
    ], "Project dev7 autoloads")
    forbid(project, [
        'RA2RulesAdapter="*res://scripts/ra2/ra2_rules_adapter.gd"',
        'RA2CombatAudio="*res://scripts/ra2/ra2_combat_audio.gd"',
    ], "Static RA2 helper autoloads")

    height_rules = text("scripts/core/runtime_height_visual_rules.gd")
    require(height_rules, [
        'const HeightTerrainOverlay = preload("res://scripts/game/height_terrain_overlay.gd")',
        'func _apply_rect_height_zones',
        'func _stamp_rect_ramps',
        'func _enforce_cliff_constraints',
        'func _restore_legacy_cliff_solids',
        'func find_path_for_unit',
        'func _find_edge_aware_path',
        'func is_height_transition_allowed',
        'func is_world_transition_walkable',
        'height_cliff_edges',
        'map_ref.set_meta("height_cliff_cells", {})',
    ], "Height edge-aware runtime rules")
    forbid(height_rules, [
        'if borders_drop and not has_ramp_access:',
        'cliff_cells[cell] = true',
    ], "Legacy solid cliff-cell pathing")

    overlay = text("scripts/game/height_terrain_overlay.gd")
    require(overlay, [
        'func _draw_cliff_faces',
        'func _draw_south_face',
        'func _draw_east_edge',
        'func _draw_height_surfaces',
        'func _draw_ramp',
        'draw_texture_rect_region(atlas, rect, _terrain_region(cell), Color.WHITE)',
        'draw_colored_polygon',
        'HEIGHT_STEP_PIXELS := 16.0',
    ], "Visible height terrain overlay")
    forbid(overlay, [
        'draw_texture_rect_region(rect, atlas',
    ], "CanvasItem texture-region argument order")

    sentry_rules = text("scripts/core/runtime_sentry_visual_rules.gd")
    require(sentry_rules, [
        'const SentryGunVisual = preload("res://scripts/game/sentry_gun_visual.gd")',
        'str(building.ra2_entity_id) != "NALASR"',
        'building.ra2_visual.set_progress("BodyStates"',
        'RuntimeSentryGunHead',
        'head.set_state(',
    ], "Soviet sentry visual runtime")

    sentry_visual = text("scripts/game/sentry_gun_visual.gd")
    require(sentry_visual, [
        'func configure', 'func set_state', 'func _draw',
        'draw_line(direction * 2.0, direction * 18.0',
        'draw_circle(direction * 1.0',
    ], "Soviet sentry custom turret")

    layered_visual = text("scripts/ra2/ra2_layered_vehicle_visual.gd")
    require(layered_visual, [
        'func _play_pair(base: AnimatedSprite2D, remap_sprite: AnimatedSprite2D',
        'remap_sprite.play(animation_name)',
    ], "Layered vehicle remap naming")
    forbid(layered_visual, [
        'func _play_pair(base: AnimatedSprite2D, remap: AnimatedSprite2D',
    ], "Built-in remap shadowing")

    movement = text("scripts/core/runtime_movement_rules.gd")
    require(movement, [
        'var alternate: Variant',
        'if manifest.has("layered_vehicle"):',
        'alternate = RA2LayeredVehicleVisual.new()',
        'alternate = RA2VisualPlayer.new()',
    ], "Explicit unload visual construction")
    forbid(movement, [
        'RA2LayeredVehicleVisual.new() if manifest.has("layered_vehicle") else RA2VisualPlayer.new()',
    ], "Incompatible visual ternary")

    grid = text("scripts/game/grid_world.gd")
    require(grid, [
        'func get_ground_sample', 'func get_ground_gradient',
        'SLOPE_SPEED_MULTIPLIER := 0.78', 'func can_place',
    ], "Height-aware grid base")

    ra2_unit = text("scripts/game/ra2_unit.gd")
    require(ra2_unit, [
        'func _update_terrain_pose', 'func apply_terrain_impulse',
        'var airborne_height: float', 'var entry: Vector2',
        'func _set_path_to',
        'RuntimeHeightVisualRules.find_path_for_unit',
        'func _guard_grounded_cliff_transition',
        'RuntimeHeightVisualRules.is_world_transition_walkable',
    ], "Height-aware RA2 units")
    forbid(ra2_unit, [
        'float(super.take_damage', 'var away := source.global_position',
    ], "RA2 unit parser/runtime regressions")

    ra2_building = text("scripts/game/ra2_building.gd")
    require(ra2_building, [
        'func _apply_terrain_pose', 'var elevated_origin: Vector2',
        'var previous_hp: float = hp',
    ], "Height-aware RA2 buildings")
    forbid(ra2_building, ['float(actual)'], "RA2 building null conversion regression")

    rules = text("scripts/ra2/ra2_rules_adapter.gd")
    require(rules, ['extends RefCounted', 'var armor_class_name: String'], "RA2 static rules adapter")
    forbid(rules, ['var class_name'], "RA2 rules reserved identifiers")

    audio = text("scripts/ra2/ra2_audio_service.gd")
    require(audio, ['SPATIAL_POOL_SIZE: int = 24', 'func _acquire_spatial_player'], "Pooled spatial audio")


def main() -> int:
    validate_gdscript_structure()
    validate_json_data()
    validate_runtime_integration()
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

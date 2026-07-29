from __future__ import annotations

import base64
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


def validate_original_texture_atlas() -> None:
    manifest = json_data("data/ra2_embedded/temperate_runtime_atlas.json")
    assets = manifest.get("assets", {}) if isinstance(manifest, dict) else {}
    required_assets = [
        "ore_00", "ore_11", "tibtre01_00", "tibtre01_10",
        "water_01", "water_14", "shore_1", "shore_e",
    ]
    for asset_id in required_assets:
        if asset_id not in assets:
            error(f"Original RA2 atlas missing asset: {asset_id}")
    encoded = ""
    for index in range(4):
        chunk_path = ROOT / f"data/ra2_embedded/temperate_runtime_atlas_{index:02d}.b64"
        if not chunk_path.exists():
            error(f"Missing original RA2 atlas chunk: {chunk_path.relative_to(ROOT)}")
            continue
        encoded += chunk_path.read_text(encoding="utf-8").strip()
    if encoded:
        try:
            payload = base64.b64decode(encoded, validate=True)
        except Exception as exc:
            error(f"Original RA2 atlas base64 is invalid: {exc}")
        else:
            if not payload.startswith(b"\x89PNG\r\n\x1a\n"):
                error("Original RA2 atlas is not a PNG payload")


def validate_json_data() -> None:
    for path in [
        "BUILD_INFO.json", "data/units.json", "data/buildings.json",
        "data/maps.json", "data/maps_height.json", "data/factions.json",
        "data/modes.json", "data/ra2/runtime_profiles.json",
        "data/ra2/warheads.json", "data/ra2_embedded/temperate_runtime_atlas.json",
    ]:
        json_data(path)

    build_info = json_data("BUILD_INFO.json")
    if str(build_info.get("version", "")) != "0.16.0-dev.8":
        error("BUILD_INFO version must be 0.16.0-dev.8")

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
    coast = height_maps.get("temperate_coast_trial", {}) if isinstance(height_maps, dict) else {}
    if coast.get("style") != "coast":
        error("temperate_coast_trial must use coast generation")
    if int(coast.get("ore_pillar_count", 0)) < 1:
        error("temperate_coast_trial must include ore pillars")

    profiles = json_data("data/ra2/runtime_profiles.json")
    dominion = profiles.get("buildings", {}).get("dominion", {}) if isinstance(profiles, dict) else {}
    dominion_bunker = dominion.get("bunker", {})
    if dominion_bunker.get("ra2_id") != "NALASR":
        error("Soviet bunker slot must remain NALASR")
    if not bool(dominion_bunker.get("use_original_composite", False)):
        error("NALASR profile must use its original composite")
    if bool(dominion_bunker.get("runtime_custom_turret", False)):
        error("NALASR must not use the hand-drawn custom turret")
    soviet_harvester = profiles.get("units", {}).get("dominion", {}).get("harvester", {})
    if int(soviet_harvester.get("body_direction_offset", 0)) != 4:
        error("Soviet harvester must use a four-direction body correction")
    if soviet_harvester.get("strategic_role") != "economy":
        error("Soviet harvester must remain an economy unit")

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

    validate_original_texture_atlas()


def validate_runtime_integration() -> None:
    project = text("project.godot")
    require(project, [
        'config/version="0.16.0-dev.8"',
        'RuntimeHeightVisualRules="*res://scripts/core/runtime_height_visual_rules.gd"',
        'RuntimeSentryVisualRules="*res://scripts/core/runtime_sentry_visual_rules.gd"',
        'RuntimeRA2ResourceRules="*res://scripts/core/runtime_ra2_resource_rules.gd"',
        'RuntimeHarvesterRules="*res://scripts/core/runtime_harvester_rules.gd"',
        'RuntimePowerDisplayRules="*res://scripts/core/runtime_power_display_rules.gd"',
        'RuntimeMovementRules="*res://scripts/core/runtime_movement_rules.gd"',
        'RuntimeProductionRules="*res://scripts/core/runtime_production_rules.gd"',
        'RuntimeAIRules="*res://scripts/core/runtime_ai_rules.gd"',
    ], "Project dev8 autoloads")
    forbid(project, [
        'RA2RulesAdapter="*res://scripts/ra2/ra2_rules_adapter.gd"',
        'RA2CombatAudio="*res://scripts/ra2/ra2_combat_audio.gd"',
    ], "Static RA2 helper autoloads")

    height_rules = text("scripts/core/runtime_height_visual_rules.gd")
    require(height_rules, [
        'const HeightTerrainOverlay = preload("res://scripts/game/height_terrain_overlay.gd")',
        'func _apply_rect_height_zones', 'func _stamp_rect_ramps',
        'func _enforce_cliff_constraints', 'func _restore_legacy_cliff_solids',
        'func find_path_for_unit', 'func _find_edge_aware_path',
        'func is_height_transition_allowed', 'func is_world_transition_walkable',
        'height_cliff_edges', 'map_ref.set_meta("height_cliff_cells", {})',
    ], "Height edge-aware runtime rules")
    forbid(height_rules, [
        'if borders_drop and not has_ramp_access:', 'cliff_cells[cell] = true',
    ], "Legacy solid cliff-cell pathing")

    overlay = text("scripts/game/height_terrain_overlay.gd")
    require(overlay, [
        'func _draw_cliff_faces', 'func _draw_south_face',
        'func _draw_east_edge', 'func _draw_height_surfaces',
        'func _draw_ramp',
        'draw_texture_rect_region(atlas, rect, _terrain_region(cell), Color.WHITE)',
        'draw_colored_polygon', 'HEIGHT_STEP_PIXELS := 16.0',
    ], "Visible height terrain overlay")
    forbid(overlay, ['draw_texture_rect_region(rect, atlas'], "CanvasItem texture-region argument order")

    original_library = text("scripts/ra2/ra2_original_texture_library.gd")
    require(original_library, [
        'extends RefCounted', 'Marshalls.base64_to_raw(encoded)',
        'image.load_png_from_buffer(bytes)', 'AtlasTexture.new()',
        'static func shoreline_asset',
    ], "Embedded original RA2 texture loader")

    ore = text("scripts/game/ore_entity.gd")
    require(ore, [
        'RA2OriginalTextures.texture(overlay_asset_id)',
        'overlay_asset_id = "ore_%02d" % stage',
        '使用《红色警戒2》温带 TIB Overlay',
    ], "Original RA2 ore overlay")

    water = text("scripts/game/ra2_water_overlay.gd")
    require(water, [
        'func _draw_water_cell', 'shoreline_asset(land_mask)',
        'asset_id = "water_%02d" % variant', 'draw_texture_rect(',
    ], "Original RA2 water and shoreline")
    forbid(water, ['mouse_filter ='], "Node2D water overlay properties")

    pillars = text("scripts/game/ore_pillar_entity.gd")
    resource_rules = text("scripts/core/runtime_ra2_resource_rules.gd")
    require(pillars, [
        'signal spread_requested(origin: Vector2i)',
        '"tibtre01_%02d" % animation_frame', 'spread_requested.emit(cell)',
    ], "Original RA2 ore pillar")
    require(resource_rules, [
        'pillar.spread_requested.connect(', 'func spread_ore',
        'ORE_GROWTH_PER_PULSE := 150', 'func _can_grow_ore',
        'RA2OriginalWaterOverlay',
    ], "RA2 resource runtime rules")

    sentry_rules = text("scripts/core/runtime_sentry_visual_rules.gd")
    require(sentry_rules, [
        'const SOVIET_SENTRY_ID := "NALASR"',
        'func _use_original_ra2_sentry',
        'building.ra2_visual.play_state(desired_state, 0, true)',
        'nglasr.shp',
    ], "Original Soviet sentry runtime")
    forbid(sentry_rules, [
        'SentryGunVisual.new()', 'head.set_state(',
    ], "Hand-drawn Soviet sentry runtime")

    harvester_rules = text("scripts/core/runtime_harvester_rules.gd")
    ai = text("scripts/game/ai_controller.gd")
    require(harvester_rules, [
        'const SOVIET_HARVESTER_ID := "HARV"',
        'HALF_TURN_DIRECTIONS := 4',
        'unit.stats["strategic_role"] = "economy"',
        'unit.ra2_visual.play_state(',
    ], "Soviet harvester direction and role")
    require(ai, [
        'if str(unit.unit_id) == "harvester" or not bool(unit.stats.get("ai_attack_unit", true)):',
        'must never be consumed by the AI attack-wave',
    ], "AI harvester attack exclusion")

    power = text("scripts/core/runtime_power_display_rules.gd")
    require(power, [
        'process_priority = 10000',
        '"电力  %d / %d" % [consumed, produced]',
        'if load_ratio > 0.75:', 'if is_inf(load_ratio) or load_ratio > 1.0:',
        'GREEN := Color("#73D586")', 'YELLOW := Color("#E5C45D")',
        'RED := Color("#EF6B63")',
    ], "Authoritative power load display")

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
        'var alternate: Variant', 'if manifest.has("layered_vehicle"):',
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
        'var airborne_height: float', 'var entry: Vector2', 'func _set_path_to',
        'RuntimeHeightVisualRules.find_path_for_unit',
        'func _guard_grounded_cliff_transition',
        'RuntimeHeightVisualRules.is_world_transition_walkable',
    ], "Height-aware RA2 units")
    forbid(ra2_unit, ['float(super.take_damage', 'var away := source.global_position'], "RA2 unit parser/runtime regressions")

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

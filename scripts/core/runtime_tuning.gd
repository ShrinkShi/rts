extends Node

# Runtime corrections that depend on the final RA2 visual/content bounds. Keeping
# them here avoids duplicating tuning code across every unit and building scene.
const CombatEffect = preload("res://scripts/game/combat_effect.gd")
const UNIT_SCRIPT_PATHS := ["res://scripts/game/unit.gd", "res://scripts/game/ra2_unit.gd"]
const BUILDING_SCRIPT_PATHS := ["res://scripts/game/building.gd", "res://scripts/game/ra2_building.gd"]
const TUNING_TAG := "v0_16_0_dev_3_tuned"
const BUILDING_SANITIZED_TAG := "v0_16_0_dev_3_animation_sanitized"
const HARVEST_UPDATE_INTERVAL := 0.08
const BUILDING_DAMAGE_INTERVAL := 0.12
const SANITIZE_INTERVAL := 0.25

var _harvesters: Array = []
var _buildings: Array = []
var _pending_sanitize: Array = []
var _harvest_effect_timers: Dictionary = {}
var _building_damage_bands: Dictionary = {}
var _harvest_elapsed := 0.0
var _building_damage_elapsed := 0.0
var _sanitize_elapsed := 0.0
var _cleanup_timer: float = 1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_PAUSABLE
    _rng.randomize()
    get_tree().node_added.connect(_on_node_added)
    _register_existing(get_tree().root)


func _register_existing(node: Node) -> void:
    _register_node(node)
    for child in node.get_children():
        _register_existing(child)


func _on_node_added(node: Node) -> void:
    call_deferred("_register_node", node)


func _register_node(node: Node) -> void:
    if not is_instance_valid(node):
        return
    var script: Script = node.get_script() as Script
    if script == null:
        return
    var script_path: String = script.resource_path
    if script_path in UNIT_SCRIPT_PATHS:
        call_deferred("_initialize_unit", node)
    elif script_path in BUILDING_SCRIPT_PATHS:
        if not node in _buildings:
            _buildings.append(node)
        if not node in _pending_sanitize:
            _pending_sanitize.append(node)
        call_deferred("_sanitize_building_animation_once", node)


func _initialize_unit(unit) -> void:
    if not is_instance_valid(unit) or unit.stats.is_empty():
        return
    _tune_unit_once(unit)
    if str(unit.unit_id) == "harvester" and not unit in _harvesters:
        _harvesters.append(unit)


func _process(delta: float) -> void:
    _harvest_elapsed -= delta
    if _harvest_elapsed <= 0.0:
        var harvest_step := HARVEST_UPDATE_INTERVAL - _harvest_elapsed
        _harvest_elapsed = HARVEST_UPDATE_INTERVAL
        for harvester in _harvesters:
            if is_instance_valid(harvester):
                _process_harvest_effect(harvester, harvest_step)

    _building_damage_elapsed -= delta
    if _building_damage_elapsed <= 0.0:
        _building_damage_elapsed = BUILDING_DAMAGE_INTERVAL
        for building in _buildings:
            if is_instance_valid(building):
                _synchronize_building_damage(building)

    _sanitize_elapsed -= delta
    if _sanitize_elapsed <= 0.0:
        _sanitize_elapsed = SANITIZE_INTERVAL
        _process_pending_sanitization()

    _cleanup_timer -= delta
    if _cleanup_timer <= 0.0:
        _cleanup_timer = 1.0
        _harvesters = _harvesters.filter(func(value): return is_instance_valid(value))
        _buildings = _buildings.filter(func(value): return is_instance_valid(value))
        _pending_sanitize = _pending_sanitize.filter(func(value): return is_instance_valid(value))
        _prune_instance_dictionary(_harvest_effect_timers)
        _prune_instance_dictionary(_building_damage_bands)


func _process_pending_sanitization() -> void:
    var pending: Array = []
    for building in _pending_sanitize:
        if not is_instance_valid(building):
            continue
        _sanitize_building_animation_once(building)
        if not is_instance_valid(building.ra2_visual) or not building.ra2_visual.has_meta(BUILDING_SANITIZED_TAG):
            pending.append(building)
    _pending_sanitize = pending


func _tune_unit_once(unit) -> void:
    if unit.has_meta(TUNING_TAG) or unit.stats.is_empty():
        return

    var category: String = str(unit.stats.get("category", ""))
    var unit_id: String = str(unit.unit_id)
    if category == "infantry":
        unit.stats["collision_radius"] = 6.25 if unit_id == "rifle" else 6.75
        unit.safe_margin = 0.72
        if unit.has_method("_build_collision_shape"):
            unit._build_collision_shape()
    elif unit_id == "tank":
        unit.stats["collision_radius"] = 16.0
        unit.stats["radius"] = 15.0
        unit.safe_margin = 0.9
        if unit.has_method("_build_collision_shape"):
            unit._build_collision_shape()

    unit.set_meta(TUNING_TAG, true)
    unit.queue_redraw()


func _process_harvest_effect(unit, delta: float) -> void:
    var instance_id: int = int(unit.get_instance_id())
    var is_harvesting: bool = (
        not bool(unit.dying)
        and bool(unit.visible)
        and not bool(unit.inside_refinery)
        and str(unit.harvester_state) == "harvest"
        and is_instance_valid(unit.harvest_target)
    )
    if not is_harvesting:
        _harvest_effect_timers[instance_id] = 0.0
        return

    var remaining: float = float(_harvest_effect_timers.get(instance_id, 0.0)) - delta
    if remaining > 0.0:
        _harvest_effect_timers[instance_id] = remaining
        return
    _harvest_effect_timers[instance_id] = 0.16

    if not is_instance_valid(unit.match_ref) or not is_instance_valid(unit.match_ref.effect_layer):
        return
    var target_position: Vector2 = unit.harvest_target.global_position
    var effect_position: Vector2 = unit.global_position.lerp(target_position, 0.68)
    effect_position += Vector2(_rng.randf_range(-7.0, 7.0), _rng.randf_range(-7.0, 2.0))
    var effect = CombatEffect.new()
    effect.z_index = 3
    unit.match_ref.effect_layer.add_child(effect)
    effect.global_position = effect_position
    effect.setup(
        "ore_harvest",
        Color("#E1BE43"),
        0.78,
        false,
        int(unit.get_instance_id()) ^ int(Time.get_ticks_usec())
    )


func _synchronize_building_damage(building) -> void:
    if building.stats.is_empty() or bool(building.destroyed):
        return
    var ratio: float = float(building.hp) / maxf(1.0, float(building.max_hp))
    var band: int = 2 if ratio <= 0.333 else (1 if ratio <= 0.666 else 0)
    var instance_id: int = int(building.get_instance_id())
    var previous_band: int = int(_building_damage_bands.get(instance_id, -1))
    if band != previous_band or int(building.damage_stage) != band:
        _building_damage_bands[instance_id] = band
        if building.has_method("_update_damage_visual"):
            building._update_damage_visual()

    if band == 0 and is_instance_valid(building.ra2_visual):
        var current_state: String = str(building.ra2_visual.current_state)
        if current_state == "damaged" and building.has_method("_update_ra2_visual_state"):
            building._update_ra2_visual_state(true)


func _sanitize_building_animation_once(building) -> void:
    if not is_instance_valid(building) or not is_instance_valid(building.ra2_visual):
        return
    var visual = building.ra2_visual
    if visual.has_meta(BUILDING_SANITIZED_TAG):
        return
    if not is_instance_valid(visual.base_sprite) or not is_instance_valid(visual.remap_sprite):
        return

    _remove_invalid_normal_tail(visual, "Operational", "DamagedOperational")
    _remove_invalid_normal_tail(visual, "Ready", "DamagedReady")
    visual.set_meta(BUILDING_SANITIZED_TAG, true)


func _remove_invalid_normal_tail(visual, normal_name: String, damaged_name: String) -> void:
    var base_frames: SpriteFrames = visual.base_sprite.sprite_frames
    var remap_frames: SpriteFrames = visual.remap_sprite.sprite_frames
    if base_frames == null or not base_frames.has_animation(normal_name):
        return
    var normal_count: int = base_frames.get_frame_count(normal_name)
    if normal_count <= 1:
        return

    var remove_tail: bool = false
    var definition: Dictionary = visual.animations.get(normal_name, {}) as Dictionary
    var source_variant: Variant = definition.get("source_indices", [])
    var source_indices: Array = source_variant as Array if source_variant is Array else []
    if not source_indices.is_empty():
        var tail_marker: String = str(source_indices[-1]).to_lower()
        remove_tail = tail_marker.contains("damaged") or tail_marker.contains("rubble")

    if not remove_tail and base_frames.has_animation(damaged_name):
        var damaged_count: int = base_frames.get_frame_count(damaged_name)
        if damaged_count > 0:
            var normal_texture: Texture2D = base_frames.get_frame_texture(normal_name, normal_count - 1)
            var damaged_texture: Texture2D = base_frames.get_frame_texture(damaged_name, 0)
            remove_tail = _textures_are_identical(normal_texture, damaged_texture)

    if not remove_tail:
        return
    base_frames.remove_frame(normal_name, normal_count - 1)
    if remap_frames != null and remap_frames.has_animation(normal_name):
        var remap_count: int = remap_frames.get_frame_count(normal_name)
        if remap_count >= normal_count:
            remap_frames.remove_frame(normal_name, remap_count - 1)


func _textures_are_identical(left: Texture2D, right: Texture2D) -> bool:
    if left == null or right == null or left.get_size() != right.get_size():
        return false
    var left_image: Image = left.get_image()
    var right_image: Image = right.get_image()
    if left_image == null or right_image == null:
        return false
    return left_image.get_data() == right_image.get_data()


func _prune_instance_dictionary(values: Dictionary) -> void:
    var live_ids: Dictionary = {}
    for harvester in _harvesters:
        if is_instance_valid(harvester):
            live_ids[int(harvester.get_instance_id())] = true
    for building in _buildings:
        if is_instance_valid(building):
            live_ids[int(building.get_instance_id())] = true
    for key in values.keys():
        if not live_ids.has(int(key)):
            values.erase(key)

extends "res://scripts/game/unit.gd"

const RA2Rules = preload("res://scripts/ra2/ra2_rules_adapter.gd")
const RA2CombatAudioRouter = preload("res://scripts/ra2/ra2_combat_audio.gd")

const AIRBORNE_GRAVITY := 420.0
const EXTERNAL_IMPULSE_DECAY := 310.0
const TERRAIN_POSE_RESPONSE := 11.0

var inside_tank_bunker := false
var tank_bunker_target
var terrain_ground_height: float = 0.0
var terrain_gradient: Vector2 = Vector2.ZERO
var airborne_height: float = 0.0
var airborne_velocity: float = 0.0
var airborne_roll: float = 0.0
var airborne_roll_velocity: float = 0.0
var external_impulse: Vector2 = Vector2.ZERO
var fallback_visual_base_position: Vector2 = Vector2.ZERO


func setup(next_match, next_map, next_unit_id, next_owner, world_position):
    super.setup(next_match, next_map, next_unit_id, next_owner, world_position)
    stats = RA2Rules.build_runtime_stats(stats, ra2_entity_id, str(stats.get("category", "vehicle")))
    stats["armor"] = float(stats.get("armor_value", 0.0))
    max_hp = float(stats.get("hp", max_hp))
    hp = max_hp
    max_shield = float(stats.get("shield", max_shield))
    shield = max_shield
    corpse_lifetime = 3.2 if str(stats.get("category", "infantry")) == "infantry" else 3.8
    guard_range = maxf(float(stats.get("range", 0.0)), float(stats.get("guard_range", guard_range)))
    var category: String = str(stats.get("category", "vehicle"))
    if category == "infantry":
        stats["collision_radius"] = 6.25 if unit_id == "rifle" else 6.75
        safe_margin = 0.72
    elif unit_id == "tank":
        stats["collision_radius"] = 16.0
        stats["radius"] = 15.0
        safe_margin = 0.9
    _build_collision_shape()
    if is_instance_valid(visual_root):
        fallback_visual_base_position = visual_root.position
    _update_terrain_pose(0.0, true)
    queue_redraw()


func _physics_process(delta):
    if inside_tank_bunker:
        velocity = Vector2.ZERO
        _update_terrain_pose(float(delta))
        return
    super._physics_process(delta)
    _process_external_impulse(float(delta))
    _update_terrain_pose(float(delta))


func _process_external_impulse(delta: float) -> void:
    if external_impulse.length_squared() <= 1.0:
        external_impulse = Vector2.ZERO
        return
    var candidate := global_position + external_impulse * delta
    var category := str(stats.get("category", "vehicle"))
    if not is_instance_valid(map_ref) or map_ref.is_cell_walkable(map_ref.world_to_cell(candidate), category):
        global_position = candidate
    else:
        external_impulse *= 0.32
    external_impulse = external_impulse.move_toward(Vector2.ZERO, EXTERNAL_IMPULSE_DECAY * delta)


func _update_terrain_pose(delta: float, snap_immediately: bool = false) -> void:
    if not is_instance_valid(map_ref):
        return
    var target_height := 0.0
    var target_gradient := Vector2.ZERO
    if map_ref.has_method("get_ground_sample"):
        var sample: Dictionary = map_ref.get_ground_sample(global_position)
        target_height = float(sample.get("height", 0.0))
        if str(stats.get("category", "vehicle")) == "vehicle":
            target_gradient = Vector2(sample.get("gradient", Vector2.ZERO))
    elif map_ref.has_method("get_ground_height"):
        target_height = float(map_ref.get_ground_height(global_position))

    if airborne_height > 0.0 or airborne_velocity > 0.0:
        airborne_velocity -= AIRBORNE_GRAVITY * delta
        airborne_height += airborne_velocity * delta
        airborne_roll += airborne_roll_velocity * delta
        airborne_roll_velocity = move_toward(airborne_roll_velocity, 0.0, 1.7 * delta)
        if airborne_height <= 0.0:
            var landing_speed := maxf(0.0, -airborne_velocity)
            airborne_height = 0.0
            airborne_velocity = 0.0
            airborne_roll_velocity = 0.0
            airborne_roll = lerpf(airborne_roll, 0.0, 0.72)
            if landing_speed > 245.0 and not dying:
                var landing_damage := (landing_speed - 245.0) * 0.16
                var display_armor := float(stats.get("armor", 0.0))
                stats["armor"] = 0.0
                super.take_damage(landing_damage, null)
                stats["armor"] = display_armor
    elif absf(airborne_roll) > 0.001:
        airborne_roll = move_toward(airborne_roll, 0.0, 2.8 * delta)

    if snap_immediately or delta <= 0.0:
        terrain_ground_height = target_height
        terrain_gradient = target_gradient
    else:
        var response := clampf(delta * TERRAIN_POSE_RESPONSE, 0.0, 1.0)
        terrain_ground_height = lerpf(terrain_ground_height, target_height, response)
        terrain_gradient = terrain_gradient.lerp(target_gradient, response)

    if is_instance_valid(ra2_visual) and ra2_visual.has_method("set_terrain_pose"):
        ra2_visual.set_terrain_pose(
            terrain_ground_height,
            terrain_gradient,
            airborne_height,
            airborne_roll
        )
    elif is_instance_valid(visual_root):
        visual_root.position = fallback_visual_base_position + Vector2(
            0.0,
            -terrain_ground_height - airborne_height
        )
        visual_root.rotation = clampf(-terrain_gradient.x * 0.18 + airborne_roll, -0.48, 0.48)
        visual_root.skew = clampf(terrain_gradient.y * 0.12, -0.20, 0.20)


func apply_terrain_impulse(planar_impulse: Vector2, lift_speed: float, roll_speed: float = 0.0) -> bool:
    if str(stats.get("category", "")) != "vehicle" or dying or inside_refinery or inside_repair_bay or inside_tank_bunker:
        return false
    external_impulse += planar_impulse.limit_length(190.0)
    airborne_velocity = maxf(airborne_velocity, maxf(0.0, lift_speed))
    airborne_height = maxf(airborne_height, 1.0)
    airborne_roll_velocity = clampf(airborne_roll_velocity + roll_speed, -3.2, 3.2)
    return true


func take_damage(amount, source = null):
    if inside_tank_bunker:
        return 0.0
    var resolved: float = RA2Rules.resolve_damage(source, self, float(amount))
    if resolved <= 0.0:
        return 0.0
    var display_armor: float = float(stats.get("armor", 0.0))
    stats["armor"] = 0.0
    var actual: float = float(super.take_damage(resolved, source))
    stats["armor"] = display_armor
    if actual > 0.0 and hp > 0.0 and not ra2_entity_id.is_empty():
        RA2CombatAudioRouter.play_entity_role(ra2_entity_id, "VoiceFeedback", global_position, match_ref, 180)
    if actual > 0.0 and is_instance_valid(source) and source.get("stats") is Dictionary:
        var source_stats: Dictionary = source.stats
        var blast_radius := float(source_stats.get("aoe_radius", 0.0))
        if blast_radius > 0.0 and str(stats.get("category", "")) == "vehicle":
            var away := source.global_position.direction_to(global_position)
            if away.length_squared() < 0.001:
                away = Vector2.RIGHT
            var instance_sign := -1.0 if int(get_instance_id()) % 2 == 0 else 1.0
            apply_terrain_impulse(
                away * clampf(actual * 0.72, 24.0, 125.0),
                clampf(actual * 0.86, 18.0, 150.0),
                instance_sign * clampf(actual * 0.012, 0.18, 1.15)
            )
    return actual


func _fire_at(target):
    var entity_id: String = ra2_entity_id
    ra2_entity_id = ""
    super._fire_at(target)
    ra2_entity_id = entity_id
    if not entity_id.is_empty():
        RA2CombatAudioRouter.play_weapon_report(entity_id, global_position, match_ref)


func _fire_at_position(target_position, forced_target = null):
    var entity_id: String = ra2_entity_id
    ra2_entity_id = ""
    super._fire_at_position(target_position, forced_target)
    ra2_entity_id = entity_id
    if not entity_id.is_empty():
        RA2CombatAudioRouter.play_weapon_report(entity_id, global_position, match_ref)


func _begin_death(source = null):
    if dying:
        return
    var entity_id: String = ra2_entity_id
    var death_position: Vector2 = global_position
    ra2_entity_id = ""
    super._begin_death(source)
    ra2_entity_id = entity_id
    if not entity_id.is_empty():
        RA2CombatAudioRouter.play_entity_role(entity_id, "DieSound", death_position, match_ref, 80)


func command_move(target_position, manual = true, queued = false):
    if str(stats.get("category", "")) == "vehicle" and unit_id == "tank" and is_instance_valid(match_ref):
        var candidate: Variant = match_ref.get_entity_at(Vector2(target_position), true)
        if is_instance_valid(candidate) and candidate.owner_id == owner_id and candidate.has_method("can_accept_tank") and candidate.can_accept_tank(self):
            _submit_order({"type": "tank_bunker", "target": candidate, "position": candidate.global_position, "manual": bool(manual)}, queued)
            return
    super.command_move(target_position, manual, queued)


func _activate_order(order):
    if str(order.get("type", "")) != "tank_bunker":
        super._activate_order(order)
        return
    active_order = order.duplicate()
    attack_target = null
    path = PackedVector2Array()
    path_index = 0
    velocity = Vector2.ZERO
    tank_bunker_target = active_order.get("target")
    if is_instance_valid(tank_bunker_target):
        var entry: Vector2 = Vector2(tank_bunker_target.get_garrison_entry_position(global_position))
        active_order["position"] = entry
        _set_path_to(entry)


func _process_active_order(delta):
    if str(active_order.get("type", "")) != "tank_bunker":
        super._process_active_order(delta)
        return
    var bunker: Variant = active_order.get("target")
    if not is_instance_valid(bunker) or not bunker.has_method("accept_tank"):
        tank_bunker_target = null
        _complete_active_order()
        return
    var entry: Vector2 = Vector2(bunker.get_garrison_entry_position(global_position))
    active_order["position"] = entry
    if global_position.distance_to(entry) <= 24.0:
        velocity = Vector2.ZERO
        path = PackedVector2Array()
        if bunker.accept_tank(self):
            inside_tank_bunker = true
            active_order = {}
        return
    if path.is_empty() or path_index >= path.size() or destination.distance_to(entry) > 3.0:
        _set_path_to(entry)
    _follow_path(delta)


func enter_tank_bunker(bunker) -> bool:
    if dying or inside_refinery or inside_repair_bay or inside_tank_bunker or not is_instance_valid(bunker):
        return false
    inside_tank_bunker = true
    tank_bunker_target = bunker
    velocity = Vector2.ZERO
    external_impulse = Vector2.ZERO
    airborne_height = 0.0
    airborne_velocity = 0.0
    airborne_roll = 0.0
    airborne_roll_velocity = 0.0
    active_order = {}
    order_queue.clear()
    path = PackedVector2Array()
    visible = false
    collision_layer = 0
    collision_mask = 0
    if is_instance_valid(collision_shape_node):
        collision_shape_node.set_deferred("disabled", true)
    queue_redraw()
    return true


func exit_tank_bunker(exit_position: Vector2) -> void:
    inside_tank_bunker = false
    tank_bunker_target = null
    global_position = exit_position
    visible = true
    collision_layer = saved_collision_layer
    collision_mask = saved_collision_mask
    if is_instance_valid(collision_shape_node):
        collision_shape_node.set_deferred("disabled", false)
    guard_post_position = exit_position
    combat_anchor = exit_position
    _update_terrain_pose(0.0, true)
    queue_redraw()

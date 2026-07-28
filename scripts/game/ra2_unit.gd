extends "res://scripts/game/unit.gd"

var inside_tank_bunker := false
var tank_bunker_target


func setup(next_match, next_map, next_unit_id, next_owner, world_position):
    super.setup(next_match, next_map, next_unit_id, next_owner, world_position)
    stats = RA2RulesAdapter.build_runtime_stats(stats, ra2_entity_id, str(stats.get("category", "vehicle")))
    max_hp = float(stats.get("hp", max_hp))
    hp = max_hp
    max_shield = float(stats.get("shield", max_shield))
    shield = max_shield
    corpse_lifetime = 3.2 if str(stats.get("category", "infantry")) == "infantry" else 3.8
    guard_range = maxf(float(stats.get("range", 0.0)), float(stats.get("guard_range", guard_range)))
    _build_collision_shape()
    queue_redraw()


func _physics_process(delta):
    if inside_tank_bunker:
        velocity = Vector2.ZERO
        return
    super._physics_process(delta)


func take_damage(amount, source = null):
    if inside_tank_bunker:
        return 0.0
    var resolved := RA2RulesAdapter.resolve_damage(source, self, float(amount))
    if resolved <= 0.0:
        return 0.0
    return super.take_damage(resolved, source)


func _fire_at(target):
    var entity_id := ra2_entity_id
    ra2_entity_id = ""
    super._fire_at(target)
    ra2_entity_id = entity_id
    if not entity_id.is_empty():
        RA2CombatAudio.play_weapon_report(entity_id, global_position, match_ref)


func _fire_at_position(target_position, forced_target = null):
    var entity_id := ra2_entity_id
    ra2_entity_id = ""
    super._fire_at_position(target_position, forced_target)
    ra2_entity_id = entity_id
    if not entity_id.is_empty():
        RA2CombatAudio.play_weapon_report(entity_id, global_position, match_ref)


func _begin_death(source = null):
    if dying:
        return
    var entity_id := ra2_entity_id
    var death_position := global_position
    ra2_entity_id = ""
    super._begin_death(source)
    ra2_entity_id = entity_id
    if not entity_id.is_empty():
        RA2CombatAudio.play_entity_role(entity_id, "DieSound", death_position, match_ref, 80)


func command_move(target_position, manual = true, queued = false):
    if str(stats.get("category", "")) == "vehicle" and unit_id == "tank" and is_instance_valid(match_ref):
        var candidate = match_ref.get_entity_at(Vector2(target_position), true)
        if is_instance_valid(candidate) and candidate.owner_id == owner_id and candidate.has_method("can_accept_tank") and candidate.can_accept_tank(self):
            _submit_order({
                "type": "tank_bunker",
                "target": candidate,
                "position": candidate.global_position,
                "manual": bool(manual)
            }, queued)
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
        var entry := tank_bunker_target.get_garrison_entry_position(global_position)
        active_order["position"] = entry
        _set_path_to(entry)


func _process_active_order(delta):
    if str(active_order.get("type", "")) != "tank_bunker":
        super._process_active_order(delta)
        return
    var bunker = active_order.get("target")
    if not is_instance_valid(bunker) or not bunker.has_method("accept_tank"):
        tank_bunker_target = null
        _complete_active_order()
        return
    var entry := bunker.get_garrison_entry_position(global_position)
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
    queue_redraw()

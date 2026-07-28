extends "res://scripts/game/building.gd"

var garrisoned_tank
var target_domains: Array[String] = ["ground"]


func setup(next_match, next_map, next_building_id, next_owner, cell, animate_construction = false):
    super.setup(next_match, next_map, next_building_id, next_owner, cell, animate_construction)
    var previous_footprint := footprint
    stats = RA2RulesAdapter.build_runtime_stats(stats, ra2_entity_id, "building")
    max_hp = float(stats.get("hp", max_hp))
    hp = max_hp
    max_shield = float(stats.get("shield", max_shield))
    shield = max_shield
    destruction_lifetime = 3.8
    var footprint_data: Array = stats.get("footprint", [previous_footprint.x, previous_footprint.y])
    var next_footprint := Vector2i(int(footprint_data[0]), int(footprint_data[1]))
    if next_footprint != previous_footprint:
        map_ref.vacate(self)
        footprint = next_footprint
        global_position = map_ref.footprint_center(origin_cell, footprint)
        map_ref.occupy(origin_cell, footprint, self)
        _build_collision_shape()
        rally_point = global_position + Vector2((footprint.x + 2) * map_ref.tile_px, 0)
        if is_instance_valid(ra2_visual):
            var runtime_width := float(ra2_profile.get("target_width", maxf(64.0, footprint.x * map_ref.tile_px * 1.42)))
            var ground_y := float(ra2_profile.get("ground_y", footprint.y * map_ref.tile_px * 0.34))
            var raw_offset: Variant = ra2_profile.get("offset", [0.0, 0.0])
            var offset := Vector2.ZERO
            if raw_offset is Array and raw_offset.size() >= 2:
                offset = Vector2(float(raw_offset[0]), float(raw_offset[1]))
            ra2_visual.configure_layout(runtime_width, ground_y, offset)
    _configure_defense_role()
    queue_redraw()


func _configure_defense_role() -> void:
    match ra2_entity_id:
        "NAFLAK", "NASAM", "GAPATS":
            target_domains = ["air"]
        "YAGGUN":
            target_domains = ["ground", "air"]
        "NATBNK":
            target_domains = []
            stats["damage"] = 0.0
            stats["range"] = 0.0
        _:
            target_domains = ["ground"]


func is_tank_bunker() -> bool:
    return ra2_entity_id == "NATBNK"


func is_defense_building():
    if is_tank_bunker():
        return false
    return super.is_defense_building()


func can_accept_tank(unit) -> bool:
    return (
        is_tank_bunker()
        and not destroyed
        and not selling
        and not is_instance_valid(garrisoned_tank)
        and is_instance_valid(unit)
        and unit.owner_id == owner_id
        and str(unit.unit_id) == "tank"
        and unit.has_method("enter_tank_bunker")
    )


func get_garrison_entry_position(from_position = Vector2.ZERO) -> Vector2:
    if is_instance_valid(service_anchor):
        return service_anchor.global_position
    var direction := global_position.direction_to(Vector2(from_position))
    if direction.length_squared() < 0.01:
        direction = Vector2.RIGHT
    return global_position + direction.normalized() * maxf(20.0, footprint.x * map_ref.tile_px * 0.55)


func accept_tank(unit) -> bool:
    if not can_accept_tank(unit) or not unit.enter_tank_bunker(self):
        return false
    garrisoned_tank = unit
    match_ref.units.erase(unit)
    match_ref.selected_entities.erase(unit)
    match_ref._invalidate_unit_spatial_hash()
    if is_instance_valid(match_ref.hud):
        match_ref.hud.set_selection(match_ref.selected_entities)
    if is_instance_valid(match_ref.overlay):
        match_ref.overlay.set_selected_entities(match_ref.selected_entities)
    set_special_active(true)
    queue_redraw()
    return true


func eject_garrisoned_tank() -> void:
    if not is_instance_valid(garrisoned_tank):
        garrisoned_tank = null
        return
    var tank = garrisoned_tank
    garrisoned_tank = null
    set_special_active(false)
    var exit_position := match_ref.find_clear_unit_position(get_garrison_entry_position(global_position + Vector2.RIGHT * 64.0), float(tank.stats.get("collision_radius", 16.0)), tank, "vehicle")
    if exit_position == Vector2.ZERO:
        exit_position = global_position + Vector2((footprint.x + 1) * map_ref.tile_px, 0.0)
    tank.exit_tank_bunker(exit_position)
    if not tank in match_ref.units:
        match_ref.units.append(tank)
    match_ref._invalidate_unit_spatial_hash()


func begin_sell(refund):
    eject_garrisoned_tank()
    return super.begin_sell(refund)


func take_damage(amount, source = null):
    if destroyed:
        return 0.0
    var resolved := RA2RulesAdapter.resolve_damage(source, self, float(amount))
    var entity_id := ra2_entity_id
    var was_destroyed := destroyed
    ra2_entity_id = ""
    var actual = super.take_damage(resolved, source)
    ra2_entity_id = entity_id
    if not was_destroyed and destroyed:
        eject_garrisoned_tank()
        if not entity_id.is_empty():
            RA2CombatAudio.play_entity_role(entity_id, "DieSound", global_position, match_ref, 80)
    return actual


func _is_valid_defense_target(candidate) -> bool:
    if not is_instance_valid(candidate) or candidate.owner_id == owner_id or candidate.hp <= 0:
        return false
    if not match_ref.are_enemies(owner_id, candidate.owner_id):
        return false
    var domain := "air" if RA2RulesAdapter.is_air_target(candidate) else "ground"
    return domain in target_domains


func _nearest_valid_defense_target(max_range: float):
    var best = null
    var best_distance := max_range * max_range
    for candidate in match_ref.units + match_ref.buildings:
        if not _is_valid_defense_target(candidate):
            continue
        var distance := global_position.distance_squared_to(candidate.global_position)
        if distance <= best_distance:
            best_distance = distance
            best = candidate
    return best


func _process_turret():
    if selling or is_under_construction() or target_domains.is_empty():
        return
    var attack_point := Vector2.ZERO
    var has_attack_point := false
    var damage_target = null
    if forced_attack_active:
        if forced_attack_target != null and not is_instance_valid(forced_attack_target):
            forced_attack_active = false
            forced_attack_target = null
        if forced_attack_active:
            if is_instance_valid(forced_attack_target):
                if not _is_valid_defense_target(forced_attack_target):
                    return
                forced_attack_position = forced_attack_target.global_position
                damage_target = forced_attack_target
            elif not "ground" in target_domains:
                return
            attack_point = forced_attack_position
            has_attack_point = true
            if global_position.distance_to(attack_point) > float(stats.get("range", 220.0)):
                return
            turret_facing = global_position.direction_to(attack_point)
    else:
        if is_instance_valid(target) and (not _is_valid_defense_target(target) or global_position.distance_to(target.global_position) > float(stats.get("range", 220.0))):
            target = null
        if not is_instance_valid(target) and scan_cooldown <= 0.0:
            scan_cooldown = 0.28
            target = _nearest_valid_defense_target(float(stats.get("range", 220.0)))
        if is_instance_valid(target):
            damage_target = target
            attack_point = target.global_position
            has_attack_point = true
            turret_facing = global_position.direction_to(attack_point)
    if not has_attack_point or fire_cooldown > 0.0:
        return
    fire_cooldown = float(stats.get("reload", 1.0))
    attack_animation_time = 0.30
    turret_visual_direction = _direction_index(turret_facing)
    if is_instance_valid(turret_sprite):
        turret_sprite.play("attack_%d" % turret_visual_direction)
    queue_redraw()
    if is_instance_valid(ra2_visual):
        ra2_visual.play_state("attack", turret_visual_direction, true)
    if not ra2_entity_id.is_empty():
        RA2CombatAudio.play_weapon_report(ra2_entity_id, global_position, match_ref)
    fired.emit(global_position + turret_facing * 18.0 + Vector2(0, -22), attack_point, owner_id)
    match_ref.spawn_muzzle_flash(global_position + turret_facing * 25.0 + Vector2(0, -22), Color("#FFD46B"))
    var shot_damage := float(stats.get("damage", 20.0))
    var shot_aoe := float(stats.get("aoe_radius", 0.0))
    if is_instance_valid(damage_target):
        match_ref.apply_weapon_damage(self, damage_target, shot_damage, shot_aoe)
    elif forced_attack_active:
        match_ref.apply_ground_damage(self, attack_point, shot_damage, shot_aoe, null)

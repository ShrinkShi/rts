extends CharacterBody2D

const SpriteSheetFactory = preload("res://scripts/game/sprite_sheet_factory.gd")
const CombatEffect = preload("res://scripts/game/combat_effect.gd")
const VisualProfileStore = preload("res://scripts/core/visual_profile_store.gd")

signal died(entity)
signal fired(from_point, to_point, owner_id)

const LAYER_INFANTRY = 1
const LAYER_VEHICLE = 2
const LAYER_BUILDING = 4
const LAYER_TREE = 8

var match_ref
var map_ref
var unit_id = "rifle"
var owner_id = 0
var stats = {}
var faction_id = "union"
var hp = 100.0
var max_hp = 100.0
var shield = 0.0
var max_shield = 0.0
var selected = false
var hover_state = ""
var path = PackedVector2Array()
var path_index = 0
var attack_target
var fire_cooldown = 0.0
var repath_cooldown = 0.0
var scan_cooldown = 0.0
var experience = 0.0
var veterancy = 0
var team_color = Color.WHITE
var carrying = 0
var harvest_timer = 0.0
var harvester_state = "seek"
var destination = Vector2.ZERO
var last_command_marker = Vector2.ZERO
var collision_shape_node
var crush_voice_cooldown = 0.0
var active_order = {}
var order_queue = []
var patrol_points = []
var patrol_index = 0
var patrol_direction = 1
var patrol_closed = false
var hold_position = Vector2.ZERO
var refinery_target
var refinery_dropoff = Vector2.ZERO
var harvest_target
var harvest_cell = Vector2i(-1, -1)
var harvest_approach_position = Vector2.ZERO
var inside_refinery = false
var unload_refinery
var stuck_elapsed = 0.0
var stuck_sample_position = Vector2.ZERO
var avoidance_direction = Vector2.ZERO
var recovery_attempts = 0
var finish_harvest_after_unload = false
var saved_collision_layer = 0
var saved_collision_mask = 0
var visual_sprite
var turret_sprite
var visual_state = ""
var visual_direction = 0
var turret_visual_direction = 0
var facing_direction = Vector2.RIGHT
var turret_facing_direction = Vector2.RIGHT
var attack_animation_time = 0.0
var dying = false
var death_elapsed = 0.0
var corpse_lifetime = 7.0
var damage_smoke
var idle_action_time = 0.0
var idle_trigger_time = 2.4
var retaliate_enabled = true
var support_enabled = true
var support_cooldown = 0.0
var inside_repair_bay = false
var repair_bay_target
var repair_entry_position = Vector2.ZERO
var behavior_cycle_index = 0
var visual_profile

func setup(next_match, next_map, next_unit_id, next_owner, world_position):
    match_ref = next_match
    map_ref = next_map
    unit_id = next_unit_id
    owner_id = next_owner
    faction_id = str(match_ref.get_player_data(owner_id).get("faction", "union"))
    stats = GameConfig.units.get(unit_id, {}).duplicate(true)
    visual_profile = VisualProfileStore.get_profile(unit_id)
    var modifiers = GameConfig.factions.get(faction_id, {}).get("unit_modifiers", {})
    stats.hp = float(stats.get("hp", 100)) * float(modifiers.get("hp", 1.0))
    stats.speed = float(stats.get("speed", 60.0)) * float(modifiers.get("speed", 1.0))
    stats.damage = float(stats.get("damage", 0)) * float(modifiers.get("damage", 1.0))
    max_hp = float(stats.hp)
    hp = max_hp
    max_shield = float(stats.get("shield", 0.0))
    shield = max_shield
    team_color = match_ref.get_player_color(owner_id)
    retaliate_enabled = bool(stats.get("retaliate_default", true))
    support_enabled = bool(stats.get("support_default", true))
    behavior_cycle_index = 0 if retaliate_enabled and support_enabled else (1 if retaliate_enabled else (2 if support_enabled else 3))
    global_position = world_position
    z_index = 0
    _build_collision_shape()
    _build_visual()
    queue_redraw()


func _build_visual():
    visual_sprite = AnimatedSprite2D.new()
    visual_sprite.name = "AnimatedVisual"
    visual_sprite.sprite_frames = SpriteSheetFactory.get_unit_frames(unit_id)
    visual_sprite.centered = true
    visual_sprite.show_behind_parent = true
    visual_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    var base_visual_position = Vector2(0, -13 if str(stats.get("category", "infantry")) == "infantry" else -11)
    var target_scale = 0.72 if str(stats.get("category", "infantry")) == "infantry" else 0.88
    if unit_id == "rifle":
        target_scale = 0.58
        base_visual_position = Vector2(0, -16)
    elif unit_id == "tank":
        target_scale = 0.52
        base_visual_position = Vector2(0, -12)
    elif unit_id == "harvester":
        target_scale = 0.94
    visual_sprite.position = base_visual_position + visual_profile.visual_offset
    visual_sprite.scale = Vector2.ONE * target_scale * visual_profile.visual_scale_multiplier
    visual_sprite.material = SpriteSheetFactory.create_team_material(team_color)
    add_child(visual_sprite)

    if unit_id == "tank":
        turret_sprite = AnimatedSprite2D.new()
        turret_sprite.name = "TurretVisual"
        turret_sprite.sprite_frames = SpriteSheetFactory.get_tank_turret_frames()
        turret_sprite.centered = true
        turret_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        # Both atlases are normalized around the same turret-ring pivot.
        turret_sprite.position = visual_sprite.position + visual_profile.turret_offset
        turret_sprite.scale = visual_sprite.scale * visual_profile.turret_scale_multiplier
        turret_sprite.z_index = 2
        turret_sprite.material = SpriteSheetFactory.create_team_material(team_color)
        add_child(turret_sprite)
    _play_visual_animation("stand", true)

func _direction_index(direction):
    if Vector2(direction).length_squared() < 0.001:
        return visual_direction
    var angle = fposmod(Vector2(direction).angle(), TAU)
    return int(round(angle / (TAU / 8.0))) % 8

func _play_visual_animation(state_name, restart = false):
    if not is_instance_valid(visual_sprite):
        return
    if unit_id == "tank":
        var chassis_state = "death" if state_name == "death" else ("move" if velocity.length_squared() > 20.0 else "stand")
        var chassis_animation = "%s_%d" % [chassis_state, visual_direction]
        if visual_sprite.animation != chassis_animation or restart:
            visual_sprite.play(chassis_animation)
        if is_instance_valid(turret_sprite):
            turret_sprite.visible = state_name != "death"
            if turret_sprite.visible:
                var turret_state = "attack" if state_name == "attack" else "stand"
                var turret_animation = "%s_%d" % [turret_state, turret_visual_direction]
                if turret_sprite.animation != turret_animation or restart:
                    turret_sprite.play(turret_animation)
        visual_state = state_name
        return
    var animation_name = "%s_%d" % [state_name, visual_direction]
    if visual_sprite.animation != animation_name or restart:
        visual_sprite.play(animation_name)
    visual_state = state_name

func _update_visual_state(delta):
    if not is_instance_valid(visual_sprite):
        return
    attack_animation_time = max(0.0, attack_animation_time - delta)
    idle_action_time = max(0.0, idle_action_time - delta)
    idle_trigger_time = max(0.0, idle_trigger_time - delta)
    if dying:
        _play_visual_animation("death")
        return
    var next_state = "stand"
    if attack_animation_time > 0.0:
        next_state = "attack"
    elif velocity.length_squared() > 20.0:
        next_state = "move"
        facing_direction = velocity.normalized()
        idle_trigger_time = 2.4
    else:
        if idle_trigger_time <= 0.0 and idle_action_time <= 0.0:
            idle_action_time = 1.1
            idle_trigger_time = 3.2 + float(get_instance_id() % 17) * 0.08
        if idle_action_time > 0.0:
            next_state = "idle"
        if is_instance_valid(attack_target) and unit_id != "tank":
            facing_direction = global_position.direction_to(attack_target.global_position)

    var next_direction = _direction_index(facing_direction)
    var direction_changed = next_direction != visual_direction
    visual_direction = next_direction

    var turret_changed = false
    if unit_id == "tank":
        if is_instance_valid(attack_target):
            turret_facing_direction = global_position.direction_to(attack_target.global_position)
        elif str(active_order.get("type", "")) == "force_attack":
            var force_target = active_order.get("target")
            var force_position = force_target.global_position if is_instance_valid(force_target) else Vector2(active_order.get("position", global_position + facing_direction))
            turret_facing_direction = global_position.direction_to(force_position)
        else:
            # With no live attack/force-fire target, the turret immediately follows
            # the chassis direction instead of retaining the last firing angle.
            turret_facing_direction = facing_direction
        var next_turret_direction = _direction_index(turret_facing_direction)
        turret_changed = next_turret_direction != turret_visual_direction
        turret_visual_direction = next_turret_direction

    if next_state != visual_state or direction_changed or turret_changed:
        _play_visual_animation(next_state, direction_changed or turret_changed)

func _update_damage_smoke():
    if dying or str(stats.get("category", "infantry")) != "vehicle":
        if is_instance_valid(damage_smoke):
            damage_smoke.queue_free()
            damage_smoke = null
        return
    var should_smoke = max_hp > 0.0 and hp / max_hp <= 0.34
    if should_smoke and not is_instance_valid(damage_smoke):
        damage_smoke = CombatEffect.new()
        damage_smoke.z_index = 4
        add_child(damage_smoke)
        damage_smoke.position = Vector2(0, -25)
        damage_smoke.setup("smoke", Color("#3D4448"), 0.9, true, get_instance_id())
    elif not should_smoke and is_instance_valid(damage_smoke):
        damage_smoke.queue_free()
        damage_smoke = null

func _process_death(delta):
    death_elapsed += delta
    velocity = Vector2.ZERO
    _update_visual_state(delta)
    if is_instance_valid(visual_sprite):
        if death_elapsed > corpse_lifetime - 1.2:
            visual_sprite.modulate.a = clamp((corpse_lifetime - death_elapsed) / 1.2, 0.0, 1.0)
            if is_instance_valid(turret_sprite):
                turret_sprite.modulate.a = visual_sprite.modulate.a
    queue_redraw()
    if death_elapsed >= corpse_lifetime:
        queue_free()

func _spawn_death_effect():
    if not is_instance_valid(match_ref) or not is_instance_valid(match_ref.effect_layer):
        return
    var effect = CombatEffect.new()
    match_ref.effect_layer.add_child(effect)
    effect.global_position = global_position + Vector2(0, -8)
    var vehicle = str(stats.get("category", "infantry")) == "vehicle"
    effect.setup("explosion" if vehicle else "smoke", team_color, 1.35 if vehicle else 0.55, false, get_instance_id())

func _begin_death(source = null):
    if dying:
        return
    dying = true
    hp = 0.0
    velocity = Vector2.ZERO
    attack_target = null
    repair_bay_target = null
    inside_repair_bay = false
    active_order = {}
    order_queue.clear()
    path = PackedVector2Array()
    collision_layer = 0
    collision_mask = 0
    if is_instance_valid(collision_shape_node):
        collision_shape_node.set_deferred("disabled", true)
    if is_instance_valid(damage_smoke):
        damage_smoke.queue_free()
        damage_smoke = null
    if is_instance_valid(source) and source.has_method("gain_experience"):
        source.gain_experience(max_hp)
    _spawn_death_effect()
    visual_direction = _direction_index(facing_direction)
    _play_visual_animation("death", true)
    died.emit(self)
    call_deferred("_move_corpse_to_effect_layer")
    queue_redraw()

func _move_corpse_to_effect_layer():
    if not dying or not is_instance_valid(match_ref) or not is_instance_valid(match_ref.effect_layer):
        return
    if get_parent() != match_ref.effect_layer:
        reparent(match_ref.effect_layer, true)

func _build_collision_shape():
    motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
    max_slides = 8
    collision_shape_node = CollisionShape2D.new()
    var circle = CircleShape2D.new()
    circle.radius = max(7.0, float(stats.get("collision_radius", stats.get("radius", 12.0))) * 0.96)
    collision_shape_node.shape = circle
    add_child(collision_shape_node)
    safe_margin = 1.35
    var category = str(stats.get("category", "infantry"))
    collision_priority = 1.0 if category == "infantry" else 1.35
    if category == "infantry":
        collision_layer = LAYER_INFANTRY
        collision_mask = LAYER_INFANTRY | LAYER_VEHICLE | LAYER_BUILDING
    else:
        collision_layer = LAYER_VEHICLE
        # 可碾压载具需要穿过敌方步兵才能触发碾压，其余车辆与步兵互相阻挡。
        collision_mask = LAYER_VEHICLE | LAYER_BUILDING | LAYER_TREE
        if not bool(stats.get("can_crush", false)):
            collision_mask |= LAYER_INFANTRY
    saved_collision_layer = collision_layer
    saved_collision_mask = collision_mask
    stuck_sample_position = global_position

func _physics_process(delta):
    if dying:
        _process_death(delta)
        return
    fire_cooldown = max(0.0, fire_cooldown - delta)
    repath_cooldown = max(0.0, repath_cooldown - delta)
    scan_cooldown = max(0.0, scan_cooldown - delta)
    crush_voice_cooldown = max(0.0, crush_voice_cooldown - delta)
    support_cooldown = max(0.0, support_cooldown - delta)
    if inside_repair_bay:
        velocity = Vector2.ZERO
        _update_visual_state(delta)
        _update_damage_smoke()
        return
    if inside_refinery:
        velocity = Vector2.ZERO
        _update_visual_state(delta)
        return

    if unit_id == "harvester" and (active_order.is_empty() or str(active_order.get("type", "")) == "harvest"):
        _process_harvester(delta)
    elif not active_order.is_empty():
        _process_active_order(delta)
    elif unit_id == "harvester":
        _process_harvester(delta)
    else:
        _process_idle_combat(delta)
    _resolve_unit_overlaps()
    _process_crushing()
    _update_visual_state(delta)
    _update_damage_smoke()

func _process_active_order(delta):
    var order_type = str(active_order.get("type", ""))
    if order_type == "move":
        if _follow_path(delta):
            _complete_active_order()
    elif order_type == "attack":
        if not is_instance_valid(attack_target):
            _complete_active_order()
        else:
            _process_attack_target(delta, true)
    elif order_type == "attack_move":
        _process_attack_move(delta)
    elif order_type == "patrol":
        _process_patrol(delta)
    elif order_type == "hold":
        _process_hold(delta)
    elif order_type == "force_attack":
        _process_force_attack(delta)
    elif order_type == "repair":
        _process_repair_order(delta)
    elif order_type == "stop":
        velocity = Vector2.ZERO
    else:
        _complete_active_order()

func _process_idle_combat(delta):
    if not is_combat_unit():
        velocity = Vector2.ZERO
        return
    if is_instance_valid(attack_target):
        _process_attack_target(delta, true)
        return
    if scan_cooldown <= 0.0:
        scan_cooldown = 0.4
        attack_target = match_ref.find_nearest_enemy(owner_id, global_position, float(stats.get("range", 0.0)) * 1.18)
    if is_instance_valid(attack_target):
        _process_attack_target(delta, true)
    else:
        velocity = Vector2.ZERO

func _process_attack_move(delta):
    var target_position = Vector2(active_order.get("position", global_position))
    if is_instance_valid(attack_target):
        _process_attack_target(delta, true)
        return
    if scan_cooldown <= 0.0:
        scan_cooldown = 0.25
        var scan_range = max(float(stats.get("range", 0.0)) * 1.35, float(stats.get("sight", 7)) * map_ref.tile_px)
        attack_target = match_ref.find_nearest_enemy(owner_id, global_position, scan_range)
        if is_instance_valid(attack_target):
            return
    if destination.distance_to(target_position) > 2.0 or path.is_empty():
        _set_path_to(target_position)
    if _follow_path(delta):
        _complete_active_order()

func _process_patrol(delta):
    if is_instance_valid(attack_target):
        _process_attack_target(delta, true)
        return
    if scan_cooldown <= 0.0:
        scan_cooldown = 0.3
        var scan_range = max(float(stats.get("range", 0.0)) * 1.3, float(stats.get("sight", 7)) * map_ref.tile_px)
        attack_target = match_ref.find_nearest_enemy(owner_id, global_position, scan_range)
        if is_instance_valid(attack_target):
            return
    if patrol_points.is_empty():
        _complete_active_order()
        return
    patrol_index = clamp(patrol_index, 0, patrol_points.size() - 1)
    var target_position = Vector2(patrol_points[patrol_index])
    if destination.distance_to(target_position) > 2.0 or path.is_empty():
        _set_path_to(target_position)
    if not _follow_path(delta):
        return
    if patrol_points.size() <= 1:
        velocity = Vector2.ZERO
        return
    if patrol_closed:
        patrol_index = (patrol_index + 1) % patrol_points.size()
    else:
        if patrol_index >= patrol_points.size() - 1:
            patrol_direction = -1
        elif patrol_index <= 0:
            patrol_direction = 1
        patrol_index += patrol_direction
    active_order["position"] = Vector2(patrol_points[patrol_index])
    _set_path_to(Vector2(patrol_points[patrol_index]))

func _process_force_attack(delta):
    if not is_combat_unit():
        _complete_active_order()
        return
    var forced_target = active_order.get("target")
    var target_position = Vector2(active_order.get("position", global_position))
    if is_instance_valid(forced_target):
        target_position = forced_target.global_position
        active_order["position"] = target_position
    var range_value = float(stats.get("range", 0.0))
    var distance = global_position.distance_to(target_position)
    facing_direction = global_position.direction_to(target_position)
    if distance <= range_value:
        velocity = Vector2.ZERO
        if fire_cooldown <= 0.0:
            _fire_at_position(target_position, forced_target)
    else:
        if repath_cooldown <= 0.0:
            _set_path_to(target_position)
            repath_cooldown = 0.45
        _follow_path(delta)

func _process_repair_order(delta):
    if str(stats.get("category", "infantry")) != "vehicle":
        _complete_active_order()
        return
    var bay = active_order.get("target")
    if not is_instance_valid(bay) or not bay.has_method("accept_vehicle_for_repair"):
        _complete_active_order()
        return
    repair_bay_target = bay
    var entry = bay.get_service_entry_position(global_position)
    active_order["position"] = entry
    if global_position.distance_to(entry) <= 25.0:
        velocity = Vector2.ZERO
        path = PackedVector2Array()
        if bay.accept_vehicle_for_repair(self):
            inside_repair_bay = true
        return
    if path.is_empty() or path_index >= path.size() or destination.distance_to(entry) > 3.0:
        _set_path_to(entry)
    _follow_path(delta)

func _process_hold(delta):
    velocity = Vector2.ZERO
    if is_instance_valid(attack_target):
        if global_position.distance_to(attack_target.global_position) <= float(stats.get("range", 0.0)):
            _process_attack_target(delta, false)
        else:
            attack_target = null
    elif scan_cooldown <= 0.0 and is_combat_unit():
        scan_cooldown = 0.25
        attack_target = match_ref.find_nearest_enemy(owner_id, hold_position, float(stats.get("range", 0.0)))

func _process_attack_target(delta, allow_chase = true):
    if not is_instance_valid(attack_target):
        return
    if attack_target.owner_id == owner_id or attack_target.hp <= 0:
        attack_target = null
        return
    var target_direction = global_position.direction_to(attack_target.global_position)
    if unit_id == "tank":
        turret_facing_direction = target_direction
    else:
        facing_direction = target_direction
    var range_value = float(stats.get("range", 0.0))
    var distance = global_position.distance_to(attack_target.global_position)
    if distance <= range_value:
        velocity = Vector2.ZERO
        if fire_cooldown <= 0.0:
            _fire_at(attack_target)
    elif allow_chase:
        if repath_cooldown <= 0.0:
            _set_path_to(attack_target.global_position)
            repath_cooldown = 0.45
        _follow_path(delta)
    else:
        velocity = Vector2.ZERO
        attack_target = null

func _fire_at(target):
    if not is_instance_valid(target):
        return
    fire_cooldown = float(stats.get("reload", 1.0))
    var shot_direction = global_position.direction_to(target.global_position)
    if unit_id == "tank":
        turret_facing_direction = shot_direction
        turret_visual_direction = _direction_index(turret_facing_direction)
    else:
        facing_direction = shot_direction
        visual_direction = _direction_index(facing_direction)
    attack_animation_time = max(0.28, min(0.55, fire_cooldown * 0.62))
    _play_visual_animation("attack", true)
    fired.emit(global_position, target.global_position, owner_id)
    var veterancy_bonus = 1.0 + veterancy * 0.22
    var damage = float(stats.get("damage", 0)) * veterancy_bonus
    match_ref.apply_weapon_damage(self, target, damage, float(stats.get("aoe_radius", 0.0)))

func _fire_at_position(target_position, forced_target = null):
    fire_cooldown = float(stats.get("reload", 1.0))
    var shot_direction = global_position.direction_to(target_position)
    if unit_id == "tank":
        turret_facing_direction = shot_direction
        turret_visual_direction = _direction_index(turret_facing_direction)
    else:
        facing_direction = shot_direction
        visual_direction = _direction_index(facing_direction)
    attack_animation_time = max(0.28, min(0.55, fire_cooldown * 0.62))
    _play_visual_animation("attack", true)
    fired.emit(global_position, target_position, owner_id)
    var veterancy_bonus = 1.0 + veterancy * 0.22
    var damage = float(stats.get("damage", 0)) * veterancy_bonus
    if is_instance_valid(forced_target) and forced_target.has_method("take_damage"):
        forced_target.take_damage(damage, self)
    match_ref.apply_ground_damage(self, target_position, damage, float(stats.get("aoe_radius", 0.0)), forced_target)

func _set_path_to(target_position):
    destination = target_position
    path = map_ref.find_path_for_unit(global_position, target_position, str(stats.get("category", "vehicle")))
    path_index = 0

func _follow_path(delta):
    if path.is_empty() or path_index >= path.size():
        velocity = Vector2.ZERO
        return true
    var next_point = path[path_index]
    var arrival_radius = max(8.0, float(stats.get("radius", 12.0)) * 0.62)
    if global_position.distance_to(next_point) < arrival_radius:
        path_index += 1
        if path_index >= path.size():
            # Do not hard-snap every member of a formation to the A* endpoint.
            # Hard snapping was the main source of vehicles occupying exactly the
            # same coordinates after reaching a shared destination.
            velocity = Vector2.ZERO
            _reset_stuck_tracking()
            return true
        next_point = path[path_index]
    var desired_direction = global_position.direction_to(next_point)
    avoidance_direction = _calculate_separation_vector()
    var steering = desired_direction + avoidance_direction * 0.82
    if steering.length_squared() < 0.01:
        steering = desired_direction
    var terrain_speed = float(map_ref.get_movement_speed_multiplier(global_position)) if map_ref.has_method("get_movement_speed_multiplier") else 1.0
    velocity = steering.normalized() * float(stats.get("speed", 60.0)) * terrain_speed
    if velocity.length_squared() > 1.0:
        facing_direction = velocity.normalized()
    var before = global_position
    move_and_slide()
    _update_stuck_recovery(delta, before, next_point)
    return false

func _pair_separation_direction(other):
    var own_id = int(get_instance_id())
    var other_id = int(other.get_instance_id())
    var low_id = min(own_id, other_id)
    var high_id = max(own_id, other_id)
    var angle = float((low_id * 59 + high_id * 17) % 360) * PI / 180.0
    var base = Vector2.RIGHT.rotated(angle)
    return base if own_id > other_id else -base

func _calculate_separation_vector():
    if not is_instance_valid(match_ref):
        return Vector2.ZERO
    var result = Vector2.ZERO
    var own_radius = float(stats.get("collision_radius", stats.get("radius", 12.0)))
    var desired = Vector2.ZERO
    if not path.is_empty() and path_index < path.size():
        desired = global_position.direction_to(path[path_index])
    var query_radius = own_radius * 4.0 + 72.0
    var nearby_units = match_ref.query_units_in_radius(global_position, query_radius, self) if match_ref.has_method("query_units_in_radius") else match_ref.units
    for other in nearby_units:
        if not is_instance_valid(other) or other == self or bool(other.inside_refinery) or bool(other.inside_repair_bay) or bool(other.dying):
            continue
        if bool(stats.get("can_crush", false)) and match_ref.are_enemies(owner_id, other.owner_id) and bool(other.stats.get("crushable", false)):
            continue
        var other_radius = float(other.stats.get("collision_radius", other.stats.get("radius", 12.0)))
        var minimum = own_radius + other_radius + 4.0
        var offset = global_position - other.global_position
        var distance = offset.length()
        if distance >= minimum * 2.0:
            continue
        var radial = Vector2.ZERO
        if distance <= 0.01:
            radial = _pair_separation_direction(other)
            distance = 0.01
        else:
            radial = offset / distance
        var strength = clamp((minimum * 2.0 - distance) / max(1.0, minimum), 0.0, 1.8)
        var tangent = radial.orthogonal()
        # Stable handedness breaks face-to-face symmetry without random jitter.
        if get_instance_id() < other.get_instance_id():
            tangent = -tangent
        var head_on = 0.0
        if desired.length_squared() > 0.01 and other.velocity.length_squared() > 1.0:
            head_on = max(0.0, desired.dot(-other.velocity.normalized()))
        result += radial * strength + tangent * strength * (0.28 + head_on * 0.48)
    return result.limit_length(1.75)

func _resolve_unit_overlaps():
    if not is_instance_valid(match_ref) or inside_refinery or inside_repair_bay or dying:
        return
    var own_radius = float(stats.get("collision_radius", stats.get("radius", 12.0)))
    # Multiple small passes are safer than one large teleport and prevent clusters
    # from settling into a mutually-overlapping equilibrium.
    for _pass in range(3):
        var correction = Vector2.ZERO
        var overlap_count = 0
        var query_radius = own_radius * 3.0 + 56.0
        var nearby_units = match_ref.query_units_in_radius(global_position, query_radius, self) if match_ref.has_method("query_units_in_radius") else match_ref.units
        for other in nearby_units:
            if not is_instance_valid(other) or other == self or bool(other.inside_refinery) or bool(other.inside_repair_bay) or bool(other.dying):
                continue
            if bool(stats.get("can_crush", false)) and match_ref.are_enemies(owner_id, other.owner_id) and bool(other.stats.get("crushable", false)):
                continue
            var other_radius = float(other.stats.get("collision_radius", other.stats.get("radius", 12.0)))
            var minimum = own_radius + other_radius + 1.5
            var offset = global_position - other.global_position
            var distance = offset.length()
            if distance >= minimum:
                continue
            var normal = Vector2.ZERO
            if distance <= 0.01:
                normal = _pair_separation_direction(other)
            else:
                normal = offset / distance
            var tangent = normal.orthogonal() * (-1.0 if get_instance_id() < other.get_instance_id() else 1.0)
            var depth = minimum - max(distance, 0.01)
            correction += normal * depth * 0.86 + tangent * min(depth, 7.0) * 0.22
            overlap_count += 1
        if overlap_count == 0:
            break
        var candidate = global_position + (correction / float(overlap_count)).limit_length(10.0)
        var cell = map_ref.world_to_cell(candidate)
        if map_ref.is_cell_walkable(cell, str(stats.get("category", "vehicle"))):
            global_position = candidate
        else:
            break

func _update_stuck_recovery(delta, before, next_point):
    if path.size() > 512:
        _set_path_to(destination)
        recovery_attempts = 0
    var moved = before.distance_to(global_position)
    if moved >= 0.65 or global_position.distance_to(next_point) < 12.0:
        _reset_stuck_tracking()
        return
    stuck_elapsed += delta
    if stuck_elapsed < 0.75:
        return
    stuck_elapsed = 0.0
    recovery_attempts += 1
    var perpendicular = global_position.direction_to(next_point).orthogonal()
    if recovery_attempts % 2 == 0:
        perpendicular = -perpendicular
    var recovery_target = global_position + perpendicular * (18.0 + min(30.0, recovery_attempts * 6.0))
    var recovery_cell = map_ref.nearest_walkable_cell(map_ref.world_to_cell(recovery_target), str(stats.get("category", "vehicle")))
    if recovery_cell.x >= 0:
        var detour = map_ref.find_path_for_unit(global_position, map_ref.cell_to_world(recovery_cell), str(stats.get("category", "vehicle")))
        if not detour.is_empty():
            var remaining = PackedVector2Array()
            for index in range(path_index, path.size()):
                remaining.append(path[index])
            path = detour
            path.append_array(remaining)
            path_index = 0
    if unit_id == "harvester" and recovery_attempts >= 3:
        # Do not let a blocked ore slot or refinery entrance trap a harvester forever.
        path = PackedVector2Array()
        path_index = 0
        destination = Vector2.ZERO
        if harvester_state == "to_ore":
            harvest_target = null
            harvest_cell = Vector2i(-1, -1)
            harvest_approach_position = Vector2.ZERO
            harvester_state = "seek"
        elif harvester_state == "return":
            refinery_dropoff = Vector2.ZERO
        recovery_attempts = 0
        return
    if recovery_attempts >= 4:
        _set_path_to(destination)
        recovery_attempts = 0

func _reset_stuck_tracking():
    stuck_elapsed = 0.0
    recovery_attempts = 0
    stuck_sample_position = global_position

func _process_crushing():
    if not bool(stats.get("can_crush", false)):
        return
    if velocity.length() < float(stats.get("speed", 60.0)) * 0.18:
        return
    var own_radius = float(stats.get("radius", 12.0))
    var crush_radius = own_radius * 2.0 + 36.0
    var nearby_units = match_ref.query_units_in_radius(global_position, crush_radius, self) if match_ref.has_method("query_units_in_radius") else match_ref.units.duplicate()
    for other in nearby_units:
        if not is_instance_valid(other) or other == self:
            continue
        if not match_ref.are_enemies(owner_id, other.owner_id):
            continue
        if not bool(other.stats.get("crushable", false)):
            continue
        var other_radius = float(other.stats.get("radius", 10.0))
        if global_position.distance_to(other.global_position) <= own_radius * 0.72 + other_radius * 0.72:
            other.take_damage(other.max_hp + float(other.stats.get("armor", 0)) + 1.0, self)
            if owner_id == 0 and crush_voice_cooldown <= 0.0:
                crush_voice_cooldown = 2.0
                VoiceManager.speak(unit_id, "crush")

func command_move(target_position, manual = true, queued = false):
    _submit_order({"type": "move", "position": target_position, "manual": manual}, queued)

func command_attack(target, queued = false):
    if not is_instance_valid(target) or target.owner_id == owner_id:
        return
    if target.has_method("is_resource_entity") and target.is_resource_entity():
        return
    _submit_order({"type": "attack", "target": target, "manual": true}, queued)

func command_attack_move(target_position, queued = false):
    if not is_combat_unit():
        command_move(target_position, true, queued)
        return
    _submit_order({"type": "attack_move", "position": target_position, "manual": true}, queued)

func command_patrol(target_position, append_to_route = false):
    if append_to_route and is_patrolling():
        return _append_patrol_point(target_position)
    var point = Vector2(target_position)
    _submit_order({
        "type": "patrol",
        "position": point,
        "patrol_points": [point],
        "patrol_closed": false,
        "manual": true
    }, false)
    return false

func _append_patrol_point(target_position):
    var point = Vector2(target_position)
    if patrol_points.size() >= 2 and point.distance_to(Vector2(patrol_points[0])) <= 18.0:
        patrol_closed = true
        active_order["patrol_closed"] = true
        active_order["patrol_points"] = patrol_points.duplicate()
        return true
    if not patrol_points.is_empty() and point.distance_to(Vector2(patrol_points[-1])) <= 10.0:
        return false
    patrol_points.append(point)
    active_order["patrol_points"] = patrol_points.duplicate()
    if patrol_points.size() == 2 and path.is_empty():
        patrol_index = 1
        active_order["position"] = point
        _set_path_to(point)
    return false

func is_patrolling():
    return str(active_order.get("type", "")) == "patrol"

func get_patrol_point_count():
    return patrol_points.size() if is_patrolling() else 0

func get_patrol_route():
    return {
        "active": is_patrolling(),
        "points": patrol_points.duplicate(),
        "closed": patrol_closed
    }

func command_force_attack(target_or_position, queued = false):
    if not is_combat_unit():
        return
    var order = {"type": "force_attack", "manual": true}
    if target_or_position is Vector2:
        order["position"] = Vector2(target_or_position)
    elif is_instance_valid(target_or_position):
        order["target"] = target_or_position
        order["position"] = target_or_position.global_position
    else:
        return
    _submit_order(order, queued)

func command_repair(repair_bay, queued = false):
    if str(stats.get("category", "infantry")) != "vehicle" or not is_instance_valid(repair_bay):
        return
    _submit_order({"type": "repair", "target": repair_bay, "position": repair_bay.global_position, "manual": true}, queued)

func cycle_behavior_policy():
    behavior_cycle_index = (behavior_cycle_index + 1) % 4
    match behavior_cycle_index:
        0:
            retaliate_enabled = true
            support_enabled = true
        1:
            retaliate_enabled = true
            support_enabled = false
        2:
            retaliate_enabled = false
            support_enabled = true
        3:
            retaliate_enabled = false
            support_enabled = false
    return get_behavior_policy_name()

func get_behavior_policy_name():
    if retaliate_enabled and support_enabled:
        return "反击并支援"
    if retaliate_enabled:
        return "仅反击"
    if support_enabled:
        return "仅支援"
    return "被动"

func can_receive_support_order():
    if dying or inside_refinery or inside_repair_bay or not is_combat_unit() or not support_enabled:
        return false
    var order_type = str(active_order.get("type", ""))
    return active_order.is_empty() or order_type == "stop"

func support_ally_against(enemy):
    if support_cooldown > 0.0 or not can_receive_support_order() or not is_instance_valid(enemy):
        return false
    support_cooldown = 1.2
    command_attack(enemy, false)
    return true

func enter_repair_bay(bay):
    if inside_repair_bay or inside_refinery or not is_instance_valid(bay):
        return false
    inside_repair_bay = true
    repair_bay_target = bay
    velocity = Vector2.ZERO
    visible = false
    collision_layer = 0
    collision_mask = 0
    if is_instance_valid(collision_shape_node):
        collision_shape_node.set_deferred("disabled", true)
    queue_redraw()
    return true

func exit_repair_bay(exit_position):
    inside_repair_bay = false
    repair_bay_target = null
    global_position = exit_position
    visible = true
    collision_layer = saved_collision_layer
    collision_mask = saved_collision_mask
    if is_instance_valid(collision_shape_node):
        collision_shape_node.set_deferred("disabled", false)
    path = PackedVector2Array()
    path_index = 0
    destination = Vector2.ZERO
    _complete_active_order()
    queue_redraw()

func command_harvest(target = null, queued = false):
    if unit_id != "harvester":
        return
    var order = {"type": "harvest", "manual": true}
    if is_instance_valid(target) and target.has_method("is_resource_entity"):
        if target.is_depleted():
            return
        order["target"] = target
        order["position"] = target.global_position
    _submit_order(order, queued)

func command_stop():
    order_queue.clear()
    _reset_harvester_assignment()
    _activate_order({"type": "stop", "manual": true})

func command_hold():
    order_queue.clear()
    _reset_harvester_assignment()
    _activate_order({"type": "hold", "position": global_position, "manual": true})

func _submit_order(order, queued):
    var active_type = str(active_order.get("type", ""))
    if queued and not active_order.is_empty() and active_type != "stop" and active_type != "hold":
        if order_queue.size() < 64:
            order_queue.append(order)
        return
    if queued and active_order.is_empty() and not order_queue.is_empty():
        if order_queue.size() < 64:
            order_queue.append(order)
        return
    if not queued:
        order_queue.clear()
    _activate_order(order)

func _activate_order(order):
    active_order = order.duplicate()
    attack_target = null
    path = PackedVector2Array()
    path_index = 0
    velocity = Vector2.ZERO
    var order_type = str(active_order.get("type", ""))
    if order_type != "patrol":
        _clear_patrol_route()
    if order_type == "move" or order_type == "attack_move":
        var target_position = Vector2(active_order.get("position", global_position))
        _set_path_to(target_position)
        last_command_marker = target_position
    elif order_type == "attack":
        attack_target = active_order.get("target")
        repath_cooldown = 0.0
    elif order_type == "force_attack":
        repath_cooldown = 0.0
        var forced_position = Vector2(active_order.get("position", global_position))
        _set_path_to(forced_position)
    elif order_type == "repair":
        repair_bay_target = active_order.get("target")
        repath_cooldown = 0.0
    elif order_type == "patrol":
        patrol_points = []
        for point in active_order.get("patrol_points", [active_order.get("position", global_position)]):
            patrol_points.append(Vector2(point))
        if patrol_points.is_empty():
            patrol_points.append(Vector2(active_order.get("position", global_position)))
        patrol_index = 0
        patrol_direction = 1
        patrol_closed = bool(active_order.get("patrol_closed", false))
        active_order["position"] = Vector2(patrol_points[0])
        active_order["patrol_points"] = patrol_points.duplicate()
        _set_path_to(Vector2(patrol_points[0]))
    elif order_type == "harvest":
        harvest_target = active_order.get("target")
        harvest_cell = harvest_target.cell if is_instance_valid(harvest_target) else Vector2i(-1, -1)
        harvest_approach_position = Vector2.ZERO
        harvester_state = "seek"
        refinery_target = null
        refinery_dropoff = Vector2.ZERO
        path = PackedVector2Array()
    elif order_type == "hold":
        hold_position = global_position

func _complete_active_order():
    var completed_type = str(active_order.get("type", ""))
    if completed_type == "harvest":
        _reset_harvester_assignment()
    if completed_type == "patrol":
        _clear_patrol_route()
    active_order = {}
    attack_target = null
    path = PackedVector2Array()
    path_index = 0
    velocity = Vector2.ZERO
    while not order_queue.is_empty():
        var next_order = order_queue.pop_front()
        if str(next_order.get("type", "")) == "attack" and not is_instance_valid(next_order.get("target")):
            continue
        _activate_order(next_order)
        break

func get_order_queue_count():
    return order_queue.size() + (0 if active_order.is_empty() else 1)

func get_current_order_name():
    var names = {
        "move": "移动",
        "attack": "攻击",
        "attack_move": "攻击移动",
        "stop": "停止",
        "hold": "原地防守",
        "patrol": "巡逻",
        "harvest": "采集矿石",
        "force_attack": "强制攻击",
        "repair": "进入维修厂"
    }
    return str(names.get(str(active_order.get("type", "")), "待命"))

func get_order_waypoints():
    var result = []
    var orders = []
    if unit_id == "harvester" and (active_order.is_empty() or str(active_order.get("type", "")) == "harvest"):
        if harvester_state in ["return", "unloading"] and is_instance_valid(refinery_target):
            var return_position = refinery_dropoff if refinery_dropoff != Vector2.ZERO else refinery_target.global_position
            result.append({"type": "move", "position": return_position})
            return result
        if is_instance_valid(harvest_target):
            var harvest_position = harvest_approach_position if harvest_approach_position != Vector2.ZERO else harvest_target.global_position
            result.append({"type": "harvest", "position": harvest_position})
            return result
    if is_patrolling():
        for point in patrol_points:
            result.append({"type": "patrol", "position": Vector2(point)})
    elif not active_order.is_empty():
        orders.append(active_order)
    orders.append_array(order_queue)
    for order in orders:
        var order_type = str(order.get("type", ""))
        var point = Vector2.ZERO
        if order_type == "attack":
            var target = order.get("target")
            if not is_instance_valid(target):
                continue
            point = target.global_position
        elif order.has("position"):
            point = Vector2(order.get("position", global_position))
        else:
            continue
        result.append({"type": order_type, "position": point})
    return result

func _clear_patrol_route():
    patrol_points.clear()
    patrol_index = 0
    patrol_direction = 1
    patrol_closed = false

func _process_harvester(delta):
    var capacity = int(stats.get("capacity", 1000))
    if carrying >= capacity and harvester_state not in ["return", "unloading"]:
        harvester_state = "return"
        refinery_target = null
        refinery_dropoff = Vector2.ZERO
        path = PackedVector2Array()

    if harvester_state == "seek":
        if carrying > 0 and not _ensure_harvest_target():
            harvester_state = "return"
            return
        if not _ensure_harvest_target():
            velocity = Vector2.ZERO
            if str(active_order.get("type", "")) == "harvest":
                _complete_active_order()
            return
        harvest_cell = harvest_target.cell
        harvest_approach_position = match_ref.get_harvest_approach_position(harvest_target, self)
        destination = harvest_approach_position
        _set_path_to(destination)
        harvester_state = "to_ore"
        return

    if harvester_state == "to_ore":
        if not _harvest_target_available():
            _handle_depleted_harvest_target()
            return
        if carrying >= capacity:
            harvester_state = "return"
            return
        if harvest_approach_position == Vector2.ZERO:
            harvest_approach_position = match_ref.get_harvest_approach_position(harvest_target, self)
        var target_position = harvest_approach_position
        var near_resource = global_position.distance_to(harvest_target.global_position) <= 30.0
        var at_approach = global_position.distance_to(target_position) <= 14.0
        if near_resource and at_approach:
            velocity = Vector2.ZERO
            path = PackedVector2Array()
            harvest_timer = min(harvest_timer, 0.12)
            harvester_state = "harvest"
            return
        if path.is_empty() or path_index >= path.size() or destination.distance_to(target_position) > 2.0:
            _set_path_to(target_position)
        if path.is_empty():
            _recover_harvester_route(target_position)
        _follow_path(delta)
        return

    if harvester_state == "harvest":
        velocity = Vector2.ZERO
        if not _harvest_target_available():
            _handle_depleted_harvest_target()
            return
        if global_position.distance_to(harvest_target.global_position) > 52.0:
            harvest_approach_position = match_ref.get_harvest_approach_position(harvest_target, self)
            harvester_state = "to_ore"
            return
        harvest_timer -= delta
        if harvest_timer <= 0.0:
            harvest_timer = 0.42
            var requested = min(100, capacity - carrying)
            var taken = map_ref.harvest_ore_cell(harvest_cell, requested)
            carrying = min(capacity, carrying + taken)
            queue_redraw()
            if carrying >= capacity:
                harvester_state = "return"
                refinery_target = null
                refinery_dropoff = Vector2.ZERO
            elif taken <= 0:
                _handle_depleted_harvest_target()
        return

    if harvester_state == "return":
        if carrying <= 0:
            harvester_state = "seek"
            return
        if not is_instance_valid(refinery_target):
            refinery_target = match_ref.get_nearest_reachable_building(owner_id, "refinery", global_position)
            refinery_dropoff = Vector2.ZERO
        if not is_instance_valid(refinery_target):
            velocity = Vector2.ZERO
            return
        if refinery_dropoff == Vector2.ZERO:
            refinery_dropoff = match_ref.get_refinery_dropoff_position(refinery_target, global_position, self)
        if refinery_dropoff == Vector2.ZERO:
            velocity = Vector2.ZERO
            return
        if global_position.distance_to(refinery_dropoff) <= 27.0:
            velocity = Vector2.ZERO
            path = PackedVector2Array()
            if match_ref.begin_harvester_unload(self, refinery_target):
                harvester_state = "unloading"
            return
        if path.is_empty() or path_index >= path.size() or destination.distance_to(refinery_dropoff) > 3.0:
            _set_path_to(refinery_dropoff)
        if path.is_empty():
            _recover_harvester_route(refinery_dropoff)
        _follow_path(delta)

func _ensure_harvest_target():
    if _harvest_target_available():
        return true
    harvest_target = null
    harvest_cell = Vector2i(-1, -1)
    harvest_approach_position = Vector2.ZERO
    var ordered_target = active_order.get("target") if str(active_order.get("type", "")) == "harvest" else null
    if is_instance_valid(ordered_target) and ordered_target.has_method("is_resource_entity") and not ordered_target.is_depleted():
        harvest_target = ordered_target
    else:
        harvest_target = match_ref.get_nearest_ore_entity(global_position, self)
    if is_instance_valid(harvest_target):
        harvest_cell = harvest_target.cell
        harvest_approach_position = match_ref.get_harvest_approach_position(harvest_target, self)
        if str(active_order.get("type", "")) == "harvest":
            active_order["target"] = harvest_target
            active_order["position"] = harvest_target.global_position
        return true
    return false

func _harvest_target_available():
    return is_instance_valid(harvest_target) and harvest_target.has_method("is_resource_entity") and not harvest_target.is_depleted()

func _handle_depleted_harvest_target():
    harvest_target = null
    harvest_cell = Vector2i(-1, -1)
    harvest_approach_position = Vector2.ZERO
    path = PackedVector2Array()
    destination = Vector2.ZERO
    if carrying > 0:
        finish_harvest_after_unload = str(active_order.get("type", "")) == "harvest"
        harvester_state = "return"
        refinery_target = null
        refinery_dropoff = Vector2.ZERO
    elif str(active_order.get("type", "")) == "harvest":
        _complete_active_order()
    else:
        harvester_state = "seek"

func _recover_harvester_route(target_position):
    var target_cell = map_ref.world_to_cell(target_position)
    for radius in range(0, 4):
        for y in range(target_cell.y - radius, target_cell.y + radius + 1):
            for x in range(target_cell.x - radius, target_cell.x + radius + 1):
                var cell = Vector2i(x, y)
                if not map_ref.is_cell_walkable(cell, str(stats.get("category", "vehicle"))):
                    continue
                var candidate_path = map_ref.find_path_for_unit(global_position, map_ref.cell_to_world(cell), str(stats.get("category", "vehicle")))
                if not candidate_path.is_empty():
                    destination = map_ref.cell_to_world(cell)
                    path = candidate_path
                    path_index = 0
                    return
    # Route recovery failed. Release the contested target/drop-off and choose again.
    if harvester_state == "to_ore":
        harvest_target = null
        harvest_cell = Vector2i(-1, -1)
        harvest_approach_position = Vector2.ZERO
        harvester_state = "seek"
    elif harvester_state == "return":
        refinery_dropoff = Vector2.ZERO

func enter_refinery(refinery):
    if inside_refinery or not is_instance_valid(refinery):
        return false
    inside_refinery = true
    unload_refinery = refinery
    velocity = Vector2.ZERO
    visible = false
    collision_layer = 0
    collision_mask = 0
    if is_instance_valid(collision_shape_node):
        collision_shape_node.set_deferred("disabled", true)
    queue_redraw()
    return true

func exit_refinery(success, exit_position):
    inside_refinery = false
    unload_refinery = null
    global_position = exit_position
    visible = true
    collision_layer = saved_collision_layer
    collision_mask = saved_collision_mask
    if is_instance_valid(collision_shape_node):
        collision_shape_node.set_deferred("disabled", false)
    if success:
        carrying = 0
    refinery_target = null
    refinery_dropoff = Vector2.ZERO
    path = PackedVector2Array()
    path_index = 0
    destination = Vector2.ZERO
    queue_redraw()
    if finish_harvest_after_unload and str(active_order.get("type", "")) == "harvest":
        finish_harvest_after_unload = false
        _complete_active_order()
    else:
        finish_harvest_after_unload = false
        harvester_state = "seek"

func _reset_harvester_assignment():
    harvest_target = null
    harvest_cell = Vector2i(-1, -1)
    harvest_approach_position = Vector2.ZERO
    refinery_target = null
    refinery_dropoff = Vector2.ZERO
    finish_harvest_after_unload = false
    if unit_id == "harvester" and not inside_refinery:
        harvester_state = "seek"

func take_damage(amount, source = null):
    var remaining = float(amount)
    if shield > 0.0:
        var absorbed = min(shield, remaining)
        shield -= absorbed
        remaining -= absorbed
    var armor = float(stats.get("armor", 0.0))
    var actual_damage = max(1.0, remaining - armor) if remaining > 0.0 else 0.0
    if actual_damage > 0.0 and is_instance_valid(map_ref):
        actual_damage *= float(map_ref.get_cover_multiplier(global_position, str(stats.get("category", "infantry"))))
    if actual_damage > 0.0:
        hp -= actual_damage
        if owner_id == 0 and is_instance_valid(match_ref) and not match_ref.is_world_position_in_battle_view(global_position):
            VoiceManager.speak_adjutant("harvester_attacked" if unit_id == "harvester" else "unit_attacked")
        if is_instance_valid(match_ref):
            match_ref.spawn_combat_text(global_position, "-%d" % int(round(actual_damage)), "damage")
            if is_instance_valid(source) and source != self and source.has_method("take_damage"):
                match_ref.notify_allies_under_attack(self, source)
                var current_type = str(active_order.get("type", ""))
                if retaliate_enabled and is_combat_unit() and (active_order.is_empty() or current_type in ["stop", "hold"]):
                    command_attack(source, false)
    queue_redraw()
    _update_damage_smoke()
    if hp <= 0:
        _begin_death(source)
    return actual_damage

func heal(amount):
    var previous = hp
    hp = min(max_hp, hp + float(amount))
    var healed = hp - previous
    if healed > 0.0 and is_instance_valid(match_ref):
        match_ref.spawn_combat_text(global_position, "+%d" % int(round(healed)), "heal")
    queue_redraw()
    return healed

func gain_experience(value):
    experience += float(value)
    var thresholds = stats.get("experience_required", [180, 520])
    var next_rank = 0
    if thresholds.size() > 1 and experience >= float(thresholds[1]):
        next_rank = 2
    elif not thresholds.is_empty() and experience >= float(thresholds[0]):
        next_rank = 1
    if next_rank > veterancy:
        veterancy = next_rank
        heal(max_hp * 0.28)
        fire_cooldown = 0.0
        queue_redraw()
        if owner_id == 0:
            EventBus.notification_requested.emit(str(stats.get("name", unit_id)) + (" 晋升精英" if veterancy == 2 else " 晋升老兵"), "info")

func get_next_experience_requirement():
    var thresholds = stats.get("experience_required", [180, 520])
    if veterancy <= 0 and not thresholds.is_empty():
        return float(thresholds[0])
    if veterancy == 1 and thresholds.size() > 1:
        return float(thresholds[1])
    return float(thresholds[-1]) if not thresholds.is_empty() else experience

func set_selected(value):
    selected = bool(value) and not dying
    queue_redraw()

func set_hover_state(value):
    if hover_state == value:
        return
    hover_state = value
    queue_redraw()

func get_selection_rect():
    var radius = (float(stats.get("radius", 12.0)) + 6.0) * float(visual_profile.selection_scale if visual_profile != null else 1.0)
    return Rect2(global_position - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0))

func get_sight_radius_cells():
    return int(stats.get("sight", 6))

func is_combat_unit():
    return float(stats.get("damage", 0)) > 0

func is_movable_unit():
    return true

func _should_show_health_bar():
    var mode = str(SaveManager.settings.get("health_bar_mode", "selected_damaged"))
    if mode == "off":
        return false
    if mode == "always":
        return true
    if mode == "selected":
        return selected
    return selected or hp < max_hp

func _visual_top_y():
    if is_instance_valid(visual_sprite):
        var frame_size = SpriteSheetFactory.get_unit_frame_size(unit_id)
        return visual_sprite.position.y - frame_size.y * visual_sprite.scale.y * 0.5 + 5.0
    return -float(stats.get("radius", 12.0)) - 12.0

func _draw_hover_marker(radius):
    var marker_color = Color("#69DDF4")
    if hover_state == "selected":
        marker_color = Color("#72E58C")
    elif hover_state == "attack" or hover_state == "enemy":
        marker_color = Color("#F06460")
    var outer = radius + 10.0
    for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
        var start = Vector2.RIGHT.rotated(angle) * outer
        var tangent = Vector2.DOWN.rotated(angle)
        draw_line(start - tangent * 5.0, start + tangent * 5.0, marker_color, 2.0)
    if hover_state == "attack":
        draw_line(Vector2(-5, -5), Vector2(5, 5), marker_color, 2.0)
        draw_line(Vector2(5, -5), Vector2(-5, 5), marker_color, 2.0)

func _draw():
    var radius = float(stats.get("radius", 12.0))
    var visual_top = _visual_top_y()
    if selected:
        draw_set_transform(Vector2(0, 7), 0.0, Vector2(1.0, 0.42))
        draw_arc(Vector2.ZERO, radius + 9.0, 0, TAU, 40, Color("#75E6FF"), 2.0)
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    if hover_state != "":
        _draw_hover_marker(radius)
    if dying:
        var stain_color = Color(0.34, 0.035, 0.025, max(0.12, 0.46 - death_elapsed * 0.035)) if str(stats.get("category", "infantry")) == "infantry" else Color(0.06, 0.055, 0.05, 0.48)
        draw_set_transform(Vector2(0, 10), 0.0, Vector2(1.0, 0.38))
        draw_circle(Vector2.ZERO, radius * (1.45 if unit_id in ["tank", "harvester"] else 1.05), stain_color)
        draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    if veterancy > 0 and not dying:
        for rank in range(veterancy):
            var y_offset = visual_top - 27.0 - rank * 5.0
            draw_polyline(PackedVector2Array([Vector2(-5, y_offset), Vector2(0, y_offset + 3), Vector2(5, y_offset)]), Color("#F1D05D"), 2.0)
    if not dying and _should_show_health_bar():
        var bar_width = max(42.0, radius * 2.8)
        var bar_x = -bar_width * 0.5
        var bar_y = visual_top
        draw_rect(Rect2(Vector2(bar_x, bar_y), Vector2(bar_width, 6)), Color("#311D1D"))
        draw_rect(Rect2(Vector2(bar_x, bar_y), Vector2(bar_width * clamp(hp / max_hp, 0.0, 1.0), 6)), Color("#61C46E"))
        if bool(SaveManager.settings.get("show_health_values", true)):
            var health_text = "%d/%d" % [int(ceil(hp)), int(max_hp)]
            var measured_width = ThemeDB.fallback_font.get_string_size(health_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
            var text_width = max(bar_width, measured_width + 10.0)
            var text_x = -text_width * 0.5
            draw_string_outline(ThemeDB.fallback_font, Vector2(text_x, bar_y - 2), health_text, HORIZONTAL_ALIGNMENT_CENTER, text_width, 10, 2, Color.BLACK)
            draw_string(ThemeDB.fallback_font, Vector2(text_x, bar_y - 2), health_text, HORIZONTAL_ALIGNMENT_CENTER, text_width, 10, Color.WHITE)
    if not dying and selected and bool(SaveManager.settings.get("show_experience", true)):
        var exp_text = "经验 %d/%d" % [int(experience), int(get_next_experience_requirement())]
        var measured_exp_width = ThemeDB.fallback_font.get_string_size(exp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
        var exp_width = max(68.0, measured_exp_width + 10.0)
        draw_string_outline(ThemeDB.fallback_font, Vector2(-exp_width * 0.5, visual_top - 13.0), exp_text, HORIZONTAL_ALIGNMENT_CENTER, exp_width, 10, 2, Color.BLACK)
        draw_string(ThemeDB.fallback_font, Vector2(-exp_width * 0.5, visual_top - 13.0), exp_text, HORIZONTAL_ALIGNMENT_CENTER, exp_width, 10, Color("#F0D267"))

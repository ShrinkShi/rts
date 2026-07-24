extends Node2D

const SpriteSheetFactory = preload("res://scripts/game/sprite_sheet_factory.gd")
const CombatEffect = preload("res://scripts/game/combat_effect.gd")
const VisualProfileStore = preload("res://scripts/core/visual_profile_store.gd")

signal died(entity)
signal production_ready(unit_id, building)
signal fired(from_point, to_point, owner_id)

const LAYER_INFANTRY = 1
const LAYER_VEHICLE = 2
const LAYER_BUILDING = 4

var match_ref
var map_ref
var building_id = "command"
var owner_id = 0
var stats = {}
var hp = 100.0
var max_hp = 100.0
var shield = 0.0
var max_shield = 0.0
var selected = false
var hover_state = ""
var team_color = Color.WHITE
var origin_cell = Vector2i.ZERO
var footprint = Vector2i.ONE
var powered = true
var production_queue = []
var target
var forced_attack_active = false
var forced_attack_target
var forced_attack_position = Vector2.ZERO
var fire_cooldown = 0.0
var scan_cooldown = 0.0
var rally_point = Vector2.ZERO
var static_body
var primary_producer = false
var manual_stopped = false
var visual_sprite
var turret_sprite
var turret_visual_direction = 0
var damage_stage = 0
var attack_animation_time = 0.0
var damage_smoke
var construction_progress = 1.0
var construction_duration = 1.35
var selling = false
var sell_refund = 0
var target_visual_scale = Vector2.ONE
var target_visual_position = Vector2.ZERO
var repairing_vehicle
var repair_animation_phase = 0.0
var repair_active = false
var turret_facing = Vector2.RIGHT
var sale_completed = false
var visual_profile

func setup(next_match, next_map, next_building_id, next_owner, cell, animate_construction = false):
    match_ref = next_match
    map_ref = next_map
    building_id = next_building_id
    owner_id = next_owner
    stats = GameConfig.buildings.get(building_id, {}).duplicate(true)
    visual_profile = VisualProfileStore.get_profile(building_id)
    max_hp = float(stats.get("hp", 500))
    hp = max_hp
    max_shield = float(stats.get("shield", 0.0))
    shield = max_shield
    var footprint_data = stats.get("footprint", [1, 1])
    footprint = Vector2i(int(footprint_data[0]), int(footprint_data[1]))
    origin_cell = cell
    global_position = map_ref.footprint_center(cell, footprint)
    team_color = match_ref.get_player_color(owner_id)
    rally_point = global_position + Vector2((footprint.x + 2) * map_ref.tile_px, 0)
    z_index = 0
    map_ref.occupy(origin_cell, footprint, self)
    _build_collision_shape()
    construction_progress = 0.0 if bool(animate_construction) else 1.0
    _build_visual()
    _apply_construction_visual()
    queue_redraw()


func _build_visual():
    visual_sprite = Sprite2D.new()
    visual_sprite.name = "BuildingVisual"
    visual_sprite.texture = SpriteSheetFactory.get_building_frame(building_id, 0)
    visual_sprite.centered = true
    visual_sprite.show_behind_parent = true
    visual_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    var frame_size = SpriteSheetFactory.get_building_frame_size(building_id)
    var target_width = max(64.0, footprint.x * map_ref.tile_px * 1.42)
    var scale_value = target_width / frame_size.x
    if building_id in ["turret", "bunker"]:
        scale_value *= 1.34
    target_visual_scale = Vector2.ONE * scale_value * visual_profile.visual_scale_multiplier
    target_visual_position = Vector2(0, -max(18.0, footprint.y * map_ref.tile_px * 0.42)) + visual_profile.visual_offset
    visual_sprite.scale = target_visual_scale
    visual_sprite.position = target_visual_position
    visual_sprite.material = SpriteSheetFactory.create_team_material(team_color)
    add_child(visual_sprite)

    if building_id in ["turret", "bunker"]:
        turret_sprite = AnimatedSprite2D.new()
        turret_sprite.name = "RotatingWeaponVisual"
        turret_sprite.sprite_frames = SpriteSheetFactory.get_defense_head_frames(building_id)
        turret_sprite.centered = true
        turret_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
        var head_size = SpriteSheetFactory.get_defense_head_frame_size(building_id)
        var head_scale = target_width / head_size.x * (1.20 if building_id == "bunker" else 1.08)
        turret_sprite.scale = Vector2.ONE * head_scale * visual_profile.turret_scale_multiplier
        turret_sprite.position = target_visual_position + Vector2(0, -8 if building_id == "bunker" else -12) + visual_profile.turret_offset
        turret_sprite.z_index = 2
        turret_sprite.material = SpriteSheetFactory.create_team_material(team_color)
        add_child(turret_sprite)
        turret_sprite.play("stand_0")

func _apply_construction_visual():
    if not is_instance_valid(visual_sprite):
        return
    var p = clamp(construction_progress, 0.0, 1.0)
    var eased = p * p * (3.0 - 2.0 * p)
    if SpriteSheetFactory.has_ai_construction_frames(building_id):
        if p < 1.0 or selling:
            visual_sprite.texture = SpriteSheetFactory.get_building_construction_frame(building_id, p)
        else:
            visual_sprite.texture = SpriteSheetFactory.get_building_frame(building_id, damage_stage)
        visual_sprite.scale = target_visual_scale
        visual_sprite.position = target_visual_position
        visual_sprite.modulate.a = clamp(0.42 + eased * 0.58, 0.0, 1.0)
    else:
        visual_sprite.scale = Vector2(target_visual_scale.x, max(0.04, target_visual_scale.y * eased))
        visual_sprite.position = target_visual_position + Vector2(0, (1.0 - eased) * 34.0)
        visual_sprite.modulate.a = clamp(0.18 + eased * 0.82, 0.0, 1.0)
    if is_instance_valid(turret_sprite):
        turret_sprite.visible = p >= 0.98 and not selling
        turret_sprite.modulate.a = visual_sprite.modulate.a

func begin_sell(refund):
    if selling or is_under_construction():
        return false
    selling = true
    sale_completed = false
    sell_refund = max(0, int(refund))
    target = null
    forced_attack_active = false
    forced_attack_target = null
    manual_stopped = true
    production_queue.clear()
    repair_active = false
    queue_redraw()
    return true

func set_repair_active(value):
    repair_active = bool(value)
    queue_redraw()

func is_under_construction():
    return construction_progress < 1.0 and not selling

func is_repair_facility():
    return building_id == "repair_bay"

func get_service_entry_position(from_position = Vector2.ZERO):
    var direction = global_position.direction_to(from_position)
    if direction.length_squared() < 0.01:
        direction = Vector2.RIGHT
    return global_position + direction.normalized() * max(footprint.x, footprint.y) * map_ref.tile_px * 0.82

func accept_vehicle_for_repair(unit):
    if not is_repair_facility() or selling or is_under_construction() or is_instance_valid(repairing_vehicle):
        return false
    if not is_instance_valid(unit) or unit.owner_id != owner_id or str(unit.stats.get("category", "")) != "vehicle":
        return false
    if unit.hp >= unit.max_hp:
        return false
    if not unit.enter_repair_bay(self):
        return false
    repairing_vehicle = unit
    repair_active = true
    queue_redraw()
    return true

func _finish_vehicle_repair():
    if not is_instance_valid(repairing_vehicle):
        repairing_vehicle = null
        repair_active = false
        return
    var vehicle = repairing_vehicle
    repairing_vehicle = null
    repair_active = false
    var exit_position = match_ref.find_clear_unit_position(get_service_entry_position(rally_point), float(vehicle.stats.get("collision_radius", 16.0)), vehicle)
    if exit_position == Vector2.ZERO:
        exit_position = global_position + Vector2((footprint.x + 1) * map_ref.tile_px, 0)
    vehicle.exit_repair_bay(exit_position)
    queue_redraw()

func _process_vehicle_repair(delta):
    if not is_repair_facility() or not is_instance_valid(repairing_vehicle):
        if is_repair_facility():
            repair_active = false
        return
    repair_active = true
    repair_animation_phase += delta * 4.5
    var result = match_ref.repair_entity_step(repairing_vehicle, delta, self)
    if bool(result.get("no_funds", false)):
        if owner_id == 0:
            EventBus.notification_requested.emit("资金不足，车辆已离开维修厂", "warning")
        _finish_vehicle_repair()
    elif bool(result.get("complete", false)):
        _finish_vehicle_repair()
    queue_redraw()

func eject_repairing_vehicle():
    if is_instance_valid(repairing_vehicle):
        _finish_vehicle_repair()

func _update_damage_visual():
    var ratio = hp / max(1.0, max_hp)
    var next_stage = 2 if ratio <= 0.333 else (1 if ratio <= 0.666 else 0)
    if next_stage != damage_stage:
        damage_stage = next_stage
        if is_instance_valid(visual_sprite):
            visual_sprite.texture = SpriteSheetFactory.get_building_frame(building_id, damage_stage)
        if is_instance_valid(turret_sprite):
            turret_sprite.modulate = Color.WHITE if damage_stage == 0 else (Color(0.86, 0.82, 0.78, 1.0) if damage_stage == 1 else Color(0.68, 0.62, 0.58, 1.0))
    var should_smoke = damage_stage >= 2 and hp > 0.0
    if should_smoke and not is_instance_valid(damage_smoke):
        damage_smoke = CombatEffect.new()
        damage_smoke.z_index = 4
        add_child(damage_smoke)
        damage_smoke.position = Vector2(footprint.x * map_ref.tile_px * 0.12, -footprint.y * map_ref.tile_px * 0.9)
        damage_smoke.setup("smoke", Color("#3A4043"), 1.15, true, get_instance_id())
    elif not should_smoke and is_instance_valid(damage_smoke):
        damage_smoke.queue_free()
        damage_smoke = null

func _spawn_collapse_effect():
    if not is_instance_valid(match_ref) or not is_instance_valid(match_ref.effect_layer):
        return
    var effect = CombatEffect.new()
    match_ref.effect_layer.add_child(effect)
    effect.global_position = global_position - Vector2(0, footprint.y * map_ref.tile_px * 0.35)
    effect.setup("building_collapse", team_color, 1.4 + footprint.x * 0.12, false, get_instance_id())

func _build_collision_shape():
    static_body = StaticBody2D.new()
    static_body.collision_layer = LAYER_BUILDING
    static_body.collision_mask = LAYER_INFANTRY | LAYER_VEHICLE
    var shape_node = CollisionShape2D.new()
    var rectangle = RectangleShape2D.new()
    rectangle.size = Vector2(footprint.x * map_ref.tile_px - 8.0, footprint.y * map_ref.tile_px - 8.0)
    shape_node.shape = rectangle
    static_body.add_child(shape_node)
    add_child(static_body)

func _process(delta):
    fire_cooldown = max(0.0, fire_cooldown - delta)
    repair_animation_phase += delta * (5.0 if repair_active else 1.0)
    if selling:
        construction_progress = max(0.0, construction_progress - delta / 1.0)
        _apply_construction_visual()
        queue_redraw()
        if construction_progress <= 0.0 and not sale_completed:
            sale_completed = true
            set_process(false)
            match_ref.complete_building_sale(self, sell_refund)
        return
    if construction_progress < 1.0:
        construction_progress = min(1.0, construction_progress + delta / max(0.2, construction_duration))
        _apply_construction_visual()
        queue_redraw()
        return
    scan_cooldown = max(0.0, scan_cooldown - delta)
    attack_animation_time = max(0.0, attack_animation_time - delta)
    _process_production(delta)
    _process_vehicle_repair(delta)
    if is_defense_building() and powered and not manual_stopped:
        _process_turret()
    _update_turret_visual()
    if attack_animation_time > 0.0:
        queue_redraw()

func _direction_index(direction):
    if Vector2(direction).length_squared() < 0.001:
        return turret_visual_direction
    var angle = fposmod(Vector2(direction).angle(), TAU)
    return int(round(angle / (TAU / 8.0))) % 8

func _update_turret_visual():
    if not is_defense_building() or not is_instance_valid(turret_sprite):
        return
    var next_direction = _direction_index(turret_facing)
    var changed = next_direction != turret_visual_direction
    turret_visual_direction = next_direction
    var state_name = "attack" if attack_animation_time > 0.0 else "stand"
    var animation_name = "%s_%d" % [state_name, turret_visual_direction]
    if turret_sprite.animation != animation_name or changed:
        turret_sprite.play(animation_name)

func _process_production(delta):
    if selling or is_under_construction() or production_queue.is_empty() or not powered:
        return
    var job = production_queue[0]
    if bool(job.get("paused", false)):
        return
    job["progress"] = float(job.get("progress", 0.0)) + delta
    production_queue[0] = job
    queue_redraw()
    if float(job.get("progress", 0.0)) >= float(job.get("duration", 1.0)):
        production_queue.pop_front()
        queue_redraw()
        production_ready.emit(str(job.get("id", "")), self)

func _process_turret():
    if selling or is_under_construction():
        return
    var attack_point = Vector2.ZERO
    var has_attack_point = false
    var damage_target = null

    if forced_attack_active:
        if forced_attack_target != null and not is_instance_valid(forced_attack_target):
            forced_attack_active = false
            forced_attack_target = null
        if forced_attack_active:
            if is_instance_valid(forced_attack_target):
                forced_attack_position = forced_attack_target.global_position
                damage_target = forced_attack_target
            attack_point = forced_attack_position
            has_attack_point = true
            if global_position.distance_to(attack_point) > float(stats.get("range", 220.0)):
                return
            turret_facing = global_position.direction_to(attack_point)
    else:
        if is_instance_valid(target):
            if target.owner_id == owner_id or target.hp <= 0 or global_position.distance_to(target.global_position) > float(stats.get("range", 220.0)):
                target = null
        if not is_instance_valid(target) and scan_cooldown <= 0.0:
            scan_cooldown = 0.28
            target = match_ref.find_nearest_enemy(owner_id, global_position, float(stats.get("range", 220.0)))
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
    fired.emit(global_position + turret_facing * 18.0 + Vector2(0, -22), attack_point, owner_id)
    match_ref.spawn_muzzle_flash(global_position + turret_facing * 25.0 + Vector2(0, -22), Color("#FFD46B"))
    var shot_damage = float(stats.get("damage", 20))
    var shot_aoe = float(stats.get("aoe_radius", 0.0))
    if is_instance_valid(damage_target):
        match_ref.apply_weapon_damage(self, damage_target, shot_damage, shot_aoe)
    elif forced_attack_active:
        match_ref.apply_ground_damage(self, attack_point, shot_damage, shot_aoe, null)

func enqueue_unit(unit_id_value, paid_cost = 0):
    var unit_data = GameConfig.units.get(unit_id_value, {})
    production_queue.append({
        "id": unit_id_value,
        "progress": 0.0,
        "duration": float(unit_data.get("build_time", 5.0)),
        "paused": false,
        "cost": int(paid_cost)
    })
    queue_redraw()

func resume_front_job(unit_id_value):
    if production_queue.is_empty():
        return false
    var job = production_queue[0]
    if str(job.get("id", "")) != unit_id_value or not bool(job.get("paused", false)):
        return false
    job["paused"] = false
    production_queue[0] = job
    queue_redraw()
    return true

func pause_or_cancel_unit(unit_id_value):
    if production_queue.is_empty():
        return {"action": "none", "refund": 0}
    var front = production_queue[0]
    if str(front.get("id", "")) == unit_id_value and not bool(front.get("paused", false)):
        front["paused"] = true
        production_queue[0] = front
        queue_redraw()
        return {"action": "paused", "refund": 0}
    var cancel_index = -1
    for index in range(production_queue.size() - 1, -1, -1):
        if str(production_queue[index].get("id", "")) == unit_id_value:
            cancel_index = index
            break
    if cancel_index < 0:
        return {"action": "none", "refund": 0}
    var removed = production_queue[cancel_index]
    production_queue.remove_at(cancel_index)
    queue_redraw()
    var progress_ratio = clamp(float(removed.get("progress", 0.0)) / max(0.01, float(removed.get("duration", 1.0))), 0.0, 1.0)
    var refund_ratio = 1.0 - progress_ratio * 0.25
    var refund = int(round(float(removed.get("cost", 0)) * refund_ratio))
    return {
        "action": "canceled",
        "refund": refund,
        "remaining": count_queued(unit_id_value)
    }

func count_queued(unit_id_value):
    var count = 0
    for job in production_queue:
        if str(job.get("id", "")) == unit_id_value:
            count += 1
    return count

func has_queued(unit_id_value):
    return count_queued(unit_id_value) > 0

func is_front_job_paused(unit_id_value = ""):
    if production_queue.is_empty():
        return false
    var job = production_queue[0]
    if unit_id_value != "" and str(job.get("id", "")) != unit_id_value:
        return false
    return bool(job.get("paused", false))

func queue_progress():
    if production_queue.is_empty():
        return 0.0
    var job = production_queue[0]
    return clamp(float(job.get("progress", 0.0)) / max(0.01, float(job.get("duration", 1.0))), 0.0, 1.0)

func queue_label():
    if production_queue.is_empty():
        return ""
    var job = production_queue[0]
    var label = str(GameConfig.units.get(str(job.get("id", "")), {}).get("name", job.get("id", "")))
    if bool(job.get("paused", false)):
        label += "（已暂停）"
    return label


func is_production_building():
    return building_id == "barracks" or building_id == "war_factory"

func is_defense_building():
    return float(stats.get("damage", 0.0)) > 0.0 and float(stats.get("range", 0.0)) > 0.0

func command_attack(next_target):
    if not is_defense_building() or not is_instance_valid(next_target):
        return false
    if next_target.owner_id == owner_id:
        return false
    if next_target.has_method("is_resource_entity") and next_target.is_resource_entity():
        return false
    forced_attack_active = false
    forced_attack_target = null
    target = next_target
    manual_stopped = false
    scan_cooldown = 0.0
    queue_redraw()
    return true

func command_force_attack(target_or_position):
    if not is_defense_building():
        return false
    target = null
    manual_stopped = false
    forced_attack_active = true
    forced_attack_target = target_or_position if target_or_position is Node else null
    forced_attack_position = forced_attack_target.global_position if is_instance_valid(forced_attack_target) else Vector2(target_or_position)
    scan_cooldown = 0.0
    queue_redraw()
    return true

func command_stop():
    if not is_defense_building():
        return false
    target = null
    forced_attack_active = false
    forced_attack_target = null
    manual_stopped = true
    queue_redraw()
    return true

func get_current_order_name():
    if is_repair_facility():
        return "维修中" if is_instance_valid(repairing_vehicle) else "待命"
    if not is_defense_building():
        return "待命"
    if manual_stopped:
        return "停止"
    if forced_attack_active:
        return "强制攻击"
    if is_instance_valid(target):
        return "攻击"
    return "自动警戒"

func set_rally_point(world_position):
    if not is_production_building():
        return false
    var cell = map_ref.nearest_walkable_cell(map_ref.world_to_cell(world_position))
    if cell.x < 0:
        return false
    rally_point = map_ref.cell_to_world(cell)
    queue_redraw()
    return true

func set_primary(value):
    primary_producer = bool(value)
    queue_redraw()

func get_order_waypoints():
    if is_production_building():
        return [{"type": "rally", "position": rally_point}]
    if is_defense_building() and forced_attack_active:
        var point = forced_attack_target.global_position if is_instance_valid(forced_attack_target) else forced_attack_position
        return [{"type": "force_attack", "position": point}]
    if is_defense_building() and is_instance_valid(target):
        return [{"type": "attack", "position": target.global_position}]
    return []

func take_damage(amount, source = null):
    var remaining = float(amount)
    if shield > 0.0:
        var absorbed = min(shield, remaining)
        shield -= absorbed
        remaining -= absorbed
    var armor = float(stats.get("armor", 0.0))
    var actual_damage = max(1.0, remaining - armor) if remaining > 0.0 else 0.0
    if actual_damage > 0.0:
        hp -= actual_damage
        if owner_id == 0 and is_instance_valid(match_ref) and not match_ref.is_world_position_in_battle_view(global_position):
            VoiceManager.speak_adjutant("building_attacked")
        if is_instance_valid(match_ref):
            match_ref.spawn_combat_text(global_position, "-%d" % int(round(actual_damage)), "damage")
            if is_instance_valid(source):
                match_ref.notify_allies_under_attack(self, source)
    _update_damage_visual()
    queue_redraw()
    if hp <= 0:
        hp = 0
        eject_repairing_vehicle()
        if is_instance_valid(source) and source.has_method("gain_experience"):
            source.gain_experience(max_hp)
        if is_instance_valid(damage_smoke):
            damage_smoke.queue_free()
            damage_smoke = null
        _spawn_collapse_effect()
        map_ref.vacate(self)
        died.emit(self)
        queue_free()

func heal(amount):
    var previous = hp
    hp = min(max_hp, hp + float(amount))
    var healed = hp - previous
    if healed > 0.0 and is_instance_valid(match_ref):
        match_ref.spawn_combat_text(global_position, "+%d" % int(round(healed)), "heal")
    queue_redraw()
    return healed

func set_selected(value):
    selected = value
    queue_redraw()

func set_hover_state(value):
    if hover_state == value:
        return
    hover_state = value
    queue_redraw()

func get_selection_rect():
    var size_value = Vector2(footprint.x * map_ref.tile_px, footprint.y * map_ref.tile_px)
    return Rect2(global_position - size_value * 0.5, size_value)

func get_sight_radius_cells():
    return int(stats.get("sight", 6))

func get_power_output():
    return int(stats.get("power_output", 0))

func get_power_use():
    return int(stats.get("power_use", 0))

func _visual_top_y():
    if is_instance_valid(visual_sprite):
        var frame_size = SpriteSheetFactory.get_building_frame_size(building_id)
        return visual_sprite.position.y - frame_size.y * visual_sprite.scale.y * 0.5 + 5.0
    return -footprint.y * map_ref.tile_px * 0.5 - 10.0

func _should_show_health_bar():
    var mode = str(SaveManager.settings.get("health_bar_mode", "selected_damaged"))
    if mode == "off":
        return false
    if mode == "always":
        return true
    if mode == "selected":
        return selected
    return selected or hp < max_hp

func _draw_hover_marker(rect):
    var color = Color("#69DDF4")
    if hover_state == "selected":
        color = Color("#72E58C")
    elif hover_state == "primary":
        color = Color("#F0D05E")
    elif hover_state == "attack" or hover_state == "enemy":
        color = Color("#F06460")
    var expanded = rect.grow(7.0)
    var length = min(12.0, min(expanded.size.x, expanded.size.y) * 0.25)
    for corner in [expanded.position, Vector2(expanded.end.x, expanded.position.y), expanded.end, Vector2(expanded.position.x, expanded.end.y)]:
        var sx = 1.0 if corner.x == expanded.position.x else -1.0
        var sy = 1.0 if corner.y == expanded.position.y else -1.0
        draw_line(corner, corner + Vector2(length * sx, 0), color, 2.0)
        draw_line(corner, corner + Vector2(0, length * sy), color, 2.0)

func _draw_attack_range():
    if not selected or not is_defense_building():
        return
    var radius = float(stats.get("range", 0.0))
    if radius <= 0.0:
        return
    var segments = 72
    for index in range(0, segments, 2):
        var start_angle = TAU * float(index) / float(segments)
        var end_angle = TAU * float(index + 1) / float(segments)
        draw_arc(Vector2.ZERO, radius, start_angle, end_angle, 4, Color(1.0, 1.0, 1.0, 0.72), 1.5)

func _draw():
    _draw_attack_range()
    var w = footprint.x * map_ref.tile_px - 5
    var h = footprint.y * map_ref.tile_px - 5
    var rect = Rect2(Vector2(-w * 0.5, -h * 0.5), Vector2(w, h))
    if not powered and get_power_use() > 0:
        draw_rect(rect.grow(-5), Color(0.08, 0.09, 0.09, 0.48))
    if repair_active:
        var spark_center = Vector2(cos(repair_animation_phase) * 16.0, -h * 0.42 + sin(repair_animation_phase * 1.7) * 7.0)
        draw_line(spark_center + Vector2(-7, 7), spark_center + Vector2(7, -7), Color("#E7D56F"), 3.0)
        draw_arc(spark_center + Vector2(7, -7), 6.0, -0.2, 3.6, 16, Color("#D8E6EB"), 2.0)
        draw_circle(spark_center + Vector2(-7, 7), 3.0, Color("#D8E6EB"))
    if construction_progress < 1.0 or selling:
        var progress_width = w * clamp(construction_progress, 0.0, 1.0)
        draw_rect(Rect2(Vector2(-w * 0.5, h * 0.42), Vector2(w, 5)), Color("#1B2226"))
        draw_rect(Rect2(Vector2(-w * 0.5, h * 0.42), Vector2(progress_width, 5)), Color("#E2C75E"))
    if hover_state != "":
        _draw_hover_marker(rect)
    if selected:
        draw_rect(rect.grow(5), Color("#75E6FF"), false, 2.0)
    var visual_top = _visual_top_y()
    if primary_producer:
        draw_circle(Vector2(0, visual_top - 17.0), 7.0, Color("#F0D05E"))
        draw_string(ThemeDB.fallback_font, Vector2(-12, visual_top - 13.0), "主", HORIZONTAL_ALIGNMENT_CENTER, 24, 10, Color("#152027"))
    if _should_show_health_bar():
        var bar_y = visual_top
        draw_rect(Rect2(Vector2(-w * 0.5, bar_y), Vector2(w, 6)), Color("#311D1D"))
        draw_rect(Rect2(Vector2(-w * 0.5, bar_y), Vector2(w * clamp(hp / max_hp, 0.0, 1.0), 6)), Color("#61C46E"))
        if bool(SaveManager.settings.get("show_health_values", true)):
            var health_text = "%d/%d" % [int(ceil(hp)), int(max_hp)]
            draw_string_outline(ThemeDB.fallback_font, Vector2(-w * 0.5, bar_y - 2), health_text, HORIZONTAL_ALIGNMENT_CENTER, w, 11, 2, Color.BLACK)
            draw_string(ThemeDB.fallback_font, Vector2(-w * 0.5, bar_y - 2), health_text, HORIZONTAL_ALIGNMENT_CENTER, w, 11, Color.WHITE)
    if not production_queue.is_empty():
        var queue_color = Color("#E3C95F") if is_front_job_paused() else Color("#62AFCB")
        draw_rect(Rect2(Vector2(-w * 0.5, h * 0.5 + 4), Vector2(w, 4)), Color("#14242B"))
        draw_rect(Rect2(Vector2(-w * 0.5, h * 0.5 + 4), Vector2(w * queue_progress(), 4)), queue_color)

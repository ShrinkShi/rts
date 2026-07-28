extends Node

const UNIT_SCRIPT_PATHS := ["res://scripts/game/unit.gd", "res://scripts/game/ra2_unit.gd"]
const BUILDING_SCRIPT_PATHS := ["res://scripts/game/building.gd", "res://scripts/game/ra2_building.gd"]
const TREE_SCRIPT_PATH := "res://scripts/game/tree_entity.gd"
const TREE_VEHICLE_RADIUS_FACTOR := 0.14
const SETTLE_INTERVAL := 0.10
const UNLOAD_INTERVAL := 0.05
const PENDING_BUILDING_INTERVAL := 0.20
const UNLOAD_VISUAL_NAME := "RuntimeUnloadVisual"
const RA2VisualPlayer = preload("res://scripts/ra2/ra2_visual_player.gd")
const RA2LayeredVehicleVisual = preload("res://scripts/ra2/ra2_layered_vehicle_visual.gd")

var _units: Array = []
var _tanks: Array = []
var _harvesters: Array = []
var _pending_buildings: Array = []
var _unload_visuals: Dictionary = {}
var _stable_vehicle_facings: Dictionary = {}
var _settle_elapsed := 0.0
var _unload_elapsed := 0.0
var _pending_building_elapsed := 0.0
var _cleanup_timer := 1.0


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_PAUSABLE
    process_priority = 100
    _register_existing(get_tree().root)
    get_tree().node_added.connect(_on_node_added)


func _register_existing(node: Node) -> void:
    _register_node(node)
    for child in node.get_children():
        _register_existing(child)


func _on_node_added(node: Node) -> void:
    call_deferred("_register_node", node)


func _register_node(node: Node) -> void:
    if not is_instance_valid(node):
        return
    var script := node.get_script() as Script
    if script == null:
        return
    var script_path := script.resource_path
    if script_path in UNIT_SCRIPT_PATHS:
        if not node in _units:
            _units.append(node)
        call_deferred("_initialize_unit_rules", node)
    elif script_path in BUILDING_SCRIPT_PATHS:
        if not node in _pending_buildings:
            _pending_buildings.append(node)
        call_deferred("_initialize_building_rules", node)
    elif script_path == TREE_SCRIPT_PATH:
        call_deferred("_tune_tree_collision", node)


func _initialize_unit_rules(unit) -> void:
    if not is_instance_valid(unit) or unit.stats.is_empty():
        return
    _enforce_infantry_tree_passthrough(unit)
    var unit_id := str(unit.unit_id)
    if unit_id == "tank" and not unit in _tanks:
        _tanks.append(unit)
        _tune_tank_lighting_once(unit)
    elif unit_id == "harvester" and not unit in _harvesters:
        _harvesters.append(unit)


func _initialize_building_rules(building) -> void:
    if not is_instance_valid(building):
        return
    _raise_building_health_bar_once(building)
    _stabilize_war_factory_production_visual_once(building)


func _process(delta: float) -> void:
    for tank in _tanks:
        if not is_instance_valid(tank):
            continue
        _stabilize_stationary_tank_facing(tank)
        _tune_tank_lighting_once(tank)

    _settle_elapsed -= delta
    if _settle_elapsed <= 0.0:
        _settle_elapsed = SETTLE_INTERVAL
        for unit in _units:
            if is_instance_valid(unit):
                _settle_occupied_move_destination(unit)

    _unload_elapsed -= delta
    if _unload_elapsed <= 0.0:
        _unload_elapsed = UNLOAD_INTERVAL
        for harvester in _harvesters:
            if is_instance_valid(harvester):
                _process_harvester_unload_visual(harvester)

    _pending_building_elapsed -= delta
    if _pending_building_elapsed <= 0.0:
        _pending_building_elapsed = PENDING_BUILDING_INTERVAL
        _process_pending_buildings()

    _cleanup_timer -= delta
    if _cleanup_timer <= 0.0:
        _cleanup_timer = 1.0
        _prune()


func _process_pending_buildings() -> void:
    var still_pending: Array = []
    for building in _pending_buildings:
        if not is_instance_valid(building):
            continue
        _initialize_building_rules(building)
        var health_ready := bool(building.has_meta("dev4_health_bar_raised")) or not is_instance_valid(building.ra2_visual)
        var factory_ready := str(building.building_id) != "war_factory" or bool(building.has_meta("dev4_war_factory_visual"))
        if not health_ready or not factory_ready:
            still_pending.append(building)
    _pending_buildings = still_pending


func _settle_occupied_move_destination(unit) -> void:
    if bool(unit.dying) or bool(unit.inside_refinery) or bool(unit.inside_repair_bay):
        return
    var order_type := str(unit.active_order.get("type", ""))
    if not order_type in ["move", "attack_move"] or unit.path.is_empty():
        return
    var destination := Vector2(unit.destination)
    var own_radius := float(unit.stats.get("collision_radius", unit.stats.get("radius", 12.0)))
    if unit.global_position.distance_squared_to(destination) > pow(own_radius + 24.0, 2.0):
        return
    if not is_instance_valid(unit.match_ref):
        return
    var blockers: Array = unit.match_ref.query_units_in_radius(destination, own_radius + 32.0, unit)
    for other in blockers:
        if not is_instance_valid(other) or other == unit or bool(other.dying) or bool(other.inside_refinery) or bool(other.inside_repair_bay):
            continue
        var other_radius := float(other.stats.get("collision_radius", other.stats.get("radius", 12.0)))
        if other.global_position.distance_squared_to(destination) > pow(own_radius + other_radius + 7.0, 2.0):
            continue
        unit.velocity = Vector2.ZERO
        unit.path = PackedVector2Array()
        unit.path_index = 0
        unit._complete_active_order()
        return


func _tune_tree_collision(tree) -> void:
    if not is_instance_valid(tree) or not bool(tree.dense) or not is_instance_valid(tree.static_body):
        return
    tree.static_body.collision_mask = 2
    var shape_node := tree.static_body.get_node_or_null("CollisionShape2D") as CollisionShape2D
    if shape_node == null:
        return
    var circle := shape_node.shape as CircleShape2D
    if circle != null:
        circle.radius = float(tree.map_ref.tile_px) * TREE_VEHICLE_RADIUS_FACTOR


func _enforce_infantry_tree_passthrough(unit) -> void:
    if str(unit.stats.get("category", "")) != "infantry":
        return
    unit.collision_mask = int(unit.collision_mask) & ~8
    unit.saved_collision_mask = int(unit.saved_collision_mask) & ~8


func _stabilize_stationary_tank_facing(unit) -> void:
    if bool(unit.dying):
        return
    var key := int(unit.get_instance_id())
    if unit.velocity.length_squared() > 100.0:
        _stable_vehicle_facings[key] = {
            "facing": Vector2(unit.facing_direction),
            "direction": int(unit.visual_direction)
        }
        return
    var stable: Dictionary = _stable_vehicle_facings.get(key, {})
    if stable.is_empty():
        _stable_vehicle_facings[key] = {"facing": Vector2(unit.facing_direction), "direction": int(unit.visual_direction)}
        return
    var stable_direction := int(stable.get("direction", unit.visual_direction))
    if int(unit.visual_direction) != stable_direction:
        unit.facing_direction = Vector2(stable.get("facing", unit.facing_direction))
        unit.visual_direction = stable_direction
        unit._play_visual_animation("stand", false)


func _tune_tank_lighting_once(unit) -> void:
    if unit.has_meta("dev4_tank_lighting") or not is_instance_valid(unit.ra2_visual):
        return
    var visual = unit.ra2_visual
    if bool(unit.ra2_layered_visual):
        if is_instance_valid(visual.body_base):
            visual.body_base.self_modulate = Color(0.82, 0.82, 0.80, 1.0)
        if is_instance_valid(visual.turret_base):
            visual.turret_base.self_modulate = Color(0.82, 0.82, 0.80, 1.0)
        var muted_team: Color = unit.team_color.darkened(0.16)
        if is_instance_valid(visual.body_remap):
            visual.body_remap.self_modulate = muted_team
        if is_instance_valid(visual.turret_remap):
            visual.turret_remap.self_modulate = muted_team
    else:
        visual.modulate = Color(0.86, 0.86, 0.84, 1.0)
    unit.set_meta("dev4_tank_lighting", true)


func _raise_building_health_bar_once(building) -> void:
    if building.has_meta("dev4_health_bar_raised") or not is_instance_valid(building.ra2_visual):
        return
    var rect: Rect2i = building.ra2_visual.content_rect
    rect.position.y -= 34
    rect.size.y += 34
    building.ra2_visual.content_rect = rect
    building.set_meta("dev4_health_bar_raised", true)
    building.queue_redraw()


func _stabilize_war_factory_production_visual_once(building) -> void:
    if str(building.building_id) != "war_factory" or building.has_meta("dev4_war_factory_visual") or not is_instance_valid(building.ra2_visual):
        return
    building.ra2_visual.animations.erase("ProductionAnim")
    building.ra2_visual.animations.erase("DeployingAnim")
    building._update_ra2_visual_state(true)
    building.set_meta("dev4_war_factory_visual", true)


func _process_harvester_unload_visual(unit) -> void:
    var key := int(unit.get_instance_id())
    var unloading := bool(unit.inside_refinery) and str(unit.harvester_state) == "unloading" and is_instance_valid(unit.unload_refinery)
    if not unloading:
        _end_unload_visual(unit, key)
        return
    var refinery = unit.unload_refinery
    var service_direction := Vector2.RIGHT
    if is_instance_valid(refinery.service_anchor):
        service_direction = refinery.global_position.direction_to(refinery.service_anchor.global_position)
    if service_direction.length_squared() < 0.01:
        service_direction = Vector2.RIGHT
    var inside_distance := maxf(8.0, float(refinery.footprint.x) * float(refinery.map_ref.tile_px) * 0.5 - float(refinery.map_ref.tile_px) * 0.35)
    unit.global_position = refinery.global_position + service_direction.normalized() * inside_distance
    unit.visible = true
    unit.facing_direction = refinery.global_position.direction_to(unit.global_position)
    if unit.facing_direction.length_squared() < 0.01:
        unit.facing_direction = Vector2.RIGHT
    unit.visual_direction = unit._direction_index(unit.facing_direction)
    unit.velocity = Vector2.ZERO
    if not _unload_visuals.has(key):
        _begin_unload_visual(unit, key)
    var alternate = _unload_visuals.get(key)
    if is_instance_valid(alternate):
        alternate.visible = true
        if alternate.get_script() == RA2LayeredVehicleVisual:
            alternate.play_state("stand", unit.visual_direction, unit.visual_direction, false)
        else:
            alternate.play_state("stand", unit.visual_direction, false)


func _begin_unload_visual(unit, key: int) -> void:
    var candidates: Array[String] = []
    var configured: Variant = unit.ra2_profile.get("unload_ra2_ids", [])
    if configured is Array:
        for value in configured:
            candidates.append(str(value).to_upper())
    var alternate_id := ""
    for candidate in candidates:
        if not RA2RuntimeDatabase.get_visual_bundle(candidate, "temperate").is_empty():
            alternate_id = candidate
            break
    if alternate_id.is_empty():
        _unload_visuals[key] = null
        return
    var manifest := RA2RuntimeDatabase.load_manifest(alternate_id)
    var alternate: Variant = RA2LayeredVehicleVisual.new() if manifest.has("layered_vehicle") else RA2VisualPlayer.new()
    alternate.name = UNLOAD_VISUAL_NAME
    unit.add_child(alternate)
    if not alternate.setup(alternate_id, unit.team_color, "temperate"):
        alternate.queue_free()
        _unload_visuals[key] = null
        return
    alternate.configure_layout(float(unit.ra2_profile.get("target_width", 62.0)), float(unit.ra2_profile.get("ground_y", 3.0)), Vector2.ZERO)
    if is_instance_valid(unit.ra2_visual):
        unit.ra2_visual.visible = false
    _unload_visuals[key] = alternate


func _end_unload_visual(unit, key: int) -> void:
    if not _unload_visuals.has(key):
        return
    var alternate = _unload_visuals[key]
    _unload_visuals.erase(key)
    if is_instance_valid(alternate):
        alternate.queue_free()
    if is_instance_valid(unit) and is_instance_valid(unit.ra2_visual):
        unit.ra2_visual.visible = true


func _prune() -> void:
    _units = _units.filter(func(value): return is_instance_valid(value))
    _tanks = _tanks.filter(func(value): return is_instance_valid(value))
    _harvesters = _harvesters.filter(func(value): return is_instance_valid(value))
    _pending_buildings = _pending_buildings.filter(func(value): return is_instance_valid(value))
    var live_ids: Dictionary = {}
    for unit in _units:
        live_ids[int(unit.get_instance_id())] = true
    for key in _stable_vehicle_facings.keys():
        if not live_ids.has(int(key)):
            _stable_vehicle_facings.erase(key)
    for key in _unload_visuals.keys():
        if not live_ids.has(int(key)):
            var visual = _unload_visuals[key]
            if is_instance_valid(visual):
                visual.queue_free()
            _unload_visuals.erase(key)

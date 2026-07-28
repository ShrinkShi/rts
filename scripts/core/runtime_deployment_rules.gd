extends Node

const MATCH_SCRIPT_PATH := "res://scripts/game/rts_match.gd"
const UnitEntity = preload("res://scripts/game/unit.gd")

var _matches: Array = []
var _selection_restore_guard: Dictionary = {}


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_PAUSABLE
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
    if script != null and script.resource_path == MATCH_SCRIPT_PATH and not node in _matches:
        _matches.append(node)


func _input(event: InputEvent) -> void:
    _matches = _matches.filter(func(value): return is_instance_valid(value))
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_D:
        for match_ref in _matches:
            if _match_accepts_input(match_ref) and _handle_deploy_key(match_ref):
                get_viewport().set_input_as_handled()
                return
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
        if _filter_deployed_units_from_right_click():
            get_viewport().set_input_as_handled()


func _match_accepts_input(match_ref) -> bool:
    return is_instance_valid(match_ref) and not bool(match_ref.game_over) and not get_tree().paused


func _handle_deploy_key(match_ref) -> bool:
    var deployable_units: Array = []
    var command_buildings: Array = []
    var mobile_construction_yards: Array = []
    for entity in match_ref.selected_entities:
        if not is_instance_valid(entity):
            continue
        if entity.has_method("is_movable_unit") and str(entity.unit_id) == "mcv":
            mobile_construction_yards.append(entity)
        elif entity.has_method("is_production_building") and str(entity.building_id) == "command":
            command_buildings.append(entity)
        elif entity.has_method("can_deploy") and bool(entity.can_deploy()):
            deployable_units.append(entity)
    if deployable_units.is_empty() and command_buildings.is_empty() and mobile_construction_yards.is_empty():
        return false

    var next_selection: Array = match_ref.selected_entities.duplicate()
    for building in command_buildings:
        var mcv = _pack_command_building(match_ref, building)
        if is_instance_valid(mcv):
            next_selection.erase(building)
            next_selection.append(mcv)
    for mcv in mobile_construction_yards:
        var command = _unpack_mcv(match_ref, mcv)
        if is_instance_valid(command):
            next_selection.erase(mcv)
            next_selection.append(command)

    var has_undeployed := false
    for unit in deployable_units:
        if not bool(unit.deployed) and not bool(unit.deploying):
            has_undeployed = true
            break
    for unit in deployable_units:
        if has_undeployed:
            if not bool(unit.deployed) and not bool(unit.deploying):
                unit.command_deploy()
        elif bool(unit.deployed) or bool(unit.deploying):
            unit.command_deploy()

    match_ref._set_selection(next_selection, false)
    if is_instance_valid(match_ref.overlay):
        match_ref.overlay.add_command_marker(match_ref._selection_center(), Color("#E0D477"), "D")
    return true


func _filter_deployed_units_from_right_click() -> bool:
    for match_ref in _matches:
        if not _match_accepts_input(match_ref) or match_ref.selected_entities.is_empty():
            continue
        if bool(match_ref.placement_mode):
            continue
        var command_mode := str(match_ref.command_mode)
        var movement_command := command_mode in ["", "move", "attack_move", "patrol", "harvest", "repair", "rally"]
        if command_mode == "":
            var world_position: Vector2 = match_ref._screen_to_world(get_viewport().get_mouse_position())
            var target = match_ref.get_entity_at(world_position, true)
            if is_instance_valid(target) and int(target.owner_id) >= 0 and match_ref.are_enemies(0, int(target.owner_id)):
                movement_command = false
        if not movement_command:
            continue
        var original: Array = match_ref.selected_entities.duplicate()
        var mobile: Array = []
        var removed := false
        for entity in original:
            if is_instance_valid(entity) and entity.has_method("is_movable_unit") and (bool(entity.deployed) or bool(entity.deploying)):
                removed = true
                continue
            mobile.append(entity)
        if not removed:
            continue
        if mobile.is_empty():
            EventBus.notification_requested.emit("部署状态单位需按 D 解除部署后才能移动", "warning")
            return true
        match_ref.selected_entities = mobile
        var key := int(match_ref.get_instance_id())
        _selection_restore_guard[key] = original
        call_deferred("_restore_filtered_selection", match_ref, key)
    return false


func _restore_filtered_selection(match_ref, key: int) -> void:
    if not is_instance_valid(match_ref) or not _selection_restore_guard.has(key):
        return
    var original: Array = _selection_restore_guard[key]
    _selection_restore_guard.erase(key)
    var valid: Array = []
    for entity in original:
        if is_instance_valid(entity):
            valid.append(entity)
    match_ref.selected_entities = valid
    if is_instance_valid(match_ref.hud):
        match_ref.hud.set_selection(valid)
    if is_instance_valid(match_ref.overlay):
        match_ref.overlay.set_selected_entities(valid)


func _pack_command_building(match_ref, building):
    if not is_instance_valid(building) or bool(building.destroyed) or bool(building.selling):
        return null
    var owner_id := int(building.owner_id)
    var world_position := Vector2(building.global_position)
    var inherited_hp := float(building.hp)
    var inherited_max_hp := float(building.max_hp)
    var inherited_shield := float(building.shield)

    match_ref.grid.vacate(building)
    match_ref.buildings.erase(building)
    match_ref.repairing_buildings.erase(building)
    match_ref.repair_credit_buffers.erase(int(building.get_instance_id()))
    for key in match_ref.primary_producers.keys():
        if match_ref.primary_producers[key] == building:
            match_ref.primary_producers.erase(key)
    var mcv = _spawn_mcv(match_ref, owner_id, world_position)
    if not is_instance_valid(mcv):
        match_ref.grid.occupy(building.origin_cell, building.footprint, building)
        match_ref.buildings.append(building)
        EventBus.notification_requested.emit("基地周围没有足够空间，无法收起", "warning")
        return null
    mcv.max_hp = inherited_max_hp
    mcv.stats["hp"] = inherited_max_hp
    mcv.hp = clampf(inherited_hp, 1.0, inherited_max_hp)
    mcv.shield = inherited_shield
    mcv.set_meta("packed_command_max_hp", inherited_max_hp)
    building.queue_free()
    match_ref._update_power()
    EventBus.notification_requested.emit("建造中心已收起为基地车", "info")
    return mcv


func _spawn_mcv(match_ref, owner_id: int, world_position: Vector2):
    var data: Dictionary = GameConfig.units.get("mcv", {})
    if data.is_empty():
        return null
    var radius := float(data.get("collision_radius", 21.0))
    var spawn_position := Vector2(match_ref.find_clear_unit_position(world_position, radius, null, "vehicle"))
    if spawn_position == Vector2.ZERO:
        return null
    var unit = UnitEntity.new()
    match_ref.entity_layer.add_child(unit)
    unit.setup(match_ref, match_ref.grid, "mcv", owner_id, spawn_position)
    unit.died.connect(Callable(match_ref, "_on_entity_died"))
    unit.fired.connect(Callable(match_ref, "_spawn_tracer"))
    match_ref.units.append(unit)
    match_ref._invalidate_unit_spatial_hash()
    return unit


func _unpack_mcv(match_ref, mcv):
    if not is_instance_valid(mcv) or bool(mcv.dying):
        return null
    var center_cell: Vector2i = match_ref.grid.world_to_cell(mcv.global_position)
    var origin := center_cell - Vector2i(1, 1)
    var footprint := Vector2i(3, 3)
    if not match_ref.grid.can_place(origin, footprint):
        EventBus.notification_requested.emit("当前位置无法展开基地", "warning")
        return null
    var first_center := Vector2(match_ref.grid.cell_to_world(origin))
    var placement_rect := Rect2(first_center - Vector2(match_ref.grid.tile_px * 0.5, match_ref.grid.tile_px * 0.5), Vector2(footprint.x * match_ref.grid.tile_px, footprint.y * match_ref.grid.tile_px))
    for other in match_ref.units:
        if not is_instance_valid(other) or other == mcv or bool(other.inside_refinery):
            continue
        var radius := float(other.stats.get("collision_radius", other.stats.get("radius", 12.0)))
        if placement_rect.grow(radius).has_point(other.global_position):
            EventBus.notification_requested.emit("展开区域内存在单位", "warning")
            return null
    var command = match_ref.spawn_building(int(mcv.owner_id), "command", origin, false)
    if not is_instance_valid(command):
        EventBus.notification_requested.emit("基地展开失败", "warning")
        return null
    command.max_hp = float(mcv.get_meta("packed_command_max_hp", command.max_hp))
    command.stats["hp"] = command.max_hp
    command.hp = clampf(float(mcv.hp), 1.0, command.max_hp)
    command.shield = float(mcv.shield)
    command._update_damage_visual()
    match_ref.units.erase(mcv)
    match_ref._invalidate_unit_spatial_hash()
    mcv.queue_free()
    match_ref._update_power()
    EventBus.notification_requested.emit("基地车已展开为建造中心", "info")
    return command

extends Node

const MATCH_SCRIPT_PATH := "res://scripts/game/rts_match.gd"
const PRODUCTION_TILE_SCRIPT_PATH := "res://scripts/ui/production_tile.gd"
const MATCH_HUD_SCRIPT_PATH := "res://scripts/ui/match_hud.gd"
const MAX_PRODUCTION_QUEUE := 30
const UI_REFRESH_INTERVAL := 0.18

var _matches: Array = []
var _elapsed := 0.0


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
    if script != null and script.resource_path == MATCH_SCRIPT_PATH and not node in _matches:
        _matches.append(node)


func _process(delta: float) -> void:
    _elapsed -= delta
    if _elapsed > 0.0:
        return
    _elapsed = UI_REFRESH_INTERVAL
    _matches = _matches.filter(func(value): return is_instance_valid(value))
    for match_ref in _matches:
        _refresh_match_ui(match_ref)


func _input(event: InputEvent) -> void:
    if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
        return
    if _handle_production_click(event):
        get_viewport().set_input_as_handled()


func _handle_production_click(event: InputEventMouseButton) -> bool:
    var control: Control = get_viewport().gui_get_hovered_control()
    while is_instance_valid(control):
        var script := control.get_script() as Script
        if script != null and script.resource_path == PRODUCTION_TILE_SCRIPT_PATH:
            if str(control.get("kind")) != "unit" or bool(control.get("disabled")) or not bool(control.get("visible")):
                return false
            var match_ref = _match_for_hud_control(control)
            if not _match_accepts_input(match_ref):
                return false
            _enqueue_units(match_ref, str(control.get("id_value")), 5 if bool(event.shift_pressed) else 1)
            return true
        control = control.get_parent() as Control
    return false


func _match_for_hud_control(control: Node):
    var node: Node = control
    while is_instance_valid(node):
        var script := node.get_script() as Script
        if script != null and script.resource_path == MATCH_HUD_SCRIPT_PATH:
            return node.get("match_ref")
        node = node.get_parent()
    return null


func _match_accepts_input(match_ref) -> bool:
    return is_instance_valid(match_ref) and not bool(match_ref.game_over) and not get_tree().paused


func _enqueue_units(match_ref, unit_id: String, requested_count: int) -> int:
    if not GameConfig.units.has(unit_id):
        return 0
    var data: Dictionary = GameConfig.units[unit_id]
    if bool(data.get("hidden_in_sidebar", false)) or not _requirements_met(match_ref, 0, data):
        return 0
    var added := 0
    var paused = match_ref._producer_with_paused_front(0, unit_id)
    if is_instance_valid(paused) and requested_count > 0:
        paused.resume_front_job(unit_id)
        added += 1
        requested_count -= 1
    var faction := str(match_ref.get_player_data(0).get("faction", "union"))
    var modifier := float(GameConfig.factions.get(faction, {}).get("unit_modifiers", {}).get("cost", 1.0))
    var actual_cost := int(round(float(data.get("cost", 0)) * modifier))
    for _index in range(requested_count):
        if int(match_ref.get_unit_queue_count(0, unit_id)) >= MAX_PRODUCTION_QUEUE:
            if added == 0:
                EventBus.notification_requested.emit("生产队列已满（上限 %d）" % MAX_PRODUCTION_QUEUE, "warning")
            break
        var producer = _producer_with_capacity(match_ref, 0, unit_id)
        if not is_instance_valid(producer):
            if added == 0:
                EventBus.notification_requested.emit("生产队列已满（上限 %d）" % MAX_PRODUCTION_QUEUE, "warning")
            break
        if int(match_ref.credits.get(0, 0)) < actual_cost:
            EventBus.notification_requested.emit("资金不足，已加入 %d 个单位" % added, "warning")
            VoiceManager.speak_adjutant("insufficient_funds")
            break
        match_ref.add_credits(0, -actual_cost)
        producer.enqueue_unit(unit_id, actual_cost)
        added += 1
    if added > 0:
        EventBus.notification_requested.emit("%s 已加入生产队列 ×%d" % [str(data.get("name", unit_id)), added], "info")
    return added


func _producer_with_capacity(match_ref, owner_id: int, unit_id: String):
    var data: Dictionary = GameConfig.units.get(unit_id, {})
    var required := str(data.get("requires", ""))
    if required.is_empty():
        required = "barracks" if str(data.get("category", "infantry")) == "infantry" else "war_factory"
    var primary = match_ref.primary_producers.get("%d:%s" % [owner_id, required])
    if is_instance_valid(primary) and int(primary.owner_id) == owner_id and str(primary.building_id) == required and not bool(primary.destroyed) and primary.production_queue.size() < MAX_PRODUCTION_QUEUE:
        return primary
    var best = null
    var smallest_queue := MAX_PRODUCTION_QUEUE + 1
    for building in match_ref.buildings:
        if not is_instance_valid(building):
            continue
        if int(building.owner_id) != owner_id or str(building.building_id) != required or bool(building.destroyed):
            continue
        var queue_size := int(building.production_queue.size())
        if queue_size < MAX_PRODUCTION_QUEUE and queue_size < smallest_queue:
            smallest_queue = queue_size
            best = building
    return best


func _requirements_met(match_ref, owner_id: int, data: Dictionary) -> bool:
    var requirement: Variant = data.get("requires", "")
    if requirement is Array:
        for item in requirement:
            if not match_ref.has_building(owner_id, str(item)):
                return false
        return true
    var requirement_id := str(requirement)
    return requirement_id.is_empty() or match_ref.has_building(owner_id, requirement_id)


func _refresh_match_ui(match_ref) -> void:
    if not is_instance_valid(match_ref.hud):
        return
    var hud = match_ref.hud
    for id_value in hud.structure_buttons.keys():
        var tile = hud.structure_buttons[id_value]
        if is_instance_valid(tile):
            var data: Dictionary = GameConfig.buildings.get(str(id_value), {})
            tile.visible = not bool(data.get("hidden_in_sidebar", false)) and _requirements_met(match_ref, 0, data)
    for id_value in hud.unit_buttons.keys():
        var tile = hud.unit_buttons[id_value]
        if is_instance_valid(tile):
            var data: Dictionary = GameConfig.units.get(str(id_value), {})
            tile.visible = not bool(data.get("hidden_in_sidebar", false)) and _requirements_met(match_ref, 0, data)
    var power_data: Dictionary = match_ref.power_state.get(0, {"produced": 0, "consumed": 0})
    var produced := int(power_data.get("produced", 0))
    var consumed := int(power_data.get("consumed", 0))
    if is_instance_valid(hud.power_label):
        hud.power_label.text = "电力  %d / %d" % [consumed, produced]
        hud.power_label.add_theme_color_override("font_color", Color("#73D586") if produced >= consumed else Color("#EF6B63"))

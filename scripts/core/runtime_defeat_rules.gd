extends Node

const MATCH_SCRIPT_PATH := "res://scripts/game/rts_match.gd"
const CHECK_INTERVAL := 0.50

var _matches: Array = []
var _defeated_players: Dictionary = {}
var _notice_boxes: Dictionary = {}
var _elapsed := 0.0


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
        _defeated_players[int(node.get_instance_id())] = {}


func _process(delta: float) -> void:
    _elapsed -= delta
    if _elapsed > 0.0:
        return
    _elapsed = CHECK_INTERVAL
    _matches = _matches.filter(func(value): return is_instance_valid(value))
    for key in _notice_boxes.keys():
        if not is_instance_valid(_notice_boxes[key]):
            _notice_boxes.erase(key)
    for match_ref in _matches:
        _process_structure_defeat(match_ref)


func _process_structure_defeat(match_ref) -> void:
    if bool(match_ref.game_over):
        return
    match_ref.victory_check_timer = 999999.0
    var players: Array = match_ref.match_config.get("players", [])
    if players.is_empty():
        return
    var state_key := int(match_ref.get_instance_id())
    var defeated: Dictionary = _defeated_players.get(state_key, {})
    for player_id in range(players.size()):
        if defeated.has(player_id) or _player_has_structure_presence(match_ref, player_id):
            continue
        defeated[player_id] = true
        var player_name := str(match_ref.get_player_data(player_id).get("name", "玩家%d" % (player_id + 1)))
        var defeat_text := "%s被击败了" % player_name
        EventBus.notification_requested.emit(defeat_text, "warning")
        _show_defeat_notice(match_ref, defeat_text)
    _defeated_players[state_key] = defeated
    if defeated.has(0):
        match_ref._end_match(false, "我方所有建筑均已被摧毁")
        return
    var human_team := int(match_ref.get_player_data(0).get("team", 1))
    var enemy_team_alive := false
    for player_id in range(1, players.size()):
        if int(match_ref.get_player_data(player_id).get("team", player_id + 1)) == human_team:
            continue
        if not defeated.has(player_id):
            enemy_team_alive = true
            break
    if not enemy_team_alive:
        match_ref._end_match(true, "敌方所有建筑均已被摧毁")


func _player_has_structure_presence(match_ref, player_id: int) -> bool:
    for building in match_ref.buildings:
        if is_instance_valid(building) and int(building.owner_id) == player_id and not bool(building.destroyed):
            return true
    for unit in match_ref.units:
        if is_instance_valid(unit) and int(unit.owner_id) == player_id and str(unit.unit_id) == "mcv" and not bool(unit.dying):
            return true
    return false


func _show_defeat_notice(match_ref, text_value: String) -> void:
    if not is_instance_valid(match_ref.hud) or not is_instance_valid(match_ref.hud.root_control):
        return
    var match_key := int(match_ref.get_instance_id())
    var box = _notice_boxes.get(match_key)
    if not is_instance_valid(box):
        box = VBoxContainer.new()
        box.name = "DefeatNotices"
        box.offset_left = 12.0
        box.offset_top = 48.0
        box.offset_right = 344.0
        box.offset_bottom = 190.0
        box.mouse_filter = Control.MOUSE_FILTER_IGNORE
        box.add_theme_constant_override("separation", 5)
        match_ref.hud.root_control.add_child(box)
        _notice_boxes[match_key] = box
    var label := Label.new()
    label.text = text_value
    label.custom_minimum_size = Vector2(320.0, 34.0)
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.add_theme_font_size_override("font_size", 15)
    label.add_theme_color_override("font_color", Color("#F0E7DB"))
    label.add_theme_color_override("font_outline_color", Color.BLACK)
    label.add_theme_constant_override("outline_size", 4)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_child(label)
    get_tree().create_timer(4.5).timeout.connect(func():
        if is_instance_valid(label):
            label.queue_free()
    )

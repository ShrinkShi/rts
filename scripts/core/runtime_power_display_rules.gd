extends Node

const MATCH_SCRIPT_PATH := "res://scripts/game/rts_match.gd"
const GREEN := Color("#73D586")
const YELLOW := Color("#E5C45D")
const RED := Color("#EF6B63")

var _matches: Array = []
var _last_signatures: Dictionary = {}


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_PAUSABLE
    # MatchHUD still updates several other widgets in its own _process(). Run after
    # every existing HUD writer so this node is the final authority before render.
    process_priority = 10000
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
    var script: Script = node.get_script() as Script
    if script != null and script.resource_path == MATCH_SCRIPT_PATH and not node in _matches:
        _matches.append(node)


func _process(_delta: float) -> void:
    _matches = _matches.filter(func(value): return is_instance_valid(value))
    for match_ref in _matches:
        _update_match_power(match_ref)


func _update_match_power(match_ref) -> void:
    if not is_instance_valid(match_ref.hud) or not is_instance_valid(match_ref.hud.power_label):
        return
    var power_data: Dictionary = match_ref.power_state.get(0, {"produced": 0, "consumed": 0})
    var produced: int = maxi(0, int(power_data.get("produced", 0)))
    var consumed: int = maxi(0, int(power_data.get("consumed", 0)))
    var load_ratio: float = 0.0
    if produced <= 0:
        load_ratio = INF if consumed > 0 else 0.0
    else:
        load_ratio = float(consumed) / float(produced)
    var color: Color = _color_for_load(load_ratio)
    var next_text: String = "电力  %d / %d" % [consumed, produced]
    var signature: String = "%s:%s" % [next_text, color.to_html()]
    var key: int = int(match_ref.get_instance_id())
    if str(_last_signatures.get(key, "")) == signature and match_ref.hud.power_label.text == next_text:
        return
    match_ref.hud.power_label.text = next_text
    match_ref.hud.power_label.tooltip_text = "当前用电量 / 总发电量\n负载率：%s" % _load_text(load_ratio)
    match_ref.hud.power_label.add_theme_color_override("font_color", color)
    match_ref.hud.power_label.set_meta("runtime_power_display_owned", true)
    _last_signatures[key] = signature


func _color_for_load(load_ratio: float) -> Color:
    if is_inf(load_ratio) or load_ratio > 1.0:
        return RED
    if load_ratio > 0.75:
        return YELLOW
    return GREEN


func _load_text(load_ratio: float) -> String:
    if is_inf(load_ratio):
        return "超负荷"
    return "%.0f%%" % (load_ratio * 100.0)

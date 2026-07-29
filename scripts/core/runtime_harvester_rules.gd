extends Node

const UNIT_SCRIPT_PATHS := [
    "res://scripts/game/unit.gd",
    "res://scripts/game/ra2_unit.gd",
]
const SOVIET_HARVESTER_ID := "HARV"
const HALF_TURN_DIRECTIONS := 4

var _soviet_harvesters: Array = []


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_PAUSABLE
    process_priority = 210
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
    if script == null:
        return
    if not UNIT_SCRIPT_PATHS.has(script.resource_path):
        return
    call_deferred("_try_register_harvester", node)


func _try_register_harvester(unit) -> void:
    if not is_instance_valid(unit):
        return
    if str(unit.unit_id) != "harvester" or str(unit.ra2_entity_id) != SOVIET_HARVESTER_ID:
        return
    if not _soviet_harvesters.has(unit):
        _soviet_harvesters.append(unit)
    unit.stats["strategic_role"] = "economy"
    unit.stats["ai_attack_unit"] = false


func _process(_delta: float) -> void:
    _soviet_harvesters = _soviet_harvesters.filter(func(value): return is_instance_valid(value))
    for unit in _soviet_harvesters:
        _correct_soviet_harvester_facing(unit)


func _correct_soviet_harvester_facing(unit) -> void:
    if bool(unit.dying) or not bool(unit.ra2_layered_visual):
        return
    if not is_instance_valid(unit.ra2_visual):
        return
    var desired_body_direction: int = posmod(
        int(unit.visual_direction) + HALF_TURN_DIRECTIONS,
        8
    )
    var desired_turret_direction: int = int(unit.turret_visual_direction)
    var desired_state: String = str(unit.visual_state)
    if desired_state.is_empty():
        desired_state = "stand"
    if (
        int(unit.ra2_visual.current_body_direction) == desired_body_direction
        and int(unit.ra2_visual.current_turret_direction) == desired_turret_direction
        and str(unit.ra2_visual.current_state) == desired_state
    ):
        return
    unit.ra2_visual.play_state(
        desired_state,
        desired_body_direction,
        desired_turret_direction,
        false
    )

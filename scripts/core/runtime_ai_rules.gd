extends Node

const AI_SCRIPT_PATH := "res://scripts/game/ai_controller.gd"
const REPAIR_SCAN_INTERVAL := 0.35

var _controllers: Array = []
var _scan_elapsed := 0.0


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_PAUSABLE
    get_tree().node_added.connect(_on_node_added)
    _register_existing(get_tree().root)


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
    if script != null and script.resource_path == AI_SCRIPT_PATH and not node in _controllers:
        _controllers.append(node)


func _process(delta: float) -> void:
    _controllers = _controllers.filter(func(value): return is_instance_valid(value))
    _scan_elapsed -= delta
    if _scan_elapsed > 0.0:
        return
    _scan_elapsed = REPAIR_SCAN_INTERVAL
    for controller in _controllers:
        _repair_one_building(controller, REPAIR_SCAN_INTERVAL)


func _repair_one_building(controller, repair_delta: float) -> void:
    if not is_instance_valid(controller.match_ref) or bool(controller.match_ref.game_over):
        return
    var match_ref = controller.match_ref
    var owner_id := int(controller.owner_id)
    var damaged: Array = []
    for building in match_ref.buildings:
        if not is_instance_valid(building) or int(building.owner_id) != owner_id:
            continue
        if bool(building.destroyed) or bool(building.selling) or float(building.hp) >= float(building.max_hp):
            if is_instance_valid(building) and bool(building.repair_active) and not is_instance_valid(building.repairing_vehicle):
                building.set_repair_active(false)
            continue
        damaged.append(building)
    if damaged.is_empty():
        return
    damaged.sort_custom(func(a, b):
        return float(a.hp) / maxf(1.0, float(a.max_hp)) < float(b.hp) / maxf(1.0, float(b.max_hp))
    )
    var target = damaged[0]
    target.set_repair_active(true)
    var result: Dictionary = match_ref.repair_entity_step(target, repair_delta * 1.25, target)
    if bool(result.get("complete", false)) or bool(result.get("no_funds", false)):
        target.set_repair_active(false)

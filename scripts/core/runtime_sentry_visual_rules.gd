extends Node

const BUILDING_SCRIPT_PATH := "res://scripts/game/ra2_building.gd"
const SentryGunVisual = preload("res://scripts/game/sentry_gun_visual.gd")

var _buildings: Array = []


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_PAUSABLE
    process_priority = 120
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
    if script != null and script.resource_path == BUILDING_SCRIPT_PATH and not node in _buildings:
        _buildings.append(node)


func _process(_delta: float) -> void:
    _buildings = _buildings.filter(func(value): return is_instance_valid(value))
    for building in _buildings:
        if str(building.ra2_entity_id) != "NALASR":
            continue
        _update_sentry(building)


func _update_sentry(building) -> void:
    var head: Node = building.get_node_or_null("RuntimeSentryGunHead")
    if not is_instance_valid(head):
        head = SentryGunVisual.new()
        head.name = "RuntimeSentryGunHead"
        building.add_child(head)
        head.configure(Color(building.team_color))
    var visible_now: bool = (
        not bool(building.destroyed)
        and not bool(building.selling)
        and float(building.construction_progress) >= 0.98
    )
    head.visible = visible_now
    if not visible_now:
        return
    if is_instance_valid(building.ra2_visual):
        var damage_progress: float = 1.0 if int(building.damage_stage) > 0 else 0.0
        building.ra2_visual.set_progress("BodyStates", damage_progress, 0)
        building.ra2_visual_state = "damaged" if damage_progress > 0.0 else "normal"
    head.position = Vector2(0.0, -float(building.terrain_ground_height) - 24.0)
    head.set_state(
        Vector2(building.turret_facing),
        float(building.attack_animation_time) > 0.0,
        int(building.damage_stage) > 0,
        bool(building.powered)
    )

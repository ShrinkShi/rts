extends Node

const BUILDING_SCRIPT_PATH := "res://scripts/game/ra2_building.gd"
const SOVIET_SENTRY_ID := "NALASR"
const LEGACY_CUSTOM_HEAD := "RuntimeSentryGunHead"

var _buildings: Array = []
var _initialized: Dictionary = {}


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
        if str(building.ra2_entity_id) != SOVIET_SENTRY_ID:
            continue
        _use_original_ra2_sentry(building)


func _use_original_ra2_sentry(building) -> void:
    var legacy_head: Node = building.get_node_or_null(LEGACY_CUSTOM_HEAD)
    if is_instance_valid(legacy_head):
        legacy_head.queue_free()
    if is_instance_valid(building.turret_sprite):
        building.turret_sprite.visible = false
    if not is_instance_valid(building.ra2_visual):
        return

    var key: int = int(building.get_instance_id())
    if not _initialized.has(key):
        # NALASR's extracted Ready and DamagedReady composites come directly from
        # nglasr.shp. Do not replace their turret with the old hand-drawn head.
        building.ra2_visual.configure_layout(
            float(building.ra2_profile.get("target_width", 44.0)),
            float(building.ra2_profile.get("ground_y", 7.0)),
            Vector2.ZERO
        )
        _initialized[key] = true

    if bool(building.destroyed) or bool(building.selling):
        return
    if float(building.construction_progress) < 0.98:
        return
    var desired_state: String = "damaged" if int(building.damage_stage) > 0 else "normal"
    if str(building.ra2_visual_state) != desired_state:
        building.ra2_visual.play_state(desired_state, 0, true)
        building.ra2_visual_state = desired_state

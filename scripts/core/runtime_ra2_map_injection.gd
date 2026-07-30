extends Node

const GRID_SCRIPT_PATH := "res://scripts/game/grid_world.gd"
const MATCH_SCRIPT_PATH := "res://scripts/game/rts_match.gd"
const RA2IsoGridWorld = preload("res://scripts/game/ra2_iso_grid_world_v2.gd")


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
    if not is_instance_valid(node):
        return
    var script: Script = node.get_script() as Script
    if script == null or script.resource_path != GRID_SCRIPT_PATH:
        return
    var parent: Node = node.get_parent()
    if not is_instance_valid(parent):
        return
    var parent_script: Script = parent.get_script() as Script
    if parent_script == null or parent_script.resource_path != MATCH_SCRIPT_PATH:
        return
    var config_variant: Variant = parent.get("match_config")
    if not config_variant is Dictionary:
        return
    var match_config: Dictionary = config_variant
    var map_id: String = str(match_config.get("map_id", ""))
    var map_definition: Dictionary = GameConfig.maps.get(map_id, {})
    if str(map_definition.get("format", "")) != "ra2_runtime_v1":
        return

    # SceneTree.node_added is emitted synchronously. rts_match adds GridWorld and
    # calls generate() on the next line, so this replacement happens before the
    # procedural generator can run.
    node.set_script(RA2IsoGridWorld)
    if bool(map_definition.get("force_disable_fog", false)):
        match_config["fog_of_war"] = false
        parent.set("match_config", match_config)

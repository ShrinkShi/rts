@tool
extends EditorPlugin

const DockScript = preload("res://addons/ra2_asset_importer/ra2_import_dock.gd")
var dock: Control


func _enter_tree() -> void:
    dock = DockScript.new()
    add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_BL, dock)


func _exit_tree() -> void:
    if dock != null:
        remove_control_from_docks(dock)
        dock.queue_free()
        dock = null

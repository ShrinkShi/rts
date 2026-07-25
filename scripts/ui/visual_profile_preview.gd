@tool
extends Node2D

const SpriteSheetFactory = preload("res://scripts/game/sprite_sheet_factory.gd")

@export_enum("rifle", "rocket", "tank", "scout", "harvester", "command", "power", "barracks", "refinery", "war_factory", "repair_bay", "turret", "bunker")
var entity_id: String = "harvester":
    set(value):
        entity_id = value
        _rebuild_preview()

@export var profile: Resource:
    set(value):
        profile = value
        _load_transform_from_profile()
        _rebuild_preview()

@export_category("可视化工作流")
@export var load_from_profile_trigger := false:
    set(value):
        if value:
            _load_transform_from_profile()
@export var save_to_profile_trigger := false:
    set(value):
        if value:
            _save_transform_to_profile()

var editable_transform: Node2D
var preview_visual: CanvasItem

func _ready():
    _ensure_nodes()
    _load_transform_from_profile()
    _rebuild_preview()
    queue_redraw()

func _process(_delta):
    if Engine.is_editor_hint():
        queue_redraw()

func _ensure_nodes():
    editable_transform = get_node_or_null("EditableTransform")
    if editable_transform == null:
        editable_transform = Node2D.new()
        editable_transform.name = "EditableTransform"
        add_child(editable_transform)
        editable_transform.owner = get_tree().edited_scene_root if Engine.is_editor_hint() else null

func _clear_preview():
    if is_instance_valid(preview_visual):
        preview_visual.queue_free()
        preview_visual = null

func _unit_base_transform(id_value):
    var category = "infantry" if id_value in ["rifle", "rocket"] else "vehicle"
    var base_position = Vector2(0, -13 if category == "infantry" else -11)
    var base_scale = 0.72 if category == "infantry" else 0.88
    if id_value == "rifle":
        base_scale = 0.58
        base_position = Vector2(0, -16)
    elif id_value == "tank":
        base_scale = 0.52
        base_position = Vector2(0, -12)
    elif id_value == "harvester":
        base_scale = 0.94
    return [base_position, Vector2.ONE * base_scale]

func _building_footprint(id_value):
    return {
        "command": Vector2i(3, 3), "power": Vector2i(2, 2), "barracks": Vector2i(2, 2),
        "refinery": Vector2i(3, 2), "war_factory": Vector2i(3, 3), "repair_bay": Vector2i(3, 2),
        "turret": Vector2i(1, 1), "bunker": Vector2i(1, 1)
    }.get(id_value, Vector2i(2, 2))

func _rebuild_preview():
    if not is_inside_tree():
        return
    _ensure_nodes()
    _clear_preview()
    var building_ids = ["command", "power", "barracks", "refinery", "war_factory", "repair_bay", "turret", "bunker"]
    if entity_id in building_ids:
        var sprite = Sprite2D.new()
        sprite.texture = SpriteSheetFactory.get_building_frame(entity_id, 0)
        sprite.centered = true
        sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        var footprint = _building_footprint(entity_id)
        var frame_size = SpriteSheetFactory.get_building_frame_size(entity_id)
        var target_width = max(64.0, footprint.x * 32.0 * 1.42)
        var scale_value = target_width / frame_size.x
        if entity_id in ["turret", "bunker"]:
            scale_value *= 1.34
        sprite.scale = Vector2.ONE * scale_value
        sprite.position = Vector2(0, -max(18.0, footprint.y * 32.0 * 0.42))
        editable_transform.add_child(sprite)
        preview_visual = sprite
    else:
        var sprite = AnimatedSprite2D.new()
        sprite.sprite_frames = SpriteSheetFactory.get_unit_frames(entity_id)
        sprite.centered = true
        sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
        var transform_data = _unit_base_transform(entity_id)
        sprite.position = transform_data[0]
        sprite.scale = transform_data[1]
        editable_transform.add_child(sprite)
        sprite.play("stand_0")
        preview_visual = sprite

func _load_transform_from_profile():
    if not is_inside_tree() or profile == null:
        return
    _ensure_nodes()
    editable_transform.position = Vector2(profile.get("visual_offset"))
    editable_transform.scale = Vector2(profile.get("visual_scale_multiplier"))

func _save_transform_to_profile():
    if profile == null or not is_instance_valid(editable_transform):
        return
    profile.set("visual_offset", editable_transform.position)
    profile.set("visual_scale_multiplier", editable_transform.scale)
    profile.emit_changed()
    var path = profile.resource_path
    if path != "":
        ResourceSaver.save(profile, path)
    print("Visual profile saved: ", path, " offset=", editable_transform.position, " scale=", editable_transform.scale)

func _draw():
    # 32px runtime tile guides and logical origin marker.
    for value in range(-160, 161, 32):
        draw_line(Vector2(value, -160), Vector2(value, 160), Color(0.32, 0.45, 0.50, 0.28), 1.0)
        draw_line(Vector2(-160, value), Vector2(160, value), Color(0.32, 0.45, 0.50, 0.28), 1.0)
    draw_line(Vector2(-170, 0), Vector2(170, 0), Color(0.90, 0.72, 0.25, 0.75), 2.0)
    draw_line(Vector2(0, -170), Vector2(0, 170), Color(0.90, 0.72, 0.25, 0.75), 2.0)
    draw_circle(Vector2.ZERO, 4.0, Color("#F2C744"))

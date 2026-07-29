extends Node2D

const RA2OriginalTextures = preload("res://scripts/ra2/ra2_original_texture_library.gd")

var match_ref
var map_ref
var cell := Vector2i.ZERO
var animation_elapsed := 0.0
var animation_frame := 0
var spread_elapsed := 0.0
var spread_interval := 10.0
var static_body: StaticBody2D


func setup(next_match, next_map, next_cell: Vector2i) -> void:
    match_ref = next_match
    map_ref = next_map
    cell = next_cell
    global_position = map_ref.cell_to_world(cell)
    z_index = 2
    spread_interval = 8.5 + float(posmod(cell.x * 13 + cell.y * 29, 7)) * 0.75
    _build_collision()
    queue_redraw()


func _build_collision() -> void:
    static_body = StaticBody2D.new()
    static_body.collision_layer = 4
    static_body.collision_mask = 3
    var shape_node := CollisionShape2D.new()
    var circle := CircleShape2D.new()
    circle.radius = 9.0
    shape_node.shape = circle
    static_body.add_child(shape_node)
    add_child(static_body)


func _process(delta: float) -> void:
    animation_elapsed += delta
    if animation_elapsed >= 0.16:
        animation_elapsed = fmod(animation_elapsed, 0.16)
        animation_frame = (animation_frame + 1) % 11
        queue_redraw()
    spread_elapsed += delta
    if spread_elapsed >= spread_interval:
        spread_elapsed = 0.0
        spread_interval = 8.5 + float(posmod(int(Time.get_ticks_msec()) + cell.x * 7 + cell.y * 11, 8)) * 0.7
        RuntimeRA2ResourceRules.spread_ore(match_ref, cell)


func is_resource_entity() -> bool:
    return true


func get_selection_rect() -> Rect2:
    return Rect2(global_position - Vector2(22, 30), Vector2(44, 48))


func take_damage(_amount, _source = null) -> float:
    return 0.0


func _draw() -> void:
    var texture := RA2OriginalTextures.texture("tibtre01_%02d" % animation_frame)
    if texture == null:
        draw_circle(Vector2(0, -8), 12.0, Color("#D0A52A"))
        return
    var texture_size := texture.get_size()
    var target_width := 54.0
    var scale_value := target_width / maxf(1.0, texture_size.x)
    var size_value := texture_size * scale_value
    draw_texture_rect(
        texture,
        Rect2(Vector2(-size_value.x * 0.5, 10.0 - size_value.y), size_value),
        false
    )

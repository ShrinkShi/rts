extends Node2D

const RA2OriginalTextures = preload("res://scripts/ra2/ra2_original_texture_library.gd")

var match_ref
var map_ref
var cell: Vector2i = Vector2i.ZERO
var owner_id: int = -1
var resource_id: String = "ore"
var hp: float = INF
var max_hp: float = INF
var selected: bool = false
var hover_state: String = ""
var max_remaining: int = 1800
var team_color: Color = Color("#D6B94B")
var overlay_texture: Texture2D
var overlay_asset_id: String = ""
var stats: Dictionary = {
    "name": "矿石",
    "resource_type": "矿石资源",
    "armor": 0,
    "armor_type": "无敌资源",
    "description": "使用《红色警戒2》温带 TIB Overlay。采矿车持续消耗储量，储量归零后矿石消失。"
}


func setup(next_match, next_map, next_cell) -> void:
    match_ref = next_match
    map_ref = next_map
    cell = Vector2i(next_cell)
    global_position = Vector2(map_ref.cell_to_world(cell))
    max_remaining = maxi(1, int(map_ref.get_ore_capacity(cell)))
    z_index = 1
    z_as_relative = true
    _refresh_overlay_texture()
    if not map_ref.ore_changed.is_connected(_on_ore_changed):
        map_ref.ore_changed.connect(_on_ore_changed)
    queue_redraw()


func _exit_tree() -> void:
    if is_instance_valid(map_ref) and map_ref.ore_changed.is_connected(_on_ore_changed):
        map_ref.ore_changed.disconnect(_on_ore_changed)


func _on_ore_changed(changed_cell: Vector2i, _remaining: int) -> void:
    if changed_cell != cell:
        return
    max_remaining = maxi(max_remaining, int(map_ref.get_ore_capacity(cell)))
    _refresh_overlay_texture()
    queue_redraw()


func _refresh_overlay_texture() -> void:
    overlay_texture = null
    overlay_asset_id = ""
    if not is_instance_valid(map_ref) or get_remaining() <= 0:
        return
    var ratio: float = clampf(
        float(get_remaining()) / float(maxi(1, max_remaining)),
        0.0,
        1.0
    )
    var stage: int = clampi(int(round(ratio * 11.0)), 0, 11)
    overlay_asset_id = "ore_%02d" % stage
    overlay_texture = RA2OriginalTextures.texture(overlay_asset_id)


func is_resource_entity() -> bool:
    return true


func is_depleted() -> bool:
    return get_remaining() <= 0


func get_remaining() -> int:
    return int(map_ref.get_ore_amount(cell)) if is_instance_valid(map_ref) else 0


func get_selection_rect() -> Rect2:
    var size_value: Vector2 = Vector2(42.0, 34.0)
    return Rect2(global_position - size_value * 0.5, size_value)


func set_selected(value: bool) -> void:
    selected = value
    queue_redraw()


func set_hover_state(value: String) -> void:
    if hover_state == value:
        return
    hover_state = value
    queue_redraw()


func get_sight_radius_cells() -> int:
    return 0


func take_damage(_amount, _source = null) -> float:
    return 0.0


func _draw() -> void:
    if not is_instance_valid(map_ref):
        return
    var remaining: int = get_remaining()
    var ratio: float = clampf(
        float(remaining) / float(maxi(1, max_remaining)),
        0.0,
        1.0
    )
    if remaining > 0:
        if overlay_texture != null:
            _draw_overlay_texture(ratio)
        else:
            _draw_fallback(ratio)
    var half: float = float(map_ref.tile_px) * 0.5 - 2.0
    if selected or not hover_state.is_empty():
        draw_rect(
            Rect2(Vector2(-half, -half), Vector2(half * 2.0, half * 2.0)),
            Color("#75E6FF") if selected else Color("#E6CB64"),
            false,
            2.0
        )
    if selected:
        var label: String = "%d" % remaining
        draw_string_outline(
            ThemeDB.fallback_font,
            Vector2(-half, -half - 5.0),
            label,
            HORIZONTAL_ALIGNMENT_CENTER,
            half * 2.0,
            11,
            2,
            Color.BLACK
        )
        draw_string(
            ThemeDB.fallback_font,
            Vector2(-half, -half - 5.0),
            label,
            HORIZONTAL_ALIGNMENT_CENTER,
            half * 2.0,
            11,
            Color("#F1D66A")
        )


func _draw_overlay_texture(ratio: float) -> void:
    var texture_size: Vector2 = overlay_texture.get_size()
    if texture_size.x <= 0.0 or texture_size.y <= 0.0:
        return
    var scale_value: float = (
        float(map_ref.tile_px) * 1.55 / texture_size.x
    ) * lerpf(0.86, 1.0, ratio)
    var size_value: Vector2 = texture_size * scale_value
    var target_rect: Rect2 = Rect2(
        Vector2(-size_value.x * 0.5, float(map_ref.tile_px) * 0.48 - size_value.y),
        size_value
    )
    draw_texture_rect(overlay_texture, target_rect, false)


func _draw_fallback(ratio: float) -> void:
    var radius: float = lerpf(7.0, 15.0, ratio)
    draw_circle(Vector2(0.0, 3.0), radius, Color("#C89D24"))
    draw_circle(Vector2(-4.0, -2.0), radius * 0.55, Color("#F2D55B"))

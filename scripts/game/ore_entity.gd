extends Node2D

const OVERLAY_ROOT := "res://assets/ra2_overlays"
const THEATER_EXTENSIONS := {
    "temperate": "tem",
    "snow": "sno",
    "urban": "urb",
    "newurban": "ubn",
    "desert": "des",
    "lunar": "lun",
}

var match_ref
var map_ref
var cell = Vector2i.ZERO
var owner_id = -1
var resource_id = "ore"
var hp = INF
var max_hp = INF
var selected = false
var hover_state = ""
var max_remaining = 1800
var team_color = Color("#D6B94B")
var overlay_texture: Texture2D
var overlay_asset_id = ""
var stats = {
    "name": "矿石",
    "resource_type": "矿石资源",
    "armor": 0,
    "armor_type": "无敌资源",
    "description": "矿石是独立 Overlay 资源实体。采矿车持续消耗其储量，储量归零后 Overlay 消失。"
}


func setup(next_match, next_map, next_cell) -> void:
    match_ref = next_match
    map_ref = next_map
    cell = next_cell
    global_position = map_ref.cell_to_world(cell)
    max_remaining = max(1, int(map_ref.get_ore_capacity(cell)))
    z_index = 0
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
    _refresh_overlay_texture()
    queue_redraw()


func _refresh_overlay_texture() -> void:
    overlay_texture = null
    overlay_asset_id = ""
    if not is_instance_valid(map_ref) or get_remaining() <= 0:
        return

    overlay_asset_id = str(map_ref.get_overlay_asset_id(cell)).to_lower()
    if overlay_asset_id.is_empty():
        return

    var theater = str(map_ref.map_config.get("theater", "temperate")).to_lower()
    var extension = str(THEATER_EXTENSIONS.get(theater, "tem"))
    var candidates = [
        "%s/%s/%s.png" % [OVERLAY_ROOT, theater, overlay_asset_id],
        "%s/%s/%s.%s.png" % [OVERLAY_ROOT, theater, overlay_asset_id, extension],
        "%s/temperate/%s.png" % [OVERLAY_ROOT, overlay_asset_id],
    ]
    for path in candidates:
        if ResourceLoader.exists(path):
            overlay_texture = load(path) as Texture2D
            if overlay_texture != null:
                return


func is_resource_entity() -> bool:
    return true


func is_depleted() -> bool:
    return get_remaining() <= 0


func get_remaining() -> int:
    if not is_instance_valid(map_ref):
        return 0
    return int(map_ref.get_ore_amount(cell))


func get_selection_rect() -> Rect2:
    if not is_instance_valid(map_ref):
        return Rect2(global_position - Vector2(18, 18), Vector2(36, 36))
    var size_value := Vector2(map_ref.tile_px * 1.15, map_ref.tile_px * 1.05)
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

    var remaining = get_remaining()
    var ratio = clampf(float(remaining) / float(max_remaining), 0.0, 1.0)
    if remaining > 0:
        if overlay_texture != null:
            _draw_overlay_texture(ratio)
        else:
            _draw_visible_fallback_overlay(ratio)

    var half = map_ref.tile_px * 0.5 - 2.0
    if selected or hover_state != "":
        var color := Color("#75E6FF") if selected else Color("#E6CB64")
        draw_rect(
            Rect2(Vector2(-half, -half), Vector2(half * 2.0, half * 2.0)),
            color,
            false,
            2.0
        )

    if selected:
        var label := "%d" % remaining
        draw_string_outline(
            ThemeDB.fallback_font,
            Vector2(-half, -half - 5),
            label,
            HORIZONTAL_ALIGNMENT_CENTER,
            half * 2.0,
            11,
            2,
            Color.BLACK
        )
        draw_string(
            ThemeDB.fallback_font,
            Vector2(-half, -half - 5),
            label,
            HORIZONTAL_ALIGNMENT_CENTER,
            half * 2.0,
            11,
            Color("#F1D66A")
        )


func _draw_overlay_texture(ratio: float) -> void:
    var texture_size = overlay_texture.get_size()
    if texture_size.x <= 0.0 or texture_size.y <= 0.0:
        _draw_visible_fallback_overlay(ratio)
        return
    var target_width = map_ref.tile_px * 1.45
    var scale_value = minf(1.0, target_width / texture_size.x)
    scale_value *= lerp(0.82, 1.0, ratio)
    var size_value = texture_size * scale_value
    # Overlay resources are anchored by their ground contact, not their canvas centre.
    var target_rect = Rect2(
        Vector2(-size_value.x * 0.5, map_ref.tile_px * 0.42 - size_value.y),
        size_value
    )
    draw_texture_rect(overlay_texture, target_rect, false)


func _draw_visible_fallback_overlay(ratio: float) -> void:
    # This is a deliberately obvious pixel-art fallback, not a terrain square.
    # It remains until TIB01.TEM..TIB20.TEM are converted into assets/ra2_overlays.
    var stage = clampi(int(ceil(ratio * 4.0)), 1, 4)
    var variation = posmod(cell.x * 17 + cell.y * 31, 5)
    var shadow_width = 10.0 + float(stage) * 3.0
    draw_colored_polygon(
        PackedVector2Array([
            Vector2(-shadow_width, 7),
            Vector2(shadow_width, 7),
            Vector2(shadow_width - 3, 11),
            Vector2(-shadow_width + 3, 11),
        ]),
        Color(0.08, 0.06, 0.02, 0.56)
    )

    var centers = [
        Vector2(-8, 4),
        Vector2(5, 5),
        Vector2(-1, -3),
        Vector2(10, -2),
        Vector2(-11, -4),
        Vector2(3, -9),
    ]
    var count = mini(centers.size(), stage + 2)
    for index in range(count):
        var jitter = Vector2(
            float(posmod(variation * 3 + index * 5, 3) - 1),
            float(posmod(variation * 7 + index * 2, 3) - 1)
        )
        var crystal_scale = 0.72 + 0.09 * float((index + variation) % 3)
        _draw_ore_crystal(centers[index] + jitter, crystal_scale, index)


func _draw_ore_crystal(center: Vector2, crystal_scale: float, index: int) -> void:
    var outline = Color("#44320B")
    var dark = Color("#9D7515")
    var body = Color("#D5AE2E") if index % 2 == 0 else Color("#C49320")
    var bright = Color("#F4DC67")

    var outer = PackedVector2Array([
        center + Vector2(-5, 3) * crystal_scale,
        center + Vector2(-4, -3) * crystal_scale,
        center + Vector2(-1, -7) * crystal_scale,
        center + Vector2(3, -5) * crystal_scale,
        center + Vector2(6, 1) * crystal_scale,
        center + Vector2(3, 5) * crystal_scale,
        center + Vector2(-2, 6) * crystal_scale,
    ])
    draw_colored_polygon(outer, outline)

    var inner = PackedVector2Array([
        center + Vector2(-3.5, 2.5) * crystal_scale,
        center + Vector2(-2.8, -2.2) * crystal_scale,
        center + Vector2(-0.7, -5.0) * crystal_scale,
        center + Vector2(2.2, -3.7) * crystal_scale,
        center + Vector2(4.2, 0.8) * crystal_scale,
        center + Vector2(2.1, 3.6) * crystal_scale,
        center + Vector2(-1.6, 4.2) * crystal_scale,
    ])
    draw_colored_polygon(inner, body)

    var shade = PackedVector2Array([
        center + Vector2(-3.2, 2.2) * crystal_scale,
        center + Vector2(-2.5, -1.5) * crystal_scale,
        center + Vector2(-0.7, 0.1) * crystal_scale,
        center + Vector2(-1.3, 3.4) * crystal_scale,
    ])
    draw_colored_polygon(shade, dark)

    draw_line(
        center + Vector2(-0.4, -4.2) * crystal_scale,
        center + Vector2(1.8, -2.8) * crystal_scale,
        bright,
        maxf(1.0, crystal_scale)
    )

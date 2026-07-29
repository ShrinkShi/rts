extends Node2D

const HEIGHT_STEP_PIXELS := 16.0
const SLOPE_NONE := 0
const SLOPE_N := 1
const SLOPE_NE := 2
const SLOPE_E := 3
const SLOPE_SE := 4
const SLOPE_S := 5
const SLOPE_SW := 6
const SLOPE_W := 7
const SLOPE_NW := 8

var map_ref: Node


func setup(next_map: Node) -> void:
    map_ref = next_map
    name = "RA2HeightTerrainOverlay"
    z_index = 0
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    queue_redraw()


func _atlas_texture() -> Texture2D:
    if not is_instance_valid(map_ref) or map_ref.tile_set == null:
        return null
    if not map_ref.tile_set.has_source(int(map_ref.source_id)):
        return null
    var source: TileSetAtlasSource = map_ref.tile_set.get_source(int(map_ref.source_id)) as TileSetAtlasSource
    return source.texture if source != null else null


func _cell_rect(cell: Vector2i) -> Rect2:
    var center: Vector2 = Vector2(map_ref.map_to_local(cell))
    var half: float = float(map_ref.tile_px) * 0.5
    return Rect2(center - Vector2.ONE * half, Vector2.ONE * float(map_ref.tile_px))


func _terrain_region(cell: Vector2i) -> Rect2:
    var terrain_type: int = int(map_ref.get_terrain(cell))
    var seed_value: int = int(map_ref.map_config.get("seed", 1))
    var variant: int = posmod(cell.x * 17 + cell.y * 31 + seed_value * 13, 8)
    return Rect2(
        float((terrain_type * 8 + variant) * int(map_ref.tile_px)),
        0.0,
        float(map_ref.tile_px),
        float(map_ref.tile_px)
    )


func _terrain_color(cell: Vector2i, raised: bool = false) -> Color:
    var terrain_type: int = int(map_ref.get_terrain(cell))
    var color: Color = Color("#6F8245")
    match terrain_type:
        1:
            color = Color("#81704A")
        2:
            color = Color("#315E70")
        4:
            color = Color("#565A52")
    return color.lightened(0.08) if raised else color


func _draw() -> void:
    if not is_instance_valid(map_ref) or map_ref.height_levels.is_empty():
        return
    var atlas: Texture2D = _atlas_texture()
    _draw_cliff_faces()
    _draw_height_surfaces(atlas)


func _draw_cliff_faces() -> void:
    for y in range(int(map_ref.map_height)):
        for x in range(int(map_ref.map_width)):
            var cell: Vector2i = Vector2i(x, y)
            var level: int = int(map_ref.get_height_level(cell))
            if level <= 0 or int(map_ref.get_slope_type(cell)) != SLOPE_NONE:
                continue
            var south: Vector2i = cell + Vector2i.DOWN
            var south_level: int = int(map_ref.get_height_level(south))
            if south_level < level and int(map_ref.get_slope_type(south)) == SLOPE_NONE:
                _draw_south_face(cell, level, south_level)
            var east: Vector2i = cell + Vector2i.RIGHT
            var east_level: int = int(map_ref.get_height_level(east))
            if east_level < level and int(map_ref.get_slope_type(east)) == SLOPE_NONE:
                _draw_east_edge(cell, level, east_level)


func _draw_south_face(cell: Vector2i, level: int, lower_level: int) -> void:
    var rect: Rect2 = _cell_rect(cell)
    var top_y: float = rect.end.y - float(level) * HEIGHT_STEP_PIXELS
    var bottom_y: float = rect.end.y - float(lower_level) * HEIGHT_STEP_PIXELS
    var points: PackedVector2Array = PackedVector2Array([
        Vector2(rect.position.x, top_y),
        Vector2(rect.end.x, top_y),
        Vector2(rect.end.x, bottom_y),
        Vector2(rect.position.x, bottom_y)
    ])
    draw_colored_polygon(points, Color("#57452E"))
    draw_line(points[0], points[1], Color("#B79A5E"), 1.5)
    draw_line(points[3], points[2], Color("#251D17"), 2.0)
    var band_y: float = top_y + 4.0
    var band_index: int = 0
    while band_y < bottom_y - 1.0:
        var offset: float = 3.0 if band_index % 2 == 0 else 0.0
        draw_line(
            Vector2(rect.position.x + offset, band_y),
            Vector2(rect.end.x, band_y),
            Color(0.20, 0.15, 0.10, 0.72),
            1.0
        )
        band_y += 5.0
        band_index += 1
    for crack_x in [0.22, 0.51, 0.78]:
        var px: float = lerpf(rect.position.x, rect.end.x, float(crack_x))
        draw_polyline(PackedVector2Array([
            Vector2(px, top_y + 1.0),
            Vector2(px - 2.0, lerpf(top_y, bottom_y, 0.48)),
            Vector2(px + 1.0, bottom_y - 1.0)
        ]), Color(0.14, 0.10, 0.07, 0.78), 1.0)


func _draw_east_edge(cell: Vector2i, level: int, lower_level: int) -> void:
    var rect: Rect2 = _cell_rect(cell)
    var top_y: float = rect.position.y - float(level) * HEIGHT_STEP_PIXELS
    var bottom_y: float = rect.end.y - float(lower_level) * HEIGHT_STEP_PIXELS
    var edge_x: float = rect.end.x
    var points: PackedVector2Array = PackedVector2Array([
        Vector2(edge_x - 1.0, top_y),
        Vector2(edge_x + 3.0, top_y + 3.0),
        Vector2(edge_x + 3.0, bottom_y),
        Vector2(edge_x - 1.0, bottom_y - 2.0)
    ])
    draw_colored_polygon(points, Color("#3B3023"))
    draw_line(points[0], points[3], Color("#201A15"), 1.5)


func _draw_height_surfaces(atlas: Texture2D) -> void:
    for y in range(int(map_ref.map_height)):
        for x in range(int(map_ref.map_width)):
            var cell: Vector2i = Vector2i(x, y)
            var level: int = int(map_ref.get_height_level(cell))
            var slope: int = int(map_ref.get_slope_type(cell))
            if level <= 0 and slope == SLOPE_NONE:
                continue
            if slope != SLOPE_NONE:
                _draw_ramp(cell, slope, level)
            else:
                var rect: Rect2 = _cell_rect(cell)
                rect.position.y -= float(level) * HEIGHT_STEP_PIXELS
                if atlas != null:
                    draw_texture_rect_region(atlas, rect, _terrain_region(cell), Color.WHITE)
                else:
                    draw_rect(rect, _terrain_color(cell, true))
                _draw_top_edge_marks(cell, rect, level)


func _draw_top_edge_marks(cell: Vector2i, rect: Rect2, level: int) -> void:
    var edge_light: Color = Color("#C6B26A")
    var edge_dark: Color = Color("#372B20")
    if int(map_ref.get_height_level(cell + Vector2i.UP)) < level:
        draw_line(rect.position, Vector2(rect.end.x, rect.position.y), edge_light, 1.5)
    if int(map_ref.get_height_level(cell + Vector2i.LEFT)) < level:
        draw_line(rect.position, Vector2(rect.position.x, rect.end.y), edge_light.darkened(0.18), 1.5)
    if int(map_ref.get_height_level(cell + Vector2i.DOWN)) < level:
        draw_line(Vector2(rect.position.x, rect.end.y), rect.end, edge_dark, 1.5)
    if int(map_ref.get_height_level(cell + Vector2i.RIGHT)) < level:
        draw_line(Vector2(rect.end.x, rect.position.y), rect.end, edge_dark, 1.5)


func _draw_ramp(cell: Vector2i, slope: int, base_level: int) -> void:
    var rect: Rect2 = _cell_rect(cell)
    var base_offset: float = float(base_level) * HEIGHT_STEP_PIXELS
    var top_left: Vector2 = rect.position + Vector2(0.0, -base_offset)
    var top_right: Vector2 = Vector2(rect.end.x, rect.position.y - base_offset)
    var bottom_right: Vector2 = rect.end + Vector2(0.0, -base_offset)
    var bottom_left: Vector2 = Vector2(rect.position.x, rect.end.y - base_offset)
    match slope:
        SLOPE_N:
            top_left.y -= HEIGHT_STEP_PIXELS
            top_right.y -= HEIGHT_STEP_PIXELS
        SLOPE_NE:
            top_right.y -= HEIGHT_STEP_PIXELS
            top_left.y -= HEIGHT_STEP_PIXELS * 0.5
            bottom_right.y -= HEIGHT_STEP_PIXELS * 0.5
        SLOPE_E:
            top_right.y -= HEIGHT_STEP_PIXELS
            bottom_right.y -= HEIGHT_STEP_PIXELS
        SLOPE_SE:
            bottom_right.y -= HEIGHT_STEP_PIXELS
            top_right.y -= HEIGHT_STEP_PIXELS * 0.5
            bottom_left.y -= HEIGHT_STEP_PIXELS * 0.5
        SLOPE_S:
            bottom_left.y -= HEIGHT_STEP_PIXELS
            bottom_right.y -= HEIGHT_STEP_PIXELS
        SLOPE_SW:
            bottom_left.y -= HEIGHT_STEP_PIXELS
            top_left.y -= HEIGHT_STEP_PIXELS * 0.5
            bottom_right.y -= HEIGHT_STEP_PIXELS * 0.5
        SLOPE_W:
            top_left.y -= HEIGHT_STEP_PIXELS
            bottom_left.y -= HEIGHT_STEP_PIXELS
        SLOPE_NW:
            top_left.y -= HEIGHT_STEP_PIXELS
            top_right.y -= HEIGHT_STEP_PIXELS * 0.5
            bottom_left.y -= HEIGHT_STEP_PIXELS * 0.5
    var points: PackedVector2Array = PackedVector2Array([top_left, top_right, bottom_right, bottom_left])
    draw_colored_polygon(points, _terrain_color(cell, true))
    draw_polyline(
        PackedVector2Array([top_left, top_right, bottom_right, bottom_left, top_left]),
        Color("#3C3122"),
        1.5
    )
    var direction: Vector2 = Vector2(map_ref.get_slope_direction(slope))
    var center: Vector2 = (top_left + top_right + bottom_right + bottom_left) * 0.25
    var perpendicular: Vector2 = Vector2(-direction.y, direction.x)
    for side in [-1.0, 1.0]:
        var track_center: Vector2 = center + perpendicular * 6.0 * float(side)
        draw_line(
            track_center - direction * 10.0,
            track_center + direction * 10.0,
            Color(0.24, 0.19, 0.12, 0.58),
            2.0
        )
    var arrow_tip: Vector2 = center + direction * 9.0
    draw_line(center - direction * 6.0, arrow_tip, Color("#D8C276"), 1.5)
    draw_line(arrow_tip, arrow_tip - direction * 4.0 + perpendicular * 3.0, Color("#D8C276"), 1.5)
    draw_line(arrow_tip, arrow_tip - direction * 4.0 - perpendicular * 3.0, Color("#D8C276"), 1.5)

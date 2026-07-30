extends "res://scripts/game/grid_world.gd"

const LOGICAL_CELL_WIDTH := 60.0
const LOGICAL_CELL_HEIGHT := 30.0
const DEFAULT_HEIGHT_STEP := 15.0
const CELL_RECORD_SIZE := 7
const RESOURCE_RECORD_SIZE := 8

var ra2_runtime_manifest: Dictionary = {}
var valid_cells: PackedByteArray = PackedByteArray()
var raw_terrain_types: PackedByteArray = PackedByteArray()
var raw_ramp_types: PackedByteArray = PackedByteArray()
var source_overlay_ids: PackedInt32Array = PackedInt32Array()
var source_map_width: int = 100
var source_map_height: int = 100
var height_step: float = DEFAULT_HEIGHT_STEP
var render_crop: Vector2 = Vector2.ZERO
var render_size: Vector2 = Vector2.ZERO
var map_baseline: float = 180.0
var background_sprite: Sprite2D


func generate(config):
    map_config = config
    var manifest_path: String = str(config.get("runtime_manifest", ""))
    ra2_runtime_manifest = _load_json_dictionary(manifest_path)
    if ra2_runtime_manifest.is_empty():
        push_error("RA2 runtime map manifest could not be loaded: %s" % manifest_path)
        super.generate(config)
        return

    var logical_size: Array = ra2_runtime_manifest.get("logical_size", [200, 200])
    map_width = int(logical_size[0])
    map_height = int(logical_size[1])
    var original_size: Array = ra2_runtime_manifest.get("source_size", [100, 100])
    source_map_width = int(original_size[0])
    source_map_height = int(original_size[1])
    var cell_size: Array = ra2_runtime_manifest.get("cell_size", [60, 30])
    tile_px = int(cell_size[1])
    height_step = float(ra2_runtime_manifest.get("cell_height", DEFAULT_HEIGHT_STEP))
    map_baseline = float(ra2_runtime_manifest.get("baseline", 180.0))
    render_crop = _vector2_from_array(ra2_runtime_manifest.get("render_crop", [0, 0]))
    render_size = _vector2_from_array(ra2_runtime_manifest.get("render_size", [6000, 3075]))

    var cell_count: int = map_width * map_height
    terrain.resize(cell_count)
    ore_amount.resize(cell_count)
    ore_capacity.resize(cell_count)
    overlay_types.resize(cell_count)
    overlay_frames.resize(cell_count)
    height_levels.resize(cell_count)
    slope_types.resize(cell_count)
    land_types.resize(cell_count)
    valid_cells.resize(cell_count)
    raw_terrain_types.resize(cell_count)
    raw_ramp_types.resize(cell_count)
    source_overlay_ids.resize(cell_count)

    terrain.fill(TILE_WATER)
    ore_amount.fill(0)
    ore_capacity.fill(0)
    overlay_types.fill(OVERLAY_NONE)
    overlay_frames.fill(-1)
    height_levels.fill(0)
    slope_types.fill(SLOPE_NONE)
    land_types.fill(LAND_WATER)
    valid_cells.fill(0)
    raw_terrain_types.fill(0)
    raw_ramp_types.fill(0)
    source_overlay_ids.fill(-1)
    dense_tree_cells.clear()
    sparse_tree_cells.clear()
    occupied.clear()

    _build_empty_tileset()
    _decode_cell_records()
    _decode_resource_records()
    _decode_terrain_objects()
    _build_pathfinding()
    _install_background()
    set_meta("height_pathing_active", true)
    set_meta("ra2_runtime_map", true)
    queue_redraw()


func is_ra2_runtime_map() -> bool:
    return true


func _build_empty_tileset() -> void:
    clear()
    var tiles: TileSet = TileSet.new()
    tiles.tile_size = Vector2i(tile_px, tile_px)
    tile_set = tiles


func _decode_cell_records() -> void:
    var definition: Dictionary = ra2_runtime_manifest.get("cells", {})
    var chunk_template: String = str(definition.get("chunk_template", ""))
    var chunk_count: int = int(definition.get("chunk_count", 0))
    var bytes: PackedByteArray = _decode_base64_chunks(chunk_template, chunk_count)
    var expected_records: int = int(definition.get("count", 0))
    if bytes.size() != expected_records * CELL_RECORD_SIZE:
        push_error(
            "RA2 cell cache size mismatch: expected %d bytes, got %d"
            % [expected_records * CELL_RECORD_SIZE, bytes.size()]
        )
        return
    for record_index in range(expected_records):
        var offset: int = record_index * CELL_RECORD_SIZE
        var rx: int = int(bytes.decode_u16(offset))
        var ry: int = int(bytes.decode_u16(offset + 2))
        var level: int = int(bytes[offset + 4])
        var terrain_type: int = int(bytes[offset + 5])
        var ramp_type: int = int(bytes[offset + 6])
        var cell: Vector2i = Vector2i(rx, ry)
        if not _inside(cell):
            continue
        var index: int = int(_index(cell))
        valid_cells[index] = 1
        raw_terrain_types[index] = terrain_type
        raw_ramp_types[index] = ramp_type
        height_levels[index] = level
        slope_types[index] = _runtime_slope_type(ramp_type)
        terrain[index] = _runtime_terrain_type(terrain_type)
        land_types[index] = _runtime_land_type(terrain_type)


func _decode_resource_records() -> void:
    var definition: Dictionary = ra2_runtime_manifest.get("resources", {})
    var encoded: String = str(definition.get("encoded", ""))
    var bytes: PackedByteArray = Marshalls.base64_to_raw(encoded)
    var expected_records: int = int(definition.get("count", 0))
    if bytes.size() != expected_records * RESOURCE_RECORD_SIZE:
        push_error(
            "RA2 resource cache size mismatch: expected %d bytes, got %d"
            % [expected_records * RESOURCE_RECORD_SIZE, bytes.size()]
        )
        return
    for record_index in range(expected_records):
        var offset: int = record_index * RESOURCE_RECORD_SIZE
        var rx: int = int(bytes.decode_u16(offset))
        var ry: int = int(bytes.decode_u16(offset + 2))
        var overlay_id: int = int(bytes.decode_u16(offset + 4))
        var frame: int = int(bytes[offset + 6])
        var kind: int = int(bytes[offset + 7])
        var cell: Vector2i = Vector2i(rx, ry)
        if not _inside(cell) or valid_cells[_index(cell)] == 0:
            continue
        var index: int = int(_index(cell))
        source_overlay_ids[index] = overlay_id
        overlay_types[index] = OVERLAY_GEM if kind == 2 else OVERLAY_ORE
        overlay_frames[index] = clampi(frame, 0, 11)
        ore_capacity[index] = 1800
        ore_amount[index] = maxi(150, int(round(float(frame + 1) / 12.0 * 1800.0)))


func _decode_terrain_objects() -> void:
    for raw_definition in ra2_runtime_manifest.get("trees", []):
        if not raw_definition is Dictionary:
            continue
        var definition: Dictionary = raw_definition
        var raw_cell: Variant = definition.get("cell", [])
        if not raw_cell is Array or raw_cell.size() < 2:
            continue
        var cell: Vector2i = Vector2i(int(raw_cell[0]), int(raw_cell[1]))
        if _inside(cell) and valid_cells[_index(cell)] == 1:
            sparse_tree_cells[cell] = true


func _install_background() -> void:
    var definition: Dictionary = ra2_runtime_manifest.get("background", {})
    var chunk_template: String = str(definition.get("chunk_template", ""))
    var chunk_count: int = int(definition.get("chunk_count", 0))
    var bytes: PackedByteArray = _decode_base64_chunks(chunk_template, chunk_count)
    if bytes.is_empty():
        push_error("RA2 runtime terrain background is empty")
        return
    var image: Image = Image.new()
    var result: Error = image.load_webp_from_buffer(bytes)
    if result != OK:
        push_error("RA2 runtime terrain WebP decode failed: %s" % error_string(result))
        return
    background_sprite = Sprite2D.new()
    background_sprite.name = "RA2OriginalTerrain"
    background_sprite.centered = false
    background_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    background_sprite.texture = ImageTexture.create_from_image(image)
    background_sprite.z_index = -1000
    add_child(background_sprite)


func _decode_base64_chunks(template: String, count: int) -> PackedByteArray:
    if template.is_empty() or count <= 0:
        return PackedByteArray()
    var encoded: String = ""
    for chunk_index in range(count):
        var path: String = template % chunk_index
        if not FileAccess.file_exists(path):
            push_error("Missing RA2 runtime chunk: %s" % path)
            return PackedByteArray()
        encoded += FileAccess.get_file_as_string(path).strip_edges()
    return Marshalls.base64_to_raw(encoded)


func _load_json_dictionary(path: String) -> Dictionary:
    if path.is_empty() or not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed if parsed is Dictionary else {}


func _vector2_from_array(value: Variant) -> Vector2:
    if value is Array and value.size() >= 2:
        return Vector2(float(value[0]), float(value[1]))
    return Vector2.ZERO


func _runtime_terrain_type(raw_type: int) -> int:
    if raw_type == 9:
        return TILE_WATER
    if raw_type == 15:
        return TILE_ROCK
    return TILE_GRASS


func _runtime_land_type(raw_type: int) -> int:
    if raw_type == 9:
        return LAND_WATER
    if raw_type == 15:
        return LAND_ROCK
    return LAND_CLEAR


func _runtime_slope_type(raw_type: int) -> int:
    match raw_type:
        1:
            return SLOPE_W
        2:
            return SLOPE_N
        3:
            return SLOPE_E
        4:
            return SLOPE_S
        5, 9, 15:
            return SLOPE_NW
        6, 10, 16:
            return SLOPE_NE
        7, 11, 13:
            return SLOPE_SE
        8, 12, 14:
            return SLOPE_SW
        17, 18:
            return SLOPE_NE
        19, 20:
            return SLOPE_SE
        _:
            return SLOPE_NONE


func _inside(cell) -> bool:
    if cell.x < 0 or cell.y < 0 or cell.x >= map_width or cell.y >= map_height:
        return false
    if valid_cells.is_empty():
        return true
    return valid_cells[_index(cell)] == 1


func cell_to_world(cell):
    var typed_cell: Vector2i = Vector2i(cell)
    if typed_cell.x < 0 or typed_cell.y < 0 or typed_cell.x >= map_width or typed_cell.y >= map_height:
        return Vector2.ZERO
    var level: int = int(height_levels[_index(typed_cell)])
    var x: float = (
        float(typed_cell.x - typed_cell.y + source_map_width - 1) *
        (LOGICAL_CELL_WIDTH * 0.5)
    ) + LOGICAL_CELL_WIDTH * 0.5 - render_crop.x
    var y: float = (
        float(typed_cell.x + typed_cell.y - source_map_width - 1) *
        (LOGICAL_CELL_HEIGHT * 0.5)
    ) + map_baseline - float(level) * height_step + LOGICAL_CELL_HEIGHT * 0.5 - render_crop.y
    return to_global(Vector2(x, y))


func world_to_cell(world_position):
    var local_position: Vector2 = to_local(Vector2(world_position))
    var difference: float = (
        (local_position.x + render_crop.x - LOGICAL_CELL_WIDTH * 0.5) /
        (LOGICAL_CELL_WIDTH * 0.5)
    ) - float(source_map_width - 1)
    var best_cell: Vector2i = Vector2i(-1, -1)
    var best_distance: float = INF
    var maximum_height: int = int(ra2_runtime_manifest.get("max_height", 12))
    for level in range(maximum_height + 1):
        var sum_value: float = (
            (local_position.y + render_crop.y - LOGICAL_CELL_HEIGHT * 0.5 - map_baseline) /
            (LOGICAL_CELL_HEIGHT * 0.5)
        ) + float(source_map_width + 1 + level)
        var estimated_x: int = int(round((difference + sum_value) * 0.5))
        var estimated_y: int = int(round((sum_value - difference) * 0.5))
        for offset_y in range(-1, 2):
            for offset_x in range(-1, 2):
                var candidate: Vector2i = Vector2i(estimated_x + offset_x, estimated_y + offset_y)
                if not _inside(candidate):
                    continue
                var distance: float = local_position.distance_squared_to(to_local(cell_to_world(candidate)))
                if distance < best_distance:
                    best_distance = distance
                    best_cell = candidate
    return best_cell


func get_world_bounds():
    return Rect2(Vector2.ZERO, render_size)


func find_path_for_unit(from_world, to_world, category = "vehicle"):
    if bool(get_meta("height_pathing_active", false)):
        return RuntimeHeightVisualRules.find_path_for_unit(
            self,
            Vector2(from_world),
            Vector2(to_world),
            str(category)
        )
    return _find_square_astar_path(from_world, to_world, category)


func _find_square_astar_path(from_world, to_world, category = "vehicle") -> PackedVector2Array:
    var path_grid: AStarGrid2D = _astar_for_category(category)
    var start: Vector2i = Vector2i(world_to_cell(from_world))
    var finish: Vector2i = Vector2i(world_to_cell(to_world))
    if not _inside(start):
        return PackedVector2Array()
    finish = Vector2i(nearest_walkable_cell(finish, category))
    if not _inside(finish) or path_grid.is_point_solid(finish):
        return PackedVector2Array()
    var result: PackedVector2Array = PackedVector2Array()
    for cell in path_grid.get_id_path(start, finish):
        result.append(Vector2(cell_to_world(cell)))
    return result


func nearest_walkable_cell(origin, category = "vehicle"):
    var typed_origin: Vector2i = Vector2i(origin)
    var path_grid: AStarGrid2D = _astar_for_category(category)
    if _inside(typed_origin) and not path_grid.is_point_solid(typed_origin):
        return typed_origin
    for radius in range(1, 17):
        for y in range(typed_origin.y - radius, typed_origin.y + radius + 1):
            for x in range(typed_origin.x - radius, typed_origin.x + radius + 1):
                var cell: Vector2i = Vector2i(x, y)
                if _inside(cell) and not path_grid.is_point_solid(cell):
                    return cell
    return Vector2i(-1, -1)


func footprint_center(origin, footprint):
    var typed_origin: Vector2i = Vector2i(origin)
    var typed_footprint: Vector2i = Vector2i(footprint)
    var sum: Vector2 = Vector2.ZERO
    var count: int = 0
    for y in range(maxi(1, typed_footprint.y)):
        for x in range(maxi(1, typed_footprint.x)):
            var cell: Vector2i = typed_origin + Vector2i(x, y)
            if not _inside(cell):
                continue
            sum += Vector2(cell_to_world(cell))
            count += 1
    return sum / float(count) if count > 0 else Vector2(cell_to_world(typed_origin))


func can_place(origin, footprint):
    for cell in get_footprint_cells(Vector2i(origin), Vector2i(footprint)):
        if not _inside(cell):
            return false
        var index: int = int(_index(cell))
        if terrain[index] in [TILE_WATER, TILE_ROCK]:
            return false
        if occupied.has(cell) or has_tree(cell) or has_ore(cell):
            return false
        if height_levels[index] != height_levels[_index(Vector2i(origin))]:
            return false
    return true


func get_ore_texture_asset_id(cell: Vector2i, ratio: float) -> String:
    if not _inside(cell):
        return ""
    var overlay_id: int = int(source_overlay_ids[_index(cell)])
    var stage: int = clampi(int(round(clampf(ratio, 0.0, 1.0) * 11.0)), 0, 11)
    if overlay_id >= 105 and overlay_id <= 124:
        return "tib_%02d_%02d" % [overlay_id - 104, stage]
    if overlay_id >= 28 and overlay_id <= 39:
        return "gem_%02d_%02d" % [overlay_id - 27, stage]
    return ""


func get_overlay_asset_id(cell) -> String:
    var typed_cell: Vector2i = Vector2i(cell)
    if not _inside(typed_cell):
        return ""
    var ratio: float = ore_ratio(typed_cell)
    return get_ore_texture_asset_id(typed_cell, ratio)

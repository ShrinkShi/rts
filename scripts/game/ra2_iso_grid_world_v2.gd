extends "res://scripts/game/ra2_iso_grid_world.gd"


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
        var cell: Vector2i = Vector2i(rx, ry)
        if not _inside_bounds(cell):
            continue
        var index: int = int(_index(cell))
        valid_cells[index] = 1
        var level: int = int(bytes[offset + 4])
        var terrain_type: int = int(bytes[offset + 5])
        var ramp_type: int = int(bytes[offset + 6])
        raw_terrain_types[index] = terrain_type
        raw_ramp_types[index] = ramp_type
        height_levels[index] = level
        slope_types[index] = _runtime_slope_type(ramp_type)
        terrain[index] = _runtime_terrain_type(terrain_type)
        land_types[index] = _runtime_land_type(terrain_type)


func _inside_bounds(cell: Vector2i) -> bool:
    return (
        cell.x >= 0 and cell.y >= 0 and
        cell.x < map_width and cell.y < map_height
    )


func _inside(cell) -> bool:
    var typed_cell: Vector2i = Vector2i(cell)
    if not _inside_bounds(typed_cell):
        return false
    if valid_cells.is_empty():
        return true
    return valid_cells[_index(typed_cell)] == 1


func _install_background() -> void:
    super._install_background()
    if not is_instance_valid(background_sprite):
        return
    var definition: Dictionary = ra2_runtime_manifest.get("background", {})
    var scale_value: float = maxf(0.01, float(definition.get("scale", 1.0)))
    background_sprite.scale = Vector2.ONE * scale_value

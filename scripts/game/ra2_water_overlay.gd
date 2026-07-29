extends Node2D

const RA2OriginalTextures = preload("res://scripts/ra2/ra2_original_texture_library.gd")

var map_ref


func setup(next_map) -> void:
    map_ref = next_map
    mouse_filter = Control.MOUSE_FILTER_IGNORE if self is Control else 0
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    queue_redraw()


func _draw() -> void:
    if not is_instance_valid(map_ref) or not RA2OriginalTextures.is_available():
        return
    for y in range(int(map_ref.map_height)):
        for x in range(int(map_ref.map_width)):
            var cell := Vector2i(x, y)
            if int(map_ref.get_terrain(cell)) != int(map_ref.TILE_WATER):
                continue
            _draw_water_cell(cell)


func _draw_water_cell(cell: Vector2i) -> void:
    var land_mask := 0
    if int(map_ref.get_terrain(cell + Vector2i.UP)) != int(map_ref.TILE_WATER):
        land_mask |= 1
    if int(map_ref.get_terrain(cell + Vector2i.RIGHT)) != int(map_ref.TILE_WATER):
        land_mask |= 2
    if int(map_ref.get_terrain(cell + Vector2i.DOWN)) != int(map_ref.TILE_WATER):
        land_mask |= 4
    if int(map_ref.get_terrain(cell + Vector2i.LEFT)) != int(map_ref.TILE_WATER):
        land_mask |= 8

    var asset_id := ""
    if land_mask != 0:
        asset_id = RA2OriginalTextures.shoreline_asset(land_mask)
    if asset_id.is_empty():
        var variant := posmod(cell.x * 17 + cell.y * 31 + int(map_ref.map_config.get("seed", 1)), 14) + 1
        asset_id = "water_%02d" % variant
    var texture := RA2OriginalTextures.texture(asset_id)
    if texture == null:
        return
    var center: Vector2 = map_ref.map_to_local(cell)
    # Original TMP water is a 60x30 isometric diamond. The current logical map is
    # rectangular, so the diamond is widened just enough to overlap neighbouring
    # cells while the existing water tile remains underneath as a seam-safe fill.
    var size_value := Vector2(float(map_ref.tile_px) * 1.72, float(map_ref.tile_px) * 1.02)
    draw_texture_rect(texture, Rect2(center - size_value * 0.5, size_value), false)

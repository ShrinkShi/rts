extends "res://scripts/game/grid_world_base.gd"

signal overlay_changed(cell: Vector2i, overlay_type: int, overlay_frame: int)

const OVERLAY_NONE = -1
const OVERLAY_ORE = 0
const OVERLAY_GEM = 1

const SLOPE_NONE = 0
const SLOPE_N = 1
const SLOPE_NE = 2
const SLOPE_E = 3
const SLOPE_SE = 4
const SLOPE_S = 5
const SLOPE_SW = 6
const SLOPE_W = 7
const SLOPE_NW = 8

const LAND_CLEAR = 0
const LAND_WATER = 1
const LAND_ROCK = 2

const HEIGHT_STEP_PIXELS := 16.0
const SLOPE_SPEED_MULTIPLIER := 0.78

var overlay_types = PackedInt32Array()
var overlay_frames = PackedInt32Array()
var height_levels = PackedInt32Array()
var slope_types = PackedInt32Array()
var land_types = PackedInt32Array()


func generate(config):
    var configured_size = config.get("size", [64, 48])
    var configured_width = int(configured_size[0])
    var configured_height = int(configured_size[1])
    var cell_count = configured_width * configured_height

    overlay_types.resize(cell_count)
    overlay_frames.resize(cell_count)
    height_levels.resize(cell_count)
    slope_types.resize(cell_count)
    land_types.resize(cell_count)
    overlay_types.fill(OVERLAY_NONE)
    overlay_frames.fill(-1)
    height_levels.fill(0)
    slope_types.fill(SLOPE_NONE)
    land_types.fill(LAND_CLEAR)

    # The v0.15 implementation remains the compatibility base. Virtual method
    # dispatch calls the overrides below while preserving mature pathfinding,
    # occupancy, cover and harvesting call sites.
    super.generate(config)

    _rebuild_land_types()
    _generate_height_metadata()
    _clear_spawn_height_metadata()
    queue_redraw()


func _build_tileset():
    super._build_tileset()
    texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    if tile_set == null or not tile_set.has_source(source_id):
        return
    var atlas_source: TileSetAtlasSource = tile_set.get_source(source_id) as TileSetAtlasSource
    if atlas_source == null or atlas_source.texture == null:
        return
    var repaired: Image = atlas_source.texture.get_image()
    if repaired == null or repaired.get_width() < tile_px or repaired.get_height() < tile_px:
        return

    # The bridge atlas was generated from resampled TMP diamonds. Its outermost
    # pixel rows retained black/transparent padding, which became a continuous
    # horizontal line at every 32 px TileMap boundary. Extrude each tile's inner
    # pixels into the one-pixel border so filtering and fractional camera zoom can
    # never sample black outside the useful tile content.
    var tile_count: int = mini(40, int(repaired.get_width() / tile_px))
    for tile_index in range(tile_count):
        var start_x: int = tile_index * tile_px
        for offset in range(tile_px):
            repaired.set_pixel(start_x + offset, 0, repaired.get_pixel(start_x + offset, 1))
            repaired.set_pixel(
                start_x + offset,
                tile_px - 1,
                repaired.get_pixel(start_x + offset, tile_px - 2)
            )
        for offset in range(tile_px):
            repaired.set_pixel(start_x, offset, repaired.get_pixel(start_x + 1, offset))
            repaired.set_pixel(
                start_x + tile_px - 1,
                offset,
                repaired.get_pixel(start_x + tile_px - 2, offset)
            )
    atlas_source.texture = ImageTexture.create_from_image(repaired)


func _generate_terrain():
    # Reuse the existing generator to preserve map seeds and ore placement, then
    # migrate ore out of TILE_ORE into an independent Overlay representation.
    super._generate_terrain()

    var seed_value = int(map_config.get("seed", 1))
    var noise = FastNoiseLite.new()
    noise.seed = seed_value
    noise.frequency = 0.065

    for y in range(map_height):
        for x in range(map_width):
            var cell = Vector2i(x, y)
            var idx = _index(cell)
            if ore_capacity[idx] <= 0:
                continue

            # The pre-ore base was grass/dirt. Reconstruct it with the same noise
            # parameters so the Overlay has a real floor instead of a duplicate
            # full-square ore terrain tile.
            var n = noise.get_noise_2d(x, y)
            terrain[idx] = TILE_GRASS if n > -0.22 else TILE_DIRT
            overlay_types[idx] = OVERLAY_ORE
            overlay_frames[idx] = _ore_overlay_frame(cell, 1.0)


func _clear_spawn_areas():
    super._clear_spawn_areas()
    for raw_position in map_config.get("positions", []):
        var center = Vector2i(int(raw_position[0]), int(raw_position[1]))
        for y in range(center.y - 5, center.y + 6):
            for x in range(center.x - 5, center.x + 6):
                var cell = Vector2i(x, y)
                if not _inside(cell):
                    continue
                var idx = _index(cell)
                overlay_types[idx] = OVERLAY_NONE
                overlay_frames[idx] = -1


func _generate_tree_layout():
    super._generate_tree_layout()
    # Base v0.15 excluded TILE_ORE. After migration the floor is grass/dirt, so
    # remove any tree that the base generator attempted to place on an Overlay.
    for cell in get_ore_cells(false):
        dense_tree_cells.erase(cell)
        sparse_tree_cells.erase(cell)


func harvest_ore_cell(cell, requested):
    if not _inside(cell):
        return 0
    var idx = _index(cell)
    if ore_amount[idx] <= 0:
        return 0

    var taken = min(max(0, int(requested)), ore_amount[idx])
    ore_amount[idx] -= taken
    if ore_amount[idx] <= 0:
        ore_amount[idx] = 0
        overlay_frames[idx] = -1
    else:
        overlay_frames[idx] = _ore_overlay_frame(cell, ore_ratio(cell))

    ore_changed.emit(cell, ore_amount[idx])
    overlay_changed.emit(cell, overlay_types[idx], overlay_frames[idx])
    return taken


func _ore_overlay_frame(cell: Vector2i, ratio: float) -> int:
    # TIB01..TIB20 are represented as five deterministic variants for four
    # storage bands. Exact frame semantics can be refined once source assets and
    # original map OverlayDataPack values are available.
    var density_band = clampi(
        int(ceil(clampf(ratio, 0.001, 1.0) * 4.0)),
        1,
        4
    )
    var variant = posmod(
        cell.x * 17 + cell.y * 31 + int(map_config.get("seed", 1)) * 13,
        5
    )
    return (density_band - 1) * 5 + variant


func get_overlay_type(cell) -> int:
    if not _inside(cell):
        return OVERLAY_NONE
    return int(overlay_types[_index(cell)])


func get_overlay_frame(cell) -> int:
    if not _inside(cell):
        return -1
    return int(overlay_frames[_index(cell)])


func get_overlay_asset_id(cell) -> String:
    var frame = get_overlay_frame(cell)
    if frame < 0:
        return ""
    if get_overlay_type(cell) == OVERLAY_ORE:
        return "TIB%02d" % (frame + 1)
    if get_overlay_type(cell) == OVERLAY_GEM:
        return "GEM%02d" % (frame + 1)
    return ""


func _rebuild_land_types():
    for y in range(map_height):
        for x in range(map_width):
            var cell = Vector2i(x, y)
            var tile = terrain[_index(cell)]
            land_types[_index(cell)] = _land_type_for_terrain(tile)


func _land_type_for_terrain(tile: int) -> int:
    if tile == TILE_WATER:
        return LAND_WATER
    if tile == TILE_ROCK:
        return LAND_ROCK
    return LAND_CLEAR


func _generate_height_metadata():
    for raw_zone in map_config.get("height_zones", []):
        if not raw_zone is Dictionary:
            continue
        var zone = raw_zone as Dictionary
        var raw_center = zone.get("center", [0, 0])
        if not raw_center is Array or raw_center.size() < 2:
            continue
        var center = Vector2i(int(raw_center[0]), int(raw_center[1]))
        var radius = maxf(0.0, float(zone.get("radius", 0.0)))
        var level = maxi(0, int(zone.get("level", 0)))
        var radius_int = int(ceil(radius))
        for y in range(
            maxi(0, center.y - radius_int),
            mini(map_height, center.y + radius_int + 1)
        ):
            for x in range(
                maxi(0, center.x - radius_int),
                mini(map_width, center.x + radius_int + 1)
            ):
                var cell = Vector2i(x, y)
                if Vector2(cell).distance_to(Vector2(center)) <= radius:
                    height_levels[_index(cell)] = level
        if level > 0 and bool(zone.get("auto_ramps", false)):
            _stamp_zone_ramps(zone, center, radius_int, level)

    for raw_cell in map_config.get("height_cells", []):
        if not raw_cell is Dictionary:
            continue
        var definition = raw_cell as Dictionary
        var raw_position = definition.get("cell", [-1, -1])
        if not raw_position is Array or raw_position.size() < 2:
            continue
        var cell = Vector2i(int(raw_position[0]), int(raw_position[1]))
        if not _inside(cell):
            continue
        var idx = _index(cell)
        height_levels[idx] = maxi(
            0,
            int(definition.get("level", height_levels[idx]))
        )
        slope_types[idx] = clampi(
            int(definition.get("slope", SLOPE_NONE)),
            SLOPE_NONE,
            SLOPE_NW
        )


func _stamp_zone_ramps(zone: Dictionary, center: Vector2i, radius: int, level: int) -> void:
    var ramp_names: Array = zone.get("ramps", ["north", "south"])
    var ramp_width: int = maxi(1, int(zone.get("ramp_width", 2)))
    for ramp_name_variant in ramp_names:
        var ramp_name: String = str(ramp_name_variant).to_lower()
        for offset in range(-ramp_width, ramp_width + 1):
            var cell: Vector2i = center
            var slope: int = SLOPE_NONE
            match ramp_name:
                "north":
                    cell = Vector2i(center.x + offset, center.y - radius)
                    slope = SLOPE_S
                "south":
                    cell = Vector2i(center.x + offset, center.y + radius)
                    slope = SLOPE_N
                "west":
                    cell = Vector2i(center.x - radius, center.y + offset)
                    slope = SLOPE_E
                "east":
                    cell = Vector2i(center.x + radius, center.y + offset)
                    slope = SLOPE_W
                _:
                    continue
            if not _inside(cell):
                continue
            var idx: int = int(_index(cell))
            height_levels[idx] = maxi(0, level - 1)
            slope_types[idx] = slope
            dense_tree_cells.erase(cell)
            sparse_tree_cells.erase(cell)


func _clear_spawn_height_metadata():
    for raw_position in map_config.get("positions", []):
        var center = Vector2i(int(raw_position[0]), int(raw_position[1]))
        for y in range(center.y - 5, center.y + 6):
            for x in range(center.x - 5, center.x + 6):
                var cell = Vector2i(x, y)
                if not _inside(cell):
                    continue
                var idx = _index(cell)
                height_levels[idx] = 0
                slope_types[idx] = SLOPE_NONE


func get_height_level(cell) -> int:
    if not _inside(cell):
        return 0
    return int(height_levels[_index(cell)])


func get_slope_type(cell) -> int:
    if not _inside(cell):
        return SLOPE_NONE
    return int(slope_types[_index(cell)])


func get_land_type(cell) -> int:
    if not _inside(cell):
        return LAND_WATER
    return int(land_types[_index(cell)])


func get_slope_direction(slope_type: int) -> Vector2:
    match slope_type:
        SLOPE_N:
            return Vector2.UP
        SLOPE_NE:
            return Vector2(1.0, -1.0).normalized()
        SLOPE_E:
            return Vector2.RIGHT
        SLOPE_SE:
            return Vector2(1.0, 1.0).normalized()
        SLOPE_S:
            return Vector2.DOWN
        SLOPE_SW:
            return Vector2(-1.0, 1.0).normalized()
        SLOPE_W:
            return Vector2.LEFT
        SLOPE_NW:
            return Vector2(-1.0, -1.0).normalized()
    return Vector2.ZERO


func get_ground_sample(world_position: Vector2) -> Dictionary:
    var cell: Vector2i = Vector2i(world_to_cell(world_position))
    if not _inside(cell):
        return {
            "cell": cell,
            "height": 0.0,
            "level": 0,
            "slope": SLOPE_NONE,
            "gradient": Vector2.ZERO,
        }
    var level: int = get_height_level(cell)
    var slope: int = get_slope_type(cell)
    var base_height: float = float(level) * HEIGHT_STEP_PIXELS
    var direction: Vector2 = get_slope_direction(slope)
    var slope_fraction: float = 0.0
    if slope != SLOPE_NONE:
        var center_local: Vector2 = Vector2(map_to_local(cell))
        var local_offset: Vector2 = to_local(world_position) - center_local
        var normalized: Vector2 = Vector2(
            clampf(local_offset.x / float(tile_px) + 0.5, 0.0, 1.0),
            clampf(local_offset.y / float(tile_px) + 0.5, 0.0, 1.0)
        )
        var north_amount: float = 1.0 - normalized.y
        var south_amount: float = normalized.y
        var east_amount: float = normalized.x
        var west_amount: float = 1.0 - normalized.x
        match slope:
            SLOPE_N:
                slope_fraction = north_amount
            SLOPE_NE:
                slope_fraction = (north_amount + east_amount) * 0.5
            SLOPE_E:
                slope_fraction = east_amount
            SLOPE_SE:
                slope_fraction = (south_amount + east_amount) * 0.5
            SLOPE_S:
                slope_fraction = south_amount
            SLOPE_SW:
                slope_fraction = (south_amount + west_amount) * 0.5
            SLOPE_W:
                slope_fraction = west_amount
            SLOPE_NW:
                slope_fraction = (north_amount + west_amount) * 0.5
    var gradient: Vector2 = direction * (HEIGHT_STEP_PIXELS / maxf(1.0, float(tile_px)))
    return {
        "cell": cell,
        "height": base_height + slope_fraction * HEIGHT_STEP_PIXELS,
        "level": level,
        "slope": slope,
        "gradient": gradient,
    }


func get_ground_height(world_position) -> float:
    return float(get_ground_sample(Vector2(world_position)).get("height", 0.0))


func get_ground_gradient(world_position) -> Vector2:
    return Vector2(get_ground_sample(Vector2(world_position)).get("gradient", Vector2.ZERO))


func get_movement_speed_multiplier(world_position):
    var multiplier: float = float(super.get_movement_speed_multiplier(world_position))
    if get_slope_type(world_to_cell(world_position)) != SLOPE_NONE:
        multiplier *= SLOPE_SPEED_MULTIPLIER
    return multiplier


func can_place(origin, footprint):
    if not super.can_place(origin, footprint):
        return false
    var reference_level: int = -1
    for cell in get_footprint_cells(origin, footprint):
        if get_slope_type(cell) != SLOPE_NONE:
            return false
        var level: int = get_height_level(cell)
        if reference_level < 0:
            reference_level = level
        elif level != reference_level:
            return false
    return true


func get_cell_snapshot(cell) -> Dictionary:
    if not _inside(cell):
        return {}
    return {
        "cell": cell,
        "terrain": get_terrain(cell),
        "overlay_type": get_overlay_type(cell),
        "overlay_frame": get_overlay_frame(cell),
        "overlay_asset": get_overlay_asset_id(cell),
        "level": get_height_level(cell),
        "slope": get_slope_type(cell),
        "land_type": get_land_type(cell),
        "ground_height": get_ground_height(cell_to_world(cell)),
        "ore_amount": get_ore_amount(cell),
        "ore_capacity": get_ore_capacity(cell),
    }


func _draw() -> void:
    if height_levels.is_empty():
        return
    var half_tile: float = float(tile_px) * 0.5
    var raised_tint: Color = Color(0.16, 0.12, 0.06, 0.055)
    var cliff_color: Color = Color(0.08, 0.065, 0.045, 0.70)
    var contour_color: Color = Color(0.82, 0.70, 0.42, 0.28)
    var ramp_color: Color = Color(0.92, 0.78, 0.44, 0.34)
    for y in range(map_height):
        for x in range(map_width):
            var cell: Vector2i = Vector2i(x, y)
            var level: int = get_height_level(cell)
            var slope: int = get_slope_type(cell)
            if level <= 0 and slope == SLOPE_NONE:
                continue
            var center: Vector2 = Vector2(map_to_local(cell))
            var rect: Rect2 = Rect2(center - Vector2.ONE * half_tile, Vector2.ONE * float(tile_px))
            if level > 0:
                draw_rect(rect, raised_tint)
            var east_level: int = get_height_level(cell + Vector2i.RIGHT)
            var south_level: int = get_height_level(cell + Vector2i.DOWN)
            if level > east_level:
                draw_line(
                    Vector2(rect.end.x - 1.0, rect.position.y + 1.0),
                    Vector2(rect.end.x - 1.0, rect.end.y - 1.0),
                    cliff_color,
                    3.0
                )
            if level > south_level:
                draw_line(
                    Vector2(rect.position.x + 1.0, rect.end.y - 1.0),
                    Vector2(rect.end.x - 1.0, rect.end.y - 1.0),
                    cliff_color,
                    3.0
                )
            if level > 0:
                draw_rect(rect.grow(-1.0), contour_color, false, 1.0)
            if slope != SLOPE_NONE:
                var direction: Vector2 = get_slope_direction(slope)
                draw_line(center - direction * 9.0, center + direction * 9.0, ramp_color, 2.0)
                draw_circle(center + direction * 9.0, 2.2, ramp_color)

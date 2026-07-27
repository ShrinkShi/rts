extends TileMapLayer

signal ore_changed(cell, remaining)

const TILE_GRASS = 0
const TILE_DIRT = 1
const TILE_WATER = 2
const TILE_ORE = 3
const TILE_ROCK = 4

var map_width = 64
var map_height = 48
var tile_px = 32
var terrain = PackedInt32Array()
var ore_amount = PackedInt32Array()
var ore_capacity = PackedInt32Array()
var astar = AStarGrid2D.new()
var astar_infantry = AStarGrid2D.new()
var astar_vehicle = AStarGrid2D.new()
var dense_tree_cells = {}
var sparse_tree_cells = {}
var occupied = {}
var source_id = 0
var map_config = {}

func generate(config):
    map_config = config
    map_width = int(config.get("size", [64, 48])[0])
    map_height = int(config.get("size", [64, 48])[1])
    terrain.resize(map_width * map_height)
    ore_amount.resize(map_width * map_height)
    ore_capacity.resize(map_width * map_height)
    terrain.fill(TILE_GRASS)
    ore_amount.fill(0)
    ore_capacity.fill(0)
    _build_tileset()
    _generate_terrain()
    _clear_spawn_areas()
    _generate_tree_layout()
    _rebuild_cells()
    _build_pathfinding()

func _build_tileset():
    var atlas_texture: Texture2D = null
    var atlas_path: String = "res://assets/ra2_terrain/temperate_atlas.png"
    if ResourceLoader.exists(atlas_path):
        atlas_texture = load(atlas_path) as Texture2D
    if atlas_texture == null:
        var fallback: Image = Image.create(tile_px * 40, tile_px, false, Image.FORMAT_RGBA8)
        var fallback_colors: Array[Color] = [
            Color("#526D42"), Color("#705F43"), Color("#2F6177"),
            Color("#9B8738"), Color("#4B5152"),
        ]
        for terrain_index in range(5):
            for variant in range(8):
                fallback.fill_rect(
                    Rect2i((terrain_index * 8 + variant) * tile_px, 0, tile_px, tile_px),
                    fallback_colors[terrain_index]
                )
        atlas_texture = ImageTexture.create_from_image(fallback)

    var tiles: TileSet = TileSet.new()
    tiles.tile_size = Vector2i(tile_px, tile_px)
    var atlas_source: TileSetAtlasSource = TileSetAtlasSource.new()
    atlas_source.texture = atlas_texture
    atlas_source.texture_region_size = Vector2i(tile_px, tile_px)
    for tile_index in range(40):
        atlas_source.create_tile(Vector2i(tile_index, 0))
    source_id = tiles.add_source(atlas_source)
    tile_set = tiles

func _generate_terrain():
    var seed_value = int(map_config.get("seed", 1))
    var style = str(map_config.get("style", "balanced_land"))
    var noise = FastNoiseLite.new()
    noise.seed = seed_value
    noise.frequency = 0.065
    for y in range(map_height):
        for x in range(map_width):
            var idx = _index(Vector2i(x, y))
            var n = noise.get_noise_2d(x, y)
            var tile = TILE_GRASS if n > -0.22 else TILE_DIRT
            # Skirmish maps are intentionally pure land. Campaign definitions can
            # still opt into legacy rivers/coast styles.
            if style == "rivers":
                var river_a = abs(x - int(map_width * 0.43 + sin(y * 0.18) * 2.2)) <= 1
                var river_b = abs(x - int(map_width * 0.64 + sin(y * 0.13 + 1.7) * 1.6)) <= 1
                if river_a or river_b:
                    tile = TILE_WATER
            elif style == "coast":
                var coast_x = int(map_width * 0.69 + sin(y * 0.16) * 4.5)
                if x > coast_x:
                    tile = TILE_WATER
                elif x > coast_x - 3 and n > 0.25:
                    tile = TILE_ROCK
            if _is_ore_cluster(x, y, seed_value, style) and tile != TILE_WATER and tile != TILE_ROCK:
                tile = TILE_ORE
                ore_amount[idx] = 1800
                ore_capacity[idx] = 1800
            terrain[idx] = tile

    if style == "rivers":
        for bridge_y in [9, int(map_height * 0.5), map_height - 10]:
            for x in range(map_width):
                if terrain[_index(Vector2i(x, bridge_y))] == TILE_WATER:
                    terrain[_index(Vector2i(x, bridge_y))] = TILE_DIRT

func _is_ore_cluster(x, y, seed_value, style):
    var configured = map_config.get("ore_centers", [])
    if not configured.is_empty():
        for raw_center in configured:
            var center = Vector2i(int(raw_center[0]), int(raw_center[1]))
            if Vector2(x, y).distance_to(Vector2(center)) <= 2.65:
                return true
        return false
    var center_x = int(floor(float(map_width) * 0.5))
    var center_y = int(floor(float(map_height) * 0.5))
    var centers = [
        Vector2i(center_x - 10, center_y - 7),
        Vector2i(center_x + 11, center_y + 6),
        Vector2i(center_x, center_y),
        Vector2i(13 + seed_value % 5, map_height - 13),
        Vector2i(map_width - 14, 12 + seed_value % 4)
    ]
    if style == "open":
        centers.append(Vector2i(center_x - 18, center_y + 8))
    for center in centers:
        if Vector2(x, y).distance_to(Vector2(center)) <= 3.2:
            return true
    return false

func _generate_tree_layout():
    dense_tree_cells.clear()
    sparse_tree_cells.clear()
    var density = clamp(float(map_config.get("tree_density", 0.05)), 0.0, 0.16)
    if density <= 0.0:
        return
    var rng = RandomNumberGenerator.new()
    rng.seed = int(map_config.get("seed", 1)) * 31 + 907
    var spawn_positions = []
    for raw in map_config.get("positions", []):
        spawn_positions.append(Vector2i(int(raw[0]), int(raw[1])))
    # Generate one quadrant and mirror it across both axes. This keeps dense and
    # sparse cover statistically and geometrically equal for opposite spawns.
    for y in range(2, int(ceil(map_height * 0.5))):
        for x in range(2, int(ceil(map_width * 0.5))):
            var roll = rng.randf()
            if roll >= density:
                continue
            var dense_value = roll < density * 0.46
            var mirrored = [
                Vector2i(x, y),
                Vector2i(map_width - 1 - x, y),
                Vector2i(x, map_height - 1 - y),
                Vector2i(map_width - 1 - x, map_height - 1 - y)
            ]
            for cell in mirrored:
                if not _inside(cell):
                    continue
                var idx = _index(cell)
                if terrain[idx] in [TILE_ORE, TILE_WATER, TILE_ROCK]:
                    continue
                var blocked = false
                for spawn_cell in spawn_positions:
                    if cell.distance_to(spawn_cell) < 7.5:
                        blocked = true
                        break
                if blocked:
                    continue
                if dense_value:
                    dense_tree_cells[cell] = true
                else:
                    sparse_tree_cells[cell] = true

func get_tree_cells():
    var result = []
    for cell in dense_tree_cells:
        result.append({"cell": cell, "dense": true})
    for cell in sparse_tree_cells:
        result.append({"cell": cell, "dense": false})
    return result

func has_tree(cell):
    return dense_tree_cells.has(cell) or sparse_tree_cells.has(cell)

func is_dense_tree(cell):
    return dense_tree_cells.has(cell)

func remove_tree(cell):
    dense_tree_cells.erase(cell)
    sparse_tree_cells.erase(cell)
    if _inside(cell):
        astar_vehicle.set_point_solid(cell, occupied.has(cell) or get_terrain(cell) in [TILE_WATER, TILE_ROCK])
        astar = astar_vehicle

func get_cover_multiplier(world_position, _category = "infantry"):
    var cell = world_to_cell(world_position)
    if has_tree(cell):
        return 0.75
    return 1.0

func get_movement_speed_multiplier(world_position):
    # Ore is traversable and has no collision body. It only behaves as slightly
    # rough ground while an active deposit remains on the cell.
    return 0.86 if has_ore(world_to_cell(world_position)) else 1.0

func _clear_spawn_areas():
    var positions = map_config.get("positions", [])
    for p in positions:
        var center = Vector2i(int(p[0]), int(p[1]))
        for y in range(center.y - 5, center.y + 6):
            for x in range(center.x - 5, center.x + 6):
                var cell = Vector2i(x, y)
                if _inside(cell):
                    terrain[_index(cell)] = TILE_GRASS if (x + y) % 4 else TILE_DIRT
                    ore_amount[_index(cell)] = 0
                    ore_capacity[_index(cell)] = 0

func _rebuild_cells():
    clear()
    var seed_value: int = int(map_config.get("seed", 1))
    for y in range(map_height):
        for x in range(map_width):
            var cell: Vector2i = Vector2i(x, y)
            var terrain_type: int = int(terrain[_index(cell)])
            var variant: int = posmod(x * 17 + y * 31 + seed_value * 13, 8)
            set_cell(cell, source_id, Vector2i(terrain_type * 8 + variant, 0), 0)

func _new_astar_grid():
    var grid = AStarGrid2D.new()
    grid.region = Rect2i(0, 0, map_width, map_height)
    grid.cell_size = Vector2(tile_px, tile_px)
    grid.offset = Vector2(tile_px * 0.5, tile_px * 0.5)
    grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
    grid.update()
    return grid

func _build_pathfinding():
    astar_infantry = _new_astar_grid()
    astar_vehicle = _new_astar_grid()
    for y in range(map_height):
        for x in range(map_width):
            var cell = Vector2i(x, y)
            var tile = terrain[_index(cell)]
            var terrain_solid = tile == TILE_WATER or tile == TILE_ROCK
            astar_infantry.set_point_solid(cell, terrain_solid)
            astar_vehicle.set_point_solid(cell, terrain_solid or dense_tree_cells.has(cell))
    astar = astar_vehicle

func _astar_for_category(category):
    return astar_infantry if str(category) == "infantry" else astar_vehicle

func find_path(from_world, to_world):
    return find_path_for_unit(from_world, to_world, "vehicle")

func find_path_for_unit(from_world, to_world, category = "vehicle"):
    var path_grid = _astar_for_category(category)
    var start = world_to_cell(from_world)
    var finish = world_to_cell(to_world)
    if not _inside(start):
        return PackedVector2Array()
    finish = nearest_walkable_cell(finish, category)
    if not _inside(finish) or path_grid.is_point_solid(finish):
        return PackedVector2Array()
    return path_grid.get_point_path(start, finish)

func is_cell_walkable(cell, category = "vehicle"):
    return _inside(cell) and not _astar_for_category(category).is_point_solid(cell)

func nearest_walkable_cell(origin, category = "vehicle"):
    var path_grid = _astar_for_category(category)
    if _inside(origin) and not path_grid.is_point_solid(origin):
        return origin
    for radius in range(1, 9):
        for y in range(origin.y - radius, origin.y + radius + 1):
            for x in range(origin.x - radius, origin.x + radius + 1):
                var cell = Vector2i(x, y)
                if _inside(cell) and not path_grid.is_point_solid(cell):
                    return cell
    return Vector2i(-1, -1)

func world_to_cell(world_position):
    return local_to_map(to_local(world_position))

func cell_to_world(cell):
    return to_global(map_to_local(cell))

func get_world_bounds():
    return Rect2(Vector2.ZERO, Vector2(map_width * tile_px, map_height * tile_px))

func get_terrain(cell):
    if not _inside(cell):
        return TILE_WATER
    return terrain[_index(cell)]

func can_place(origin, footprint):
    var cells = get_footprint_cells(origin, footprint)
    for cell in cells:
        if not _inside(cell):
            return false
        var tile = terrain[_index(cell)]
        if tile == TILE_WATER or tile == TILE_ROCK or occupied.has(cell) or has_tree(cell) or has_ore(cell):
            return false
    return true

func occupy(origin, footprint, entity):
    for cell in get_footprint_cells(origin, footprint):
        occupied[cell] = entity
        if _inside(cell):
            astar_infantry.set_point_solid(cell, true)
            astar_vehicle.set_point_solid(cell, true)
            astar = astar_vehicle

func vacate(entity):
    var to_remove = []
    for cell in occupied:
        if occupied[cell] == entity:
            to_remove.append(cell)
    for cell in to_remove:
        occupied.erase(cell)
        if _inside(cell):
            var tile = terrain[_index(cell)]
            var terrain_solid = tile == TILE_WATER or tile == TILE_ROCK
            astar_infantry.set_point_solid(cell, terrain_solid)
            astar_vehicle.set_point_solid(cell, terrain_solid or dense_tree_cells.has(cell))
            astar = astar_vehicle

func get_footprint_cells(origin, footprint):
    var cells = []
    for y in range(int(footprint.y)):
        for x in range(int(footprint.x)):
            cells.append(origin + Vector2i(x, y))
    return cells

func footprint_center(origin, footprint):
    var first = cell_to_world(origin)
    return first + Vector2((footprint.x - 1) * tile_px * 0.5, (footprint.y - 1) * tile_px * 0.5)

func harvest_ore_at(world_position, requested):
    return harvest_ore_cell(world_to_cell(world_position), requested)

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
        terrain[idx] = TILE_DIRT
        set_cell(cell, source_id, Vector2i(TILE_DIRT, 0), 0)
    ore_changed.emit(cell, ore_amount[idx])
    return taken

func get_ore_cells(include_depleted = false):
    var result = []
    for y in range(map_height):
        for x in range(map_width):
            var cell = Vector2i(x, y)
            var idx = _index(cell)
            if ore_capacity[idx] > 0 and (include_depleted or ore_amount[idx] > 0):
                result.append(cell)
    return result

func get_ore_amount(cell):
    if not _inside(cell):
        return 0
    return int(ore_amount[_index(cell)])

func get_ore_capacity(cell):
    if not _inside(cell):
        return 0
    return int(ore_capacity[_index(cell)])

func has_ore(cell):
    return get_ore_amount(cell) > 0

func nearest_ore_cell(from_world):
    var origin = world_to_cell(from_world)
    var best_distance = INF
    var best = Vector2i(-1, -1)
    for cell in get_ore_cells(false):
        var distance = origin.distance_squared_to(cell)
        if distance < best_distance:
            best_distance = distance
            best = cell
    return best

func nearest_ore_world(from_world):
    var cell = nearest_ore_cell(from_world)
    return cell_to_world(cell) if cell.x >= 0 else Vector2.ZERO

func ore_ratio(cell):
    if not _inside(cell):
        return 0.0
    var capacity = max(1, get_ore_capacity(cell))
    return clamp(float(get_ore_amount(cell)) / float(capacity), 0.0, 1.0)

func _inside(cell):
    return cell.x >= 0 and cell.y >= 0 and cell.x < map_width and cell.y < map_height

func _index(cell):
    return cell.y * map_width + cell.x

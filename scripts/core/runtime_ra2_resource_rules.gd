extends Node

const MATCH_SCRIPT_PATH := "res://scripts/game/rts_match.gd"
const RA2WaterOverlay = preload("res://scripts/game/ra2_water_overlay.gd")
const OrePillarEntity = preload("res://scripts/game/ore_pillar_entity.gd")
const OreEntity = preload("res://scripts/game/ore_entity.gd")

const DEFAULT_ORE_CAPACITY := 1800
const ORE_GROWTH_PER_PULSE := 150

var _matches: Array = []
var _initialized_matches: Dictionary = {}
var _pillar_cells: Dictionary = {}


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_PAUSABLE
    process_priority = 115
    _register_existing(get_tree().root)
    get_tree().node_added.connect(_on_node_added)


func _register_existing(node: Node) -> void:
    _register_node(node)
    for child in node.get_children():
        _register_existing(child)


func _on_node_added(node: Node) -> void:
    call_deferred("_register_node", node)


func _register_node(node: Node) -> void:
    if not is_instance_valid(node):
        return
    var script := node.get_script() as Script
    if script != null and script.resource_path == MATCH_SCRIPT_PATH and not node in _matches:
        _matches.append(node)


func _process(_delta: float) -> void:
    _matches = _matches.filter(func(value): return is_instance_valid(value))
    for match_ref in _matches:
        var key := int(match_ref.get_instance_id())
        if _initialized_matches.has(key):
            continue
        if not is_instance_valid(match_ref.grid) or not is_instance_valid(match_ref.entity_layer):
            continue
        _install_match_resources(match_ref)
        _initialized_matches[key] = true


func _install_match_resources(match_ref) -> void:
    if not is_instance_valid(match_ref.grid.get_node_or_null("RA2OriginalWaterOverlay")):
        var water_overlay: Node2D = RA2WaterOverlay.new()
        water_overlay.name = "RA2OriginalWaterOverlay"
        match_ref.grid.add_child(water_overlay)
        water_overlay.setup(match_ref.grid)
    _spawn_ore_pillars(match_ref)


func _spawn_ore_pillars(match_ref) -> void:
    var raw_centers: Variant = match_ref.grid.map_config.get("ore_centers", [])
    if not raw_centers is Array or raw_centers.is_empty():
        return
    var requested_count := clampi(
        int(match_ref.grid.map_config.get("ore_pillar_count", maxi(1, raw_centers.size() / 5))),
        1,
        4
    )
    var stride := maxf(1.0, float(raw_centers.size()) / float(requested_count))
    var match_key := int(match_ref.get_instance_id())
    var cells: Dictionary = {}
    _pillar_cells[match_key] = cells
    for pillar_index in range(requested_count):
        var source_index := mini(raw_centers.size() - 1, int(floor(float(pillar_index) * stride + stride * 0.5)))
        var raw_center: Variant = raw_centers[source_index]
        if not raw_center is Array or raw_center.size() < 2:
            continue
        var center := Vector2i(int(raw_center[0]), int(raw_center[1]))
        var pillar_cell := _find_pillar_cell(match_ref, center, cells)
        if pillar_cell.x < 0:
            continue
        cells[pillar_cell] = true
        _clear_ore_for_pillar(match_ref, pillar_cell)
        var pillar: Node2D = OrePillarEntity.new()
        match_ref.entity_layer.add_child(pillar)
        pillar.setup(match_ref, match_ref.grid, pillar_cell)
        match_ref.grid.astar_infantry.set_point_solid(pillar_cell, true)
        match_ref.grid.astar_vehicle.set_point_solid(pillar_cell, true)


func _find_pillar_cell(match_ref, center: Vector2i, existing: Dictionary) -> Vector2i:
    for radius in range(0, 4):
        for y in range(center.y - radius, center.y + radius + 1):
            for x in range(center.x - radius, center.x + radius + 1):
                var cell := Vector2i(x, y)
                if not match_ref.grid._inside(cell) or existing.has(cell):
                    continue
                var terrain_type := int(match_ref.grid.get_terrain(cell))
                if terrain_type in [int(match_ref.grid.TILE_WATER), int(match_ref.grid.TILE_ROCK)]:
                    continue
                if match_ref.grid.has_tree(cell) or match_ref.grid.occupied.has(cell):
                    continue
                return cell
    return Vector2i(-1, -1)


func _clear_ore_for_pillar(match_ref, cell: Vector2i) -> void:
    var index := int(match_ref.grid._index(cell))
    match_ref.grid.ore_amount[index] = 0
    match_ref.grid.ore_capacity[index] = 0
    match_ref.grid.terrain[index] = int(match_ref.grid.TILE_DIRT)
    _refresh_grid_cell(match_ref.grid, cell)
    for ore in match_ref.ore_entities.duplicate():
        if is_instance_valid(ore) and Vector2i(ore.cell) == cell:
            match_ref.ore_entities.erase(ore)
            ore.queue_free()


func spread_ore(match_ref, origin: Vector2i) -> bool:
    if not is_instance_valid(match_ref) or not is_instance_valid(match_ref.grid):
        return false
    var match_key := int(match_ref.get_instance_id())
    var pillar_cells: Dictionary = _pillar_cells.get(match_key, {})
    var candidates: Array[Vector2i] = []
    for radius in range(1, 4):
        for y in range(origin.y - radius, origin.y + radius + 1):
            for x in range(origin.x - radius, origin.x + radius + 1):
                var cell := Vector2i(x, y)
                if maxi(absi(x - origin.x), absi(y - origin.y)) != radius:
                    continue
                if _can_grow_ore(match_ref, origin, cell, pillar_cells):
                    candidates.append(cell)
        if not candidates.is_empty():
            break
    if candidates.is_empty():
        return false
    var pick_index := posmod(int(Time.get_ticks_msec() / 1000) + origin.x * 17 + origin.y * 31, candidates.size())
    var target := candidates[pick_index]
    var index := int(match_ref.grid._index(target))
    if int(match_ref.grid.ore_capacity[index]) <= 0:
        match_ref.grid.ore_capacity[index] = DEFAULT_ORE_CAPACITY
    match_ref.grid.ore_amount[index] = mini(
        int(match_ref.grid.ore_capacity[index]),
        int(match_ref.grid.ore_amount[index]) + ORE_GROWTH_PER_PULSE
    )
    match_ref.grid.terrain[index] = int(match_ref.grid.TILE_ORE)
    _refresh_grid_cell(match_ref.grid, target)
    match_ref.grid.ore_changed.emit(target, int(match_ref.grid.ore_amount[index]))
    _ensure_ore_entity(match_ref, target)
    return true


func _can_grow_ore(match_ref, origin: Vector2i, cell: Vector2i, pillar_cells: Dictionary) -> bool:
    if not match_ref.grid._inside(cell) or pillar_cells.has(cell):
        return false
    var terrain_type := int(match_ref.grid.get_terrain(cell))
    if terrain_type in [int(match_ref.grid.TILE_WATER), int(match_ref.grid.TILE_ROCK)]:
        return false
    if match_ref.grid.has_tree(cell) or match_ref.grid.occupied.has(cell):
        return false
    if match_ref.grid.has_method("get_height_level"):
        if int(match_ref.grid.get_height_level(cell)) != int(match_ref.grid.get_height_level(origin)):
            return false
    return int(match_ref.grid.get_ore_amount(cell)) < DEFAULT_ORE_CAPACITY


func _ensure_ore_entity(match_ref, cell: Vector2i) -> void:
    for ore in match_ref.ore_entities:
        if is_instance_valid(ore) and Vector2i(ore.cell) == cell:
            return
    var ore: Node2D = OreEntity.new()
    match_ref.entity_layer.add_child(ore)
    ore.setup(match_ref, match_ref.grid, cell)
    match_ref.ore_entities.append(ore)


func _refresh_grid_cell(grid, cell: Vector2i) -> void:
    var terrain_type := int(grid.get_terrain(cell))
    var seed_value := int(grid.map_config.get("seed", 1))
    var variant := posmod(cell.x * 17 + cell.y * 31 + seed_value * 13, 8)
    grid.set_cell(cell, grid.source_id, Vector2i(terrain_type * 8 + variant, 0), 0)

extends Node

const GRID_SCRIPT_PATH := "res://scripts/game/grid_world.gd"
const HeightTerrainOverlay = preload("res://scripts/game/height_terrain_overlay.gd")

const PATH_NEIGHBORS: Array[Vector2i] = [
    Vector2i.UP,
    Vector2i(1, -1),
    Vector2i.RIGHT,
    Vector2i(1, 1),
    Vector2i.DOWN,
    Vector2i(-1, 1),
    Vector2i.LEFT,
    Vector2i(-1, -1),
]
const DIAGONAL_COST := 1.41421356
const MAX_PATH_SEARCH_FACTOR := 8

var _maps: Array = []


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_PAUSABLE
    process_priority = 110
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
    var script: Script = node.get_script() as Script
    if script != null and script.resource_path == GRID_SCRIPT_PATH and not node in _maps:
        _maps.append(node)


func _process(_delta: float) -> void:
    _maps = _maps.filter(func(value): return is_instance_valid(value))
    for map_ref in _maps:
        if not bool(map_ref.get_meta("dev7_height_visual_ready", false)):
            _try_finalize_map(map_ref)


func _try_finalize_map(map_ref) -> void:
    var expected: int = int(map_ref.map_width) * int(map_ref.map_height)
    if expected <= 0 or int(map_ref.height_levels.size()) != expected:
        return
    _apply_rect_height_zones(map_ref)
    _install_overlay(map_ref)
    _enforce_cliff_constraints(map_ref)
    map_ref.set_meta("dev7_height_visual_ready", true)
    map_ref.queue_redraw()


func _apply_rect_height_zones(map_ref) -> void:
    var zones: Variant = map_ref.map_config.get("height_rects", [])
    var has_zones: bool = zones is Array and not zones.is_empty()
    map_ref.set_meta("height_pathing_active", has_zones)
    if not has_zones:
        return
    map_ref.height_levels.fill(0)
    map_ref.slope_types.fill(0)
    for zone_variant in zones:
        if not zone_variant is Dictionary:
            continue
        var zone: Dictionary = zone_variant
        var raw_origin: Variant = zone.get("origin", [0, 0])
        var raw_size: Variant = zone.get("size", [1, 1])
        if not raw_origin is Array or not raw_size is Array:
            continue
        if raw_origin.size() < 2 or raw_size.size() < 2:
            continue
        var origin: Vector2i = Vector2i(int(raw_origin[0]), int(raw_origin[1]))
        var size: Vector2i = Vector2i(maxi(1, int(raw_size[0])), maxi(1, int(raw_size[1])))
        var level: int = maxi(1, int(zone.get("level", 1)))
        for y in range(origin.y, origin.y + size.y):
            for x in range(origin.x, origin.x + size.x):
                var cell: Vector2i = Vector2i(x, y)
                if not map_ref._inside(cell):
                    continue
                var index: int = int(map_ref._index(cell))
                map_ref.height_levels[index] = level
                map_ref.dense_tree_cells.erase(cell)
                map_ref.sparse_tree_cells.erase(cell)
        _stamp_rect_ramps(map_ref, zone, origin, size, level)


func _stamp_rect_ramps(map_ref, zone: Dictionary, origin: Vector2i, size: Vector2i, level: int) -> void:
    var ramp_names: Array = zone.get("ramps", ["north", "south"])
    var ramp_width: int = maxi(1, int(zone.get("ramp_width", 2)))
    var center_x: int = origin.x + int(floor(float(size.x - 1) * 0.5))
    var center_y: int = origin.y + int(floor(float(size.y - 1) * 0.5))
    for ramp_variant in ramp_names:
        var ramp_name: String = str(ramp_variant).to_lower()
        for offset in range(-ramp_width, ramp_width + 1):
            var cell: Vector2i = Vector2i.ZERO
            var slope: int = 0
            match ramp_name:
                "north":
                    cell = Vector2i(center_x + offset, origin.y)
                    slope = 5
                "south":
                    cell = Vector2i(center_x + offset, origin.y + size.y - 1)
                    slope = 1
                "west":
                    cell = Vector2i(origin.x, center_y + offset)
                    slope = 3
                "east":
                    cell = Vector2i(origin.x + size.x - 1, center_y + offset)
                    slope = 7
                _:
                    continue
            if not map_ref._inside(cell):
                continue
            var index: int = int(map_ref._index(cell))
            map_ref.height_levels[index] = maxi(0, level - 1)
            map_ref.slope_types[index] = slope
            map_ref.dense_tree_cells.erase(cell)
            map_ref.sparse_tree_cells.erase(cell)


func _install_overlay(map_ref) -> void:
    if is_instance_valid(map_ref.get_node_or_null("RA2HeightTerrainOverlay")):
        return
    var overlay: Node2D = HeightTerrainOverlay.new()
    map_ref.add_child(overlay)
    overlay.setup(map_ref)


func _enforce_cliff_constraints(map_ref) -> void:
    if not is_instance_valid(map_ref.astar_infantry) or not is_instance_valid(map_ref.astar_vehicle):
        return

    # dev.7 originally made every upper cliff-edge cell solid. A vehicle that was
    # already standing on one of those cells then had a solid A* start node and
    # could never receive a path away from the cliff. Restore those cells to their
    # real terrain/occupancy state before switching to edge-based constraints.
    _restore_legacy_cliff_solids(map_ref)

    var cliff_edges: Dictionary = {}
    for y in range(int(map_ref.map_height)):
        for x in range(int(map_ref.map_width)):
            var cell: Vector2i = Vector2i(x, y)
            for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
                var neighbor: Vector2i = cell + direction
                if not map_ref._inside(neighbor):
                    continue
                if is_height_transition_allowed(map_ref, cell, neighbor):
                    continue
                var forward_key: String = _edge_key(cell, neighbor)
                var reverse_key: String = _edge_key(neighbor, cell)
                cliff_edges[forward_key] = true
                cliff_edges[reverse_key] = true

    map_ref.set_meta("height_cliff_cells", {})
    map_ref.set_meta("height_cliff_edges", cliff_edges)
    map_ref.set_meta("height_pathing_active", not cliff_edges.is_empty())
    map_ref.astar = map_ref.astar_vehicle


func _restore_legacy_cliff_solids(map_ref) -> void:
    var previous_variant: Variant = map_ref.get_meta("height_cliff_cells", {})
    if not previous_variant is Dictionary:
        return
    var previous: Dictionary = previous_variant
    for cell_variant in previous.keys():
        var cell: Vector2i = Vector2i(cell_variant)
        if not map_ref._inside(cell):
            continue
        var terrain_solid: bool = int(map_ref.get_land_type(cell)) != 0
        var occupied_solid: bool = map_ref.occupied.has(cell)
        map_ref.astar_infantry.set_point_solid(cell, terrain_solid or occupied_solid)
        map_ref.astar_vehicle.set_point_solid(
            cell,
            terrain_solid or occupied_solid or map_ref.dense_tree_cells.has(cell)
        )


func is_height_pathing_active(map_ref) -> bool:
    return is_instance_valid(map_ref) and bool(map_ref.get_meta("height_pathing_active", false))


func find_path_for_unit(
    map_ref,
    from_world: Vector2,
    to_world: Vector2,
    category: String = "vehicle"
) -> PackedVector2Array:
    if not is_instance_valid(map_ref):
        return PackedVector2Array()
    if not is_height_pathing_active(map_ref):
        return map_ref.find_path_for_unit(from_world, to_world, category)

    var start: Vector2i = Vector2i(map_ref.world_to_cell(from_world))
    var finish: Vector2i = Vector2i(map_ref.world_to_cell(to_world))
    if not map_ref._inside(start):
        return PackedVector2Array()
    finish = Vector2i(map_ref.nearest_walkable_cell(finish, category))
    if not map_ref._inside(finish):
        return PackedVector2Array()

    var path_grid: AStarGrid2D = map_ref.astar_vehicle
    if category == "infantry":
        path_grid = map_ref.astar_infantry
    if path_grid.is_point_solid(finish):
        return PackedVector2Array()

    return _find_edge_aware_path(map_ref, path_grid, start, finish)


func _find_edge_aware_path(
    map_ref,
    path_grid: AStarGrid2D,
    start: Vector2i,
    finish: Vector2i
) -> PackedVector2Array:
    var node_count: int = int(map_ref.map_width) * int(map_ref.map_height)
    var start_id: int = _cell_id(map_ref, start)
    var finish_id: int = _cell_id(map_ref, finish)

    var g_score: PackedFloat32Array = PackedFloat32Array()
    g_score.resize(node_count)
    g_score.fill(1.0e20)
    var came_from: PackedInt32Array = PackedInt32Array()
    came_from.resize(node_count)
    came_from.fill(-1)
    var closed: PackedByteArray = PackedByteArray()
    closed.resize(node_count)
    closed.fill(0)

    var heap_ids: Array[int] = []
    var heap_scores: Array[float] = []
    g_score[start_id] = 0.0
    _heap_push(heap_ids, heap_scores, start_id, _path_heuristic(start, finish))

    var found: bool = false
    var iterations: int = 0
    var iteration_limit: int = maxi(node_count, node_count * MAX_PATH_SEARCH_FACTOR)
    while not heap_ids.is_empty() and iterations < iteration_limit:
        iterations += 1
        var current_id: int = _heap_pop(heap_ids, heap_scores)
        if current_id < 0 or current_id >= node_count:
            continue
        if closed[current_id] != 0:
            continue
        if current_id == finish_id:
            found = true
            break
        closed[current_id] = 1
        var current: Vector2i = _cell_from_id(map_ref, current_id)
        for direction in PATH_NEIGHBORS:
            var neighbor: Vector2i = current + direction
            if not _path_step_allowed(map_ref, path_grid, current, neighbor):
                continue
            var neighbor_id: int = _cell_id(map_ref, neighbor)
            if closed[neighbor_id] != 0:
                continue
            var step_cost: float = DIAGONAL_COST if direction.x != 0 and direction.y != 0 else 1.0
            if int(map_ref.get_slope_type(current)) != 0 or int(map_ref.get_slope_type(neighbor)) != 0:
                step_cost *= 1.08
            var tentative: float = float(g_score[current_id]) + step_cost
            if tentative >= float(g_score[neighbor_id]):
                continue
            came_from[neighbor_id] = current_id
            g_score[neighbor_id] = tentative
            _heap_push(
                heap_ids,
                heap_scores,
                neighbor_id,
                tentative + _path_heuristic(neighbor, finish)
            )

    if not found:
        return PackedVector2Array()
    return _reconstruct_world_path(map_ref, came_from, start_id, finish_id)


func _path_step_allowed(
    map_ref,
    path_grid: AStarGrid2D,
    from_cell: Vector2i,
    to_cell: Vector2i
) -> bool:
    if not map_ref._inside(to_cell) or path_grid.is_point_solid(to_cell):
        return false
    if not is_height_transition_allowed(map_ref, from_cell, to_cell):
        return false

    var delta: Vector2i = to_cell - from_cell
    if delta.x == 0 or delta.y == 0:
        return true

    # Do not cut diagonally through a blocked cliff corner. Both cardinal routes
    # around the corner must be legal, matching AStarGrid2D's obstacle behaviour.
    var side_x: Vector2i = from_cell + Vector2i(delta.x, 0)
    var side_y: Vector2i = from_cell + Vector2i(0, delta.y)
    if not map_ref._inside(side_x) or not map_ref._inside(side_y):
        return false
    if path_grid.is_point_solid(side_x) or path_grid.is_point_solid(side_y):
        return false
    if not is_height_transition_allowed(map_ref, from_cell, side_x):
        return false
    if not is_height_transition_allowed(map_ref, from_cell, side_y):
        return false
    if not is_height_transition_allowed(map_ref, side_x, to_cell):
        return false
    if not is_height_transition_allowed(map_ref, side_y, to_cell):
        return false
    return true


func is_height_transition_allowed(map_ref, from_cell: Vector2i, to_cell: Vector2i) -> bool:
    if not is_instance_valid(map_ref) or not map_ref._inside(from_cell) or not map_ref._inside(to_cell):
        return false
    var from_level: int = int(map_ref.get_height_level(from_cell))
    var to_level: int = int(map_ref.get_height_level(to_cell))
    if from_level == to_level:
        return true
    if absi(to_level - from_level) > 1:
        return false

    var movement: Vector2 = Vector2(to_cell - from_cell).normalized()
    var from_slope: int = int(map_ref.get_slope_type(from_cell))
    if from_slope != 0:
        var from_direction: Vector2 = Vector2(map_ref.get_slope_direction(from_slope))
        if to_level > from_level and movement.dot(from_direction) > 0.45:
            return true
        if to_level < from_level and movement.dot(from_direction) < -0.45:
            return true

    var to_slope: int = int(map_ref.get_slope_type(to_cell))
    if to_slope != 0:
        var to_direction: Vector2 = Vector2(map_ref.get_slope_direction(to_slope))
        if to_level > from_level and movement.dot(to_direction) > 0.45:
            return true
        if to_level < from_level and movement.dot(to_direction) < -0.45:
            return true
    return false


func is_world_transition_walkable(
    map_ref,
    from_world: Vector2,
    to_world: Vector2,
    category: String = "vehicle"
) -> bool:
    if not is_instance_valid(map_ref):
        return false
    var from_cell: Vector2i = Vector2i(map_ref.world_to_cell(from_world))
    var to_cell: Vector2i = Vector2i(map_ref.world_to_cell(to_world))
    if from_cell == to_cell:
        return true

    var path_grid: AStarGrid2D = map_ref.astar_vehicle
    if category == "infantry":
        path_grid = map_ref.astar_infantry
    var delta: Vector2i = to_cell - from_cell
    var steps: int = maxi(absi(delta.x), absi(delta.y))
    var previous: Vector2i = from_cell
    for step_index in range(1, steps + 1):
        var progress: float = float(step_index) / float(steps)
        var next_cell: Vector2i = Vector2i(
            int(round(lerpf(float(from_cell.x), float(to_cell.x), progress))),
            int(round(lerpf(float(from_cell.y), float(to_cell.y), progress)))
        )
        if next_cell == previous:
            continue
        if not _path_step_allowed(map_ref, path_grid, previous, next_cell):
            return false
        previous = next_cell
    return true


func _reconstruct_world_path(
    map_ref,
    came_from: PackedInt32Array,
    start_id: int,
    finish_id: int
) -> PackedVector2Array:
    var reversed_ids: Array[int] = []
    var current_id: int = finish_id
    while current_id >= 0:
        reversed_ids.append(current_id)
        if current_id == start_id:
            break
        current_id = int(came_from[current_id])
    if reversed_ids.is_empty() or reversed_ids[-1] != start_id:
        return PackedVector2Array()
    reversed_ids.reverse()

    var result: PackedVector2Array = PackedVector2Array()
    for node_id in reversed_ids:
        result.append(Vector2(map_ref.cell_to_world(_cell_from_id(map_ref, node_id))))
    return result


func _path_heuristic(from_cell: Vector2i, to_cell: Vector2i) -> float:
    var dx: float = float(absi(from_cell.x - to_cell.x))
    var dy: float = float(absi(from_cell.y - to_cell.y))
    var diagonal: float = minf(dx, dy)
    return maxf(dx, dy) + (DIAGONAL_COST - 1.0) * diagonal


func _cell_id(map_ref, cell: Vector2i) -> int:
    return cell.y * int(map_ref.map_width) + cell.x


func _cell_from_id(map_ref, node_id: int) -> Vector2i:
    var width: int = int(map_ref.map_width)
    return Vector2i(node_id % width, int(node_id / width))


func _edge_key(from_cell: Vector2i, to_cell: Vector2i) -> String:
    return "%d,%d>%d,%d" % [from_cell.x, from_cell.y, to_cell.x, to_cell.y]


func _heap_push(
    heap_ids: Array[int],
    heap_scores: Array[float],
    node_id: int,
    score: float
) -> void:
    heap_ids.append(node_id)
    heap_scores.append(score)
    var index: int = heap_ids.size() - 1
    while index > 0:
        var parent: int = int((index - 1) / 2)
        if heap_scores[parent] <= heap_scores[index]:
            break
        var parent_id: int = heap_ids[parent]
        var parent_score: float = heap_scores[parent]
        heap_ids[parent] = heap_ids[index]
        heap_scores[parent] = heap_scores[index]
        heap_ids[index] = parent_id
        heap_scores[index] = parent_score
        index = parent


func _heap_pop(heap_ids: Array[int], heap_scores: Array[float]) -> int:
    if heap_ids.is_empty():
        return -1
    var root_id: int = heap_ids[0]
    var last_id: int = heap_ids.pop_back()
    var last_score: float = heap_scores.pop_back()
    if heap_ids.is_empty():
        return root_id
    heap_ids[0] = last_id
    heap_scores[0] = last_score

    var index: int = 0
    while true:
        var left: int = index * 2 + 1
        var right: int = left + 1
        var smallest: int = index
        if left < heap_ids.size() and heap_scores[left] < heap_scores[smallest]:
            smallest = left
        if right < heap_ids.size() and heap_scores[right] < heap_scores[smallest]:
            smallest = right
        if smallest == index:
            break
        var swap_id: int = heap_ids[smallest]
        var swap_score: float = heap_scores[smallest]
        heap_ids[smallest] = heap_ids[index]
        heap_scores[smallest] = heap_scores[index]
        heap_ids[index] = swap_id
        heap_scores[index] = swap_score
        index = smallest
    return root_id

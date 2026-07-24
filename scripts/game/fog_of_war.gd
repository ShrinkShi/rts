extends Node2D

var match_ref
var map_ref
var enabled = true
var visible_cells = PackedByteArray()
var discovered_cells = PackedByteArray()
var update_timer = 0.0

func setup(next_match, next_map, is_enabled):
    match_ref = next_match
    map_ref = next_map
    enabled = is_enabled
    visible_cells.resize(map_ref.map_width * map_ref.map_height)
    discovered_cells.resize(map_ref.map_width * map_ref.map_height)
    z_index = 90
    queue_redraw()

func _process(delta):
    if not enabled:
        return
    update_timer -= delta
    if update_timer <= 0.0:
        update_timer = 0.18
        _recalculate()

func _recalculate():
    visible_cells.fill(0)
    for entity in match_ref.get_owned_entities(0):
        if not is_instance_valid(entity):
            continue
        var center = map_ref.world_to_cell(entity.global_position)
        var radius = entity.get_sight_radius_cells()
        for y in range(center.y - radius, center.y + radius + 1):
            for x in range(center.x - radius, center.x + radius + 1):
                if x < 0 or y < 0 or x >= map_ref.map_width or y >= map_ref.map_height:
                    continue
                var cell = Vector2i(x, y)
                if Vector2(center).distance_to(Vector2(cell)) <= radius:
                    var idx = y * map_ref.map_width + x
                    visible_cells[idx] = 1
                    discovered_cells[idx] = 1
    queue_redraw()

func is_world_visible(world_position):
    if not enabled:
        return true
    var cell = map_ref.world_to_cell(world_position)
    return is_cell_visible(cell)

func is_world_discovered(world_position):
    if not enabled:
        return true
    var cell = map_ref.world_to_cell(world_position)
    return is_cell_discovered(cell)

func is_cell_visible(cell):
    if not enabled:
        return true
    if cell.x < 0 or cell.y < 0 or cell.x >= map_ref.map_width or cell.y >= map_ref.map_height:
        return false
    return visible_cells[cell.y * map_ref.map_width + cell.x] == 1

func is_cell_discovered(cell):
    if not enabled:
        return true
    if cell.x < 0 or cell.y < 0 or cell.x >= map_ref.map_width or cell.y >= map_ref.map_height:
        return false
    return discovered_cells[cell.y * map_ref.map_width + cell.x] == 1

func get_cell_state(cell):
    if not enabled:
        return 2
    if is_cell_visible(cell):
        return 2
    if is_cell_discovered(cell):
        return 1
    return 0

func _draw():
    if not enabled or not is_instance_valid(map_ref):
        return
    var tile_size = map_ref.tile_px
    for y in range(map_ref.map_height):
        for x in range(map_ref.map_width):
            var idx = y * map_ref.map_width + x
            if visible_cells[idx] == 1:
                continue
            var color = Color(0, 0, 0, 0.58) if discovered_cells[idx] == 1 else Color(0, 0, 0, 1.0)
            draw_rect(Rect2(Vector2(x * tile_size, y * tile_size), Vector2(tile_size + 1, tile_size + 1)), color)

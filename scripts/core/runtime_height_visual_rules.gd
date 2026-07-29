extends Node

const GRID_SCRIPT_PATH := "res://scripts/game/grid_world.gd"
const HeightTerrainOverlay = preload("res://scripts/game/height_terrain_overlay.gd")

var _maps: Array = []
var _refresh_elapsed: float = 0.0


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


func _process(delta: float) -> void:
    _maps = _maps.filter(func(value): return is_instance_valid(value))
    for map_ref in _maps:
        if not bool(map_ref.get_meta("dev7_height_visual_ready", false)):
            _try_finalize_map(map_ref)
    _refresh_elapsed -= delta
    if _refresh_elapsed <= 0.0:
        _refresh_elapsed = 1.0
        for map_ref in _maps:
            if bool(map_ref.get_meta("dev7_height_visual_ready", false)):
                _enforce_cliff_constraints(map_ref)


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
    if not zones is Array or zones.is_empty():
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
    var cliff_cells: Dictionary = {}
    for y in range(int(map_ref.map_height)):
        for x in range(int(map_ref.map_width)):
            var cell: Vector2i = Vector2i(x, y)
            var level: int = int(map_ref.get_height_level(cell))
            if level <= 0 or int(map_ref.get_slope_type(cell)) != 0:
                continue
            var has_ramp_access: bool = false
            var borders_drop: bool = false
            for direction_variant in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
                var direction: Vector2i = Vector2i(direction_variant)
                var neighbor: Vector2i = cell + direction
                if int(map_ref.get_slope_type(neighbor)) != 0:
                    has_ramp_access = true
                elif int(map_ref.get_height_level(neighbor)) < level:
                    borders_drop = true
            if borders_drop and not has_ramp_access:
                cliff_cells[cell] = true
    map_ref.set_meta("height_cliff_cells", cliff_cells)
    for cell_variant in cliff_cells.keys():
        var cell: Vector2i = Vector2i(cell_variant)
        map_ref.astar_infantry.set_point_solid(cell, true)
        map_ref.astar_vehicle.set_point_solid(cell, true)
    map_ref.astar = map_ref.astar_vehicle

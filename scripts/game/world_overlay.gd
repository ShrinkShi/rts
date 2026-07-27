extends Node2D

var selecting = false
var selection_start = Vector2.ZERO
var selection_end = Vector2.ZERO
var placement_active = false
var placement_cell = Vector2i.ZERO
var placement_footprint = Vector2i.ONE
var placement_valid = false
var map_ref
var command_markers = []
var selected_entities = []
var training_line_x = -1.0

func setup(next_map):
    map_ref = next_map
    z_index = 100

func set_selection(active, from_point, to_point):
    selecting = active
    selection_start = from_point
    selection_end = to_point
    queue_redraw()

func set_placement(active, cell = Vector2i.ZERO, footprint = Vector2i.ONE, valid = false):
    placement_active = active
    placement_cell = cell
    placement_footprint = footprint
    placement_valid = valid
    queue_redraw()

func set_selected_entities(entities):
    selected_entities = []
    for entity in entities:
        if is_instance_valid(entity):
            selected_entities.append(entity)
    queue_redraw()

func add_command_marker(world_position, marker_color = Color("#67D7F5"), label_text = ""):
    command_markers.append({"position": world_position, "life": 0.72, "duration": 0.72, "color": marker_color, "label": label_text})
    queue_redraw()

func _process(delta):
    var changed = false
    for marker in command_markers:
        marker["life"] = float(marker.get("life", 0.0)) - delta
        changed = true
    command_markers = command_markers.filter(func(item): return float(item.get("life", 0.0)) > 0.0)
    if changed or not selected_entities.is_empty() or Input.is_key_pressed(KEY_SHIFT):
        queue_redraw()

func _draw():
    if training_line_x >= 0.0:
        var y = 0.0
        while y < map_ref.map_height * map_ref.tile_px:
            draw_line(Vector2(training_line_x, y), Vector2(training_line_x, min(y + 18.0, map_ref.map_height * map_ref.tile_px)), Color(0.35, 0.85, 1.0, 0.48), 2.0)
            y += 30.0
    if selecting:
        var rect = Rect2(selection_start, selection_end - selection_start).abs()
        draw_rect(rect, Color(0.2, 0.72, 0.95, 0.14))
        draw_rect(rect, Color("#66CFF1"), false, 1.5)
    if placement_active and is_instance_valid(map_ref):
        var top_left = map_ref.cell_to_world(placement_cell) - Vector2(map_ref.tile_px * 0.5, map_ref.tile_px * 0.5)
        var size_value = Vector2(placement_footprint.x * map_ref.tile_px, placement_footprint.y * map_ref.tile_px)
        var color = Color(0.2, 0.9, 0.45, 0.35) if placement_valid else Color(0.95, 0.2, 0.2, 0.35)
        draw_rect(Rect2(top_left, size_value), color)
        draw_rect(Rect2(top_left, size_value), Color(color, 0.95), false, 2.0)
    _draw_selected_waypoints()
    for marker in command_markers:
        var ratio = marker.life / max(0.01, float(marker.get("duration", 0.72)))
        var radius = 18.0 * ratio + 5.0
        draw_arc(marker.position, radius, 0, TAU, 24, Color(marker.color, ratio), 2.0)
        var label_text = str(marker.get("label", ""))
        if label_text != "":
            draw_circle(marker.position, 10.0, Color(0.04, 0.07, 0.08, 0.85 * ratio))
            draw_string(ThemeDB.fallback_font, marker.position + Vector2(-10, 5), label_text, HORIZONTAL_ALIGNMENT_CENTER, 20, 12, Color(marker.color, ratio))

func _draw_selected_waypoints():
    for entity in selected_entities:
        if not is_instance_valid(entity):
            continue
        if entity.has_method("get_patrol_route"):
            var patrol = entity.get_patrol_route()
            if bool(patrol.get("active", false)):
                _draw_patrol_route(entity, patrol)
                continue
        if not entity.has_method("get_order_waypoints"):
            continue
        var points = entity.get_order_waypoints()
        if points.is_empty():
            continue
        var previous = entity.global_position
        for index in range(points.size()):
            var item = points[index]
            var waypoint_position = Vector2(item.get("position", previous))
            var order_type = str(item.get("type", "move"))
            var color = Color("#63D879")
            if order_type in ["attack", "attack_move", "force_attack"]:
                color = Color("#EF625B")
            elif order_type == "harvest":
                color = Color("#E5C34F")
            elif order_type == "repair":
                color = Color("#69D889")
            draw_dashed_line(previous, waypoint_position, Color(color, 0.82), 1.7, 8.0)
            draw_circle(waypoint_position, 8.0, Color(0.03, 0.05, 0.06, 0.88))
            draw_arc(waypoint_position, 9.0, 0, TAU, 20, color, 1.7)
            draw_string(ThemeDB.fallback_font, waypoint_position + Vector2(-8, 4), str(index + 1), HORIZONTAL_ALIGNMENT_CENTER, 16, 11, color)
            previous = waypoint_position

func _draw_patrol_route(entity, patrol):
    var points = patrol.get("points", [])
    if points.is_empty():
        return
    var blue = Color("#55AFFF")
    var previous = entity.global_position
    for index in range(points.size()):
        var patrol_position = Vector2(points[index])
        draw_dashed_line(previous, patrol_position, Color(blue, 0.9), 2.0, 7.0)
        draw_circle(patrol_position, 8.5, Color(0.025, 0.055, 0.09, 0.9))
        draw_arc(patrol_position, 9.5, 0, TAU, 22, blue, 2.0)
        draw_string(ThemeDB.fallback_font, patrol_position + Vector2(-8, 4), str(index + 1), HORIZONTAL_ALIGNMENT_CENTER, 16, 11, blue)
        previous = patrol_position
    if bool(patrol.get("closed", false)) and points.size() >= 2:
        draw_dashed_line(Vector2(points[-1]), Vector2(points[0]), Color(blue, 0.95), 2.2, 7.0)
        draw_circle(Vector2(points[0]), 13.0, Color(blue, 0.12))


extends Control

signal world_clicked(world_position)
signal world_commanded(world_position)

var match_ref
var map_ref
var dragging = false


func setup(next_match, next_map):
    match_ref = next_match
    map_ref = next_map
    custom_minimum_size = Vector2(246, 170)
    mouse_filter = Control.MOUSE_FILTER_STOP
    gui_input.connect(_on_gui_input)
    set_process(true)


func _process(_delta):
    queue_redraw()


func _draw():
    draw_rect(Rect2(Vector2.ZERO, size), Color("#101719"))
    if not is_instance_valid(map_ref):
        return
    var sx = size.x / float(map_ref.map_width)
    var sy = size.y / float(map_ref.map_height)
    for y in range(map_ref.map_height):
        for x in range(map_ref.map_width):
            var cell = Vector2i(x, y)
            var tile = map_ref.terrain[y * map_ref.map_width + x]
            var color = Color("#506A41")
            if tile == map_ref.TILE_DIRT:
                color = Color("#705F43")
            elif tile == map_ref.TILE_WATER:
                color = Color("#2F6177")
            elif tile == map_ref.TILE_ROCK:
                color = Color("#454C4E")

            # Ore is no longer encoded as TILE_ORE. Minimap resource visibility
            # must query the independent Overlay/resource state instead.
            if map_ref.has_ore(cell):
                color = Color("#B89A2C")

            var cell_rect = Rect2(
                Vector2(x * sx, y * sy),
                Vector2(ceil(sx) + 0.2, ceil(sy) + 0.2)
            )
            draw_rect(cell_rect, color)
            if is_instance_valid(match_ref.fog) and match_ref.fog.enabled:
                var fog_state = match_ref.fog.get_cell_state(cell)
                if fog_state == 0:
                    draw_rect(cell_rect, Color.BLACK)
                elif fog_state == 1:
                    draw_rect(cell_rect, Color(0, 0, 0, 0.58))
    for building in match_ref.buildings:
        if is_instance_valid(building) and _entity_visible(building):
            var p = Vector2(building.global_position.x / (map_ref.map_width * map_ref.tile_px) * size.x, building.global_position.y / (map_ref.map_height * map_ref.tile_px) * size.y)
            draw_rect(Rect2(p - Vector2(2.5, 2.5), Vector2(5, 5)), match_ref.get_player_color(building.owner_id))
    for unit in match_ref.units:
        if is_instance_valid(unit) and _entity_visible(unit):
            var p = Vector2(unit.global_position.x / (map_ref.map_width * map_ref.tile_px) * size.x, unit.global_position.y / (map_ref.map_height * map_ref.tile_px) * size.y)
            draw_circle(p, 1.8, match_ref.get_player_color(unit.owner_id))
    if is_instance_valid(match_ref.camera):
        var battle_rect = match_ref.get_world_battle_rect()
        var camera_rect = Rect2(
            Vector2(battle_rect.position.x / (map_ref.map_width * map_ref.tile_px) * size.x, battle_rect.position.y / (map_ref.map_height * map_ref.tile_px) * size.y),
            Vector2(battle_rect.size.x / (map_ref.map_width * map_ref.tile_px) * size.x, battle_rect.size.y / (map_ref.map_height * map_ref.tile_px) * size.y)
        )
        draw_rect(camera_rect, Color("#E9F5F8"), false, 1.0)
    draw_rect(Rect2(Vector2.ZERO, size), Color("#6C8792"), false, 2.0)


func _entity_visible(entity):
    if entity.owner_id == 0:
        return true
    if is_instance_valid(match_ref.fog):
        return match_ref.fog.is_world_visible(entity.global_position)
    return true


func _local_to_world(local_position):
    if not is_instance_valid(map_ref):
        return Vector2.ZERO
    var clamped = Vector2(clamp(local_position.x, 0.0, size.x), clamp(local_position.y, 0.0, size.y))
    var ratio = clamped / size
    return Vector2(ratio.x * map_ref.map_width * map_ref.tile_px, ratio.y * map_ref.map_height * map_ref.tile_px)


func _emit_world_position(local_position):
    if not is_instance_valid(map_ref):
        return
    world_clicked.emit(_local_to_world(local_position))


func _input(event):
    if not dragging:
        return
    # 拖出小地图边界后仍持续跟随，并把坐标限制在小地图范围内。
    if event is InputEventMouseMotion:
        _emit_world_position(get_local_mouse_position())
        get_viewport().set_input_as_handled()
        return
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
        dragging = false
        get_viewport().set_input_as_handled()


func _on_gui_input(event):
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        dragging = event.pressed
        if event.pressed:
            _emit_world_position(event.position)
        accept_event()
        return
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
        world_commanded.emit(_local_to_world(event.position))
        accept_event()
        return
    if event is InputEventMouseMotion and dragging:
        _emit_world_position(event.position)
        accept_event()

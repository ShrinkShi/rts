extends Node

var textures = {}
var hotspots = {}
var current_state = ""

func _ready():
    _build_cursors()
    set_state("default")

func set_state(state):
    var next_state = state if textures.has(state) else "default"
    if current_state == next_state:
        return
    current_state = next_state
    Input.set_custom_mouse_cursor(textures[next_state], Input.CURSOR_ARROW, hotspots.get(next_state, Vector2(16, 16)))

func reset():
    set_state("default")

func _build_cursors():
    textures["default"] = _make_default_cursor()
    hotspots["default"] = Vector2(2, 2)
    textures["select"] = _make_target_cursor(Color("#63D6F3"), false, false)
    textures["selected"] = _make_target_cursor(Color("#74E68C"), true, false)
    textures["attack"] = _make_target_cursor(Color("#F0615D"), false, true)
    textures["enemy"] = _make_target_cursor(Color("#E79B55"), false, true)
    textures["move"] = _make_move_cursor(Color("#E7D36B"))
    textures["build_valid"] = _make_build_cursor(Color("#69D984"), true)
    textures["build_invalid"] = _make_build_cursor(Color("#F06460"), false)
    textures["pan"] = _make_pan_cursor(Color("#DDE9ED"))
    textures["primary"] = _make_target_cursor(Color("#F0D05E"), true, false)
    for key in textures:
        if key != "default":
            hotspots[key] = Vector2(16, 16)

func _new_image():
    var image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
    image.fill(Color(0, 0, 0, 0))
    return image

func _texture(image):
    return ImageTexture.create_from_image(image)

func _make_default_cursor():
    var image = _new_image()
    var outline = Color("#101719")
    var fill = Color("#EAF3F6")
    var points = [Vector2i(2, 2), Vector2i(2, 23), Vector2i(7, 18), Vector2i(11, 29), Vector2i(15, 27), Vector2i(11, 17), Vector2i(19, 17)]
    _draw_polyline(image, points + [points[0]], outline, 3)
    _draw_polyline(image, points + [points[0]], fill, 1)
    return _texture(image)

func _make_target_cursor(color, checked, crossed):
    var image = _new_image()
    var shadow = Color(0.02, 0.04, 0.05, 0.9)
    for offset in [0, 1]:
        _draw_line(image, Vector2i(5, 10 + offset), Vector2i(5, 5), shadow, 2)
        _draw_line(image, Vector2i(5, 5), Vector2i(10 + offset, 5), shadow, 2)
        _draw_line(image, Vector2i(22 - offset, 5), Vector2i(27, 5), shadow, 2)
        _draw_line(image, Vector2i(27, 5), Vector2i(27, 10 + offset), shadow, 2)
        _draw_line(image, Vector2i(5, 22 - offset), Vector2i(5, 27), shadow, 2)
        _draw_line(image, Vector2i(5, 27), Vector2i(10 + offset, 27), shadow, 2)
        _draw_line(image, Vector2i(22 - offset, 27), Vector2i(27, 27), shadow, 2)
        _draw_line(image, Vector2i(27, 27), Vector2i(27, 22 - offset), shadow, 2)
    _draw_line(image, Vector2i(5, 10), Vector2i(5, 5), color, 1)
    _draw_line(image, Vector2i(5, 5), Vector2i(10, 5), color, 1)
    _draw_line(image, Vector2i(22, 5), Vector2i(27, 5), color, 1)
    _draw_line(image, Vector2i(27, 5), Vector2i(27, 10), color, 1)
    _draw_line(image, Vector2i(5, 22), Vector2i(5, 27), color, 1)
    _draw_line(image, Vector2i(5, 27), Vector2i(10, 27), color, 1)
    _draw_line(image, Vector2i(22, 27), Vector2i(27, 27), color, 1)
    _draw_line(image, Vector2i(27, 27), Vector2i(27, 22), color, 1)
    if checked:
        _draw_line(image, Vector2i(10, 16), Vector2i(14, 20), color, 2)
        _draw_line(image, Vector2i(14, 20), Vector2i(23, 11), color, 2)
    elif crossed:
        _draw_line(image, Vector2i(11, 11), Vector2i(21, 21), color, 2)
        _draw_line(image, Vector2i(21, 11), Vector2i(11, 21), color, 2)
    else:
        _draw_line(image, Vector2i(16, 11), Vector2i(16, 21), color, 1)
        _draw_line(image, Vector2i(11, 16), Vector2i(21, 16), color, 1)
    return _texture(image)

func _make_move_cursor(color):
    var image = _new_image()
    _draw_line(image, Vector2i(16, 4), Vector2i(16, 28), color, 2)
    _draw_line(image, Vector2i(4, 16), Vector2i(28, 16), color, 2)
    _draw_line(image, Vector2i(16, 4), Vector2i(12, 9), color, 2)
    _draw_line(image, Vector2i(16, 4), Vector2i(20, 9), color, 2)
    _draw_line(image, Vector2i(16, 28), Vector2i(12, 23), color, 2)
    _draw_line(image, Vector2i(16, 28), Vector2i(20, 23), color, 2)
    _draw_line(image, Vector2i(4, 16), Vector2i(9, 12), color, 2)
    _draw_line(image, Vector2i(4, 16), Vector2i(9, 20), color, 2)
    _draw_line(image, Vector2i(28, 16), Vector2i(23, 12), color, 2)
    _draw_line(image, Vector2i(28, 16), Vector2i(23, 20), color, 2)
    _draw_circle(image, Vector2i(16, 16), 3, color)
    return _texture(image)

func _make_build_cursor(color, valid):
    var image = _new_image()
    _draw_line(image, Vector2i(6, 8), Vector2i(26, 8), color, 2)
    _draw_line(image, Vector2i(6, 8), Vector2i(6, 24), color, 2)
    _draw_line(image, Vector2i(26, 8), Vector2i(26, 24), color, 2)
    _draw_line(image, Vector2i(6, 24), Vector2i(26, 24), color, 2)
    _draw_line(image, Vector2i(10, 13), Vector2i(22, 13), color, 1)
    _draw_line(image, Vector2i(10, 17), Vector2i(22, 17), color, 1)
    if valid:
        _draw_line(image, Vector2i(10, 20), Vector2i(14, 24), color, 2)
        _draw_line(image, Vector2i(14, 24), Vector2i(24, 14), color, 2)
    else:
        _draw_line(image, Vector2i(10, 12), Vector2i(23, 25), color, 2)
        _draw_line(image, Vector2i(23, 12), Vector2i(10, 25), color, 2)
    return _texture(image)

func _make_pan_cursor(color):
    var image = _new_image()
    _draw_circle(image, Vector2i(16, 16), 4, color)
    for pair in [
        [Vector2i(16, 3), Vector2i(16, 11)],
        [Vector2i(16, 21), Vector2i(16, 29)],
        [Vector2i(3, 16), Vector2i(11, 16)],
        [Vector2i(21, 16), Vector2i(29, 16)]
    ]:
        _draw_line(image, pair[0], pair[1], color, 2)
    _draw_line(image, Vector2i(16, 3), Vector2i(12, 7), color, 2)
    _draw_line(image, Vector2i(16, 3), Vector2i(20, 7), color, 2)
    _draw_line(image, Vector2i(16, 29), Vector2i(12, 25), color, 2)
    _draw_line(image, Vector2i(16, 29), Vector2i(20, 25), color, 2)
    _draw_line(image, Vector2i(3, 16), Vector2i(7, 12), color, 2)
    _draw_line(image, Vector2i(3, 16), Vector2i(7, 20), color, 2)
    _draw_line(image, Vector2i(29, 16), Vector2i(25, 12), color, 2)
    _draw_line(image, Vector2i(29, 16), Vector2i(25, 20), color, 2)
    return _texture(image)

func _draw_polyline(image, points, color, thickness = 1):
    for index in range(points.size() - 1):
        _draw_line(image, points[index], points[index + 1], color, thickness)

func _draw_circle(image, center, radius, color):
    for y in range(center.y - radius, center.y + radius + 1):
        for x in range(center.x - radius, center.x + radius + 1):
            if Vector2(x - center.x, y - center.y).length() <= radius:
                _plot(image, x, y, color)

func _draw_line(image, start, finish, color, thickness = 1):
    var x0 = start.x
    var y0 = start.y
    var x1 = finish.x
    var y1 = finish.y
    var dx = abs(x1 - x0)
    var sx = 1 if x0 < x1 else -1
    var dy = -abs(y1 - y0)
    var sy = 1 if y0 < y1 else -1
    var error = dx + dy
    var half = int(thickness / 2)
    while true:
        for oy in range(-half, half + 1):
            for ox in range(-half, half + 1):
                _plot(image, x0 + ox, y0 + oy, color)
        if x0 == x1 and y0 == y1:
            break
        var twice = 2 * error
        if twice >= dy:
            error += dy
            x0 += sx
        if twice <= dx:
            error += dx
            y0 += sy

func _plot(image, x, y, color):
    if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
        image.set_pixel(x, y, color)

extends Control

func _ready():
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_process(true)

func _process(_delta):
    queue_redraw()

func _draw():
    draw_rect(Rect2(Vector2.ZERO, size), Color("#0B1117"))
    var spacing = 48.0
    var offset = fmod(Time.get_ticks_msec() * 0.006, spacing)
    for x in range(-1, int(size.x / spacing) + 2):
        var px = x * spacing + offset
        draw_line(Vector2(px, 0), Vector2(px, size.y), Color(0.16, 0.24, 0.29, 0.22), 1.0)
    for y in range(-1, int(size.y / spacing) + 2):
        var py = y * spacing + offset * 0.35
        draw_line(Vector2(0, py), Vector2(size.x, py), Color(0.16, 0.24, 0.29, 0.17), 1.0)
    draw_circle(Vector2(size.x * 0.82, size.y * 0.18), 210, Color(0.1, 0.28, 0.34, 0.12))

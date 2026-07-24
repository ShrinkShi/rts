extends Button

var category_id = "primary"
var active = false
var hotkey_text = ""

func setup(next_id, tooltip, next_hotkey = ""):
    category_id = next_id
    tooltip_text = "%s [%s]" % [tooltip, next_hotkey]
    hotkey_text = str(next_hotkey)
    text = ""
    flat = true
    focus_mode = Control.FOCUS_NONE
    custom_minimum_size = Vector2(34, 28)
    queue_redraw()

func set_active(value):
    active = value
    queue_redraw()

func _draw():
    var bg = Color("#263A44") if active else (Color("#20313A") if is_hovered() else Color("#15232A"))
    var border = Color("#8BC5D9") if active else Color("#3F5964")
    draw_rect(Rect2(Vector2.ZERO, size), bg)
    draw_rect(Rect2(Vector2.ZERO, size), border, false, 1.5)
    var c = size * 0.5
    var color = Color("#9BC7D7") if not disabled else Color("#596A71")
    if category_id == "primary":
        draw_rect(Rect2(c + Vector2(-10, -6), Vector2(20, 13)), color.darkened(0.2))
        draw_polyline(PackedVector2Array([c + Vector2(-12, -6), c + Vector2(0, -13), c + Vector2(12, -6)]), color, 2.0)
    elif category_id == "defense":
        draw_circle(c + Vector2(-3, 2), 7.0, color)
        draw_line(c + Vector2(2, 0), c + Vector2(12, -6), color, 4.0)
    elif category_id == "infantry":
        draw_circle(c + Vector2(0, -6), 4.0, color)
        draw_line(c + Vector2(0, -2), c + Vector2(0, 9), color, 3.0)
        draw_line(c + Vector2(0, 2), c + Vector2(8, -1), color, 2.0)
        draw_line(c + Vector2(0, 8), c + Vector2(-6, 13), color, 2.0)
        draw_line(c + Vector2(0, 8), c + Vector2(6, 13), color, 2.0)
    elif category_id == "vehicle":
        draw_rect(Rect2(c + Vector2(-11, -6), Vector2(22, 12)), color.darkened(0.12))
        draw_circle(c + Vector2(-7, 8), 3.0, color)
        draw_circle(c + Vector2(7, 8), 3.0, color)
    elif category_id == "air":
        var points = PackedVector2Array([c + Vector2(0, -12), c + Vector2(4, -2), c + Vector2(12, 2), c + Vector2(4, 4), c + Vector2(2, 12), c + Vector2(-2, 12), c + Vector2(-4, 4), c + Vector2(-12, 2), c + Vector2(-4, -2)])
        draw_colored_polygon(points, color)
    else:
        draw_polyline(PackedVector2Array([c + Vector2(-12, -3), c + Vector2(-7, 7), c + Vector2(8, 7), c + Vector2(13, -3)]), color, 3.0)
        draw_line(c + Vector2(-7, -3), c + Vector2(7, -3), color, 2.0)
    if hotkey_text != "":
        draw_circle(Vector2(size.x - 7, 7), 6.0, Color(0.03, 0.055, 0.065, 0.92))
        draw_string(ThemeDB.fallback_font, Vector2(size.x - 13, 10), hotkey_text, HORIZONTAL_ALIGNMENT_CENTER, 12, 8, Color("#F0D269"))

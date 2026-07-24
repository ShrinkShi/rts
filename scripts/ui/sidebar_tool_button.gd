extends Button

var icon_kind = "repair"
var active = false

func setup(kind, title, tooltip):
    icon_kind = "repair" if str(kind) == "repair_building" else "sell"
    tooltip_text = "%s\n%s" % [str(title), str(tooltip)]
    text = ""
    focus_mode = Control.FOCUS_NONE
    custom_minimum_size = Vector2(44, 32)
    queue_redraw()

func set_active(value):
    active = bool(value)
    queue_redraw()

func _draw():
    var center = size * 0.5
    var color = Color("#F0D05E") if active else Color("#C6D5DB")
    if icon_kind == "repair":
        draw_line(center + Vector2(-10, 9), center + Vector2(7, -8), color, 4.0)
        draw_arc(center + Vector2(8, -9), 7.0, -PI * 0.15, PI * 1.15, 18, color, 3.0)
        draw_circle(center + Vector2(-10, 10), 4.0, color)
    else:
        draw_string(ThemeDB.fallback_font, Vector2(0, center.y + 8), "$", HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, color)

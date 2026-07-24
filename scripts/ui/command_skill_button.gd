extends Button

var command_id = ""
var skill_name = ""
var effect_text = ""
var hotkey_text = ""
var icon_id = ""
var configured = false
var active = false

func _ready():
    focus_mode = Control.FOCUS_NONE
    clip_text = true
    text = ""
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    size_flags_vertical = Control.SIZE_EXPAND_FILL
    custom_minimum_size = Vector2(46, 34)

func configure(next_command_id, next_name, next_effect, next_hotkey, next_icon):
    command_id = str(next_command_id)
    skill_name = str(next_name)
    effect_text = str(next_effect)
    hotkey_text = str(next_hotkey)
    icon_id = str(next_icon)
    configured = true
    disabled = false
    mouse_filter = Control.MOUSE_FILTER_STOP
    tooltip_text = "%s\n效果：%s\n快捷键：%s" % [skill_name, effect_text, hotkey_text if hotkey_text != "" else "无"]
    queue_redraw()

func clear_slot():
    command_id = ""
    skill_name = ""
    effect_text = ""
    hotkey_text = ""
    icon_id = ""
    configured = false
    active = false
    disabled = true
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    tooltip_text = ""
    queue_redraw()

func set_active(value):
    active = bool(value)
    queue_redraw()

func _draw():
    if not configured:
        return
    var center = size * 0.5 + Vector2(0, 1)
    var icon_color = Color("#EAF4F7") if not disabled else Color("#65757D")
    if active:
        icon_color = Color("#F1D36D")
    _draw_icon(center, min(size.x, size.y) * 0.29, icon_color)
    if hotkey_text != "":
        var key_color = Color("#F3D36D") if not disabled else Color("#65757D")
        draw_string(ThemeDB.fallback_font, Vector2(size.x - 19, 11), hotkey_text, HORIZONTAL_ALIGNMENT_CENTER, 17, 9, key_color)

func _draw_icon(center, radius, color):
    match icon_id:
        "move":
            draw_line(center + Vector2(-radius, radius * 0.55), center + Vector2(radius * 0.65, -radius * 0.55), color, 2.4)
            draw_colored_polygon(PackedVector2Array([
                center + Vector2(radius * 0.15, -radius * 0.75),
                center + Vector2(radius, -radius * 0.85),
                center + Vector2(radius * 0.78, 0.0)
            ]), color)
        "attack":
            draw_arc(center, radius * 0.72, 0, TAU, 20, color, 2.0)
            draw_line(center + Vector2(-radius, 0), center + Vector2(radius, 0), color, 1.6)
            draw_line(center + Vector2(0, -radius), center + Vector2(0, radius), color, 1.6)
            draw_colored_polygon(PackedVector2Array([
                center + Vector2(radius * 0.2, -radius * 0.2),
                center + Vector2(radius * 0.88, -radius * 0.88),
                center + Vector2(radius * 0.62, radius * 0.02)
            ]), color)
        "stop":
            draw_rect(Rect2(center - Vector2(radius * 0.72, radius * 0.72), Vector2(radius * 1.44, radius * 1.44)), color, true)
        "hold":
            var points = PackedVector2Array([
                center + Vector2(0, -radius),
                center + Vector2(radius * 0.78, -radius * 0.55),
                center + Vector2(radius * 0.62, radius * 0.5),
                center + Vector2(0, radius),
                center + Vector2(-radius * 0.62, radius * 0.5),
                center + Vector2(-radius * 0.78, -radius * 0.55)
            ])
            var closed_points = points.duplicate()
            closed_points.append(points[0])
            draw_polyline(closed_points, color, 2.0)
            draw_line(center + Vector2(0, -radius * 0.55), center + Vector2(0, radius * 0.55), color, 1.8)
        "patrol":
            draw_arc(center, radius * 0.78, -PI * 0.2, PI * 1.45, 24, color, 2.2)
            draw_colored_polygon(PackedVector2Array([
                center + Vector2(-radius * 0.95, -radius * 0.18),
                center + Vector2(-radius * 0.33, -radius * 0.42),
                center + Vector2(-radius * 0.42, radius * 0.22)
            ]), color)
            draw_circle(center, radius * 0.18, color)
        "harvest":
            draw_circle(center + Vector2(-radius * 0.38, radius * 0.38), radius * 0.42, Color("#D4B841"))
            draw_line(center + Vector2(-radius * 0.05, radius * 0.65), center + Vector2(radius * 0.58, -radius * 0.62), color, 2.7)
            draw_line(center + Vector2(radius * 0.15, -radius * 0.65), center + Vector2(radius * 0.92, -radius * 0.34), color, 2.3)
        "rally":
            draw_line(center + Vector2(-radius * 0.58, radius), center + Vector2(-radius * 0.58, -radius), color, 2.2)
            draw_colored_polygon(PackedVector2Array([
                center + Vector2(-radius * 0.48, -radius * 0.88),
                center + Vector2(radius * 0.88, -radius * 0.48),
                center + Vector2(-radius * 0.48, -radius * 0.05)
            ]), color)
        "primary":
            var points = PackedVector2Array()
            for index in range(10):
                var angle = -PI * 0.5 + index * PI / 5.0
                var point_radius = radius if index % 2 == 0 else radius * 0.45
                points.append(center + Vector2.RIGHT.rotated(angle) * point_radius)
            draw_colored_polygon(points, color)
        _:
            draw_circle(center, radius * 0.65, color)

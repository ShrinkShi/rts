extends Control

var map_id = "twin_rivers"
var human_position = 0
var ai_count = 1
var human_color = Color("#4FA3FF")
var ai_color = Color("#E14B4B")

func _ready():
    custom_minimum_size = Vector2(390, 250)
    mouse_filter = Control.MOUSE_FILTER_IGNORE

func configure(next_map_id, next_human_position, next_ai_count, next_human_color, next_ai_color):
    map_id = next_map_id
    human_position = next_human_position
    ai_count = next_ai_count
    human_color = next_human_color
    ai_color = next_ai_color
    queue_redraw()

func _draw():
    var rect = Rect2(Vector2(8, 8), size - Vector2(16, 16))
    draw_rect(rect, Color("#283526"))
    draw_rect(rect, Color("#607065"), false, 2.0)
    var config = GameConfig.maps.get(map_id, {})
    var style = config.get("style", "open")
    if style == "rivers":
        draw_rect(Rect2(rect.position + Vector2(rect.size.x * 0.42, 0), Vector2(rect.size.x * 0.08, rect.size.y)), Color("#315D70"))
        draw_rect(Rect2(rect.position + Vector2(rect.size.x * 0.63, 0), Vector2(rect.size.x * 0.055, rect.size.y)), Color("#315D70"))
    elif style == "coast":
        var points = PackedVector2Array([
            rect.position + Vector2(rect.size.x * 0.72, 0), rect.end - Vector2(0, rect.size.y),
            rect.end, rect.position + Vector2(rect.size.x * 0.58, rect.size.y),
            rect.position + Vector2(rect.size.x * 0.66, rect.size.y * 0.42)
        ])
        draw_colored_polygon(points, Color("#315D70"))
    else:
        for i in range(6):
            var p = rect.position + Vector2(35 + i * 55, 40 + (i % 3) * 55)
            draw_circle(p, 16, Color("#8C7B35"))

    var positions = config.get("positions", [])
    for index in range(positions.size()):
        var map_size = config.get("size", [64, 48])
        var source = positions[index]
        var p = rect.position + Vector2(float(source[0]) / map_size[0] * rect.size.x, float(source[1]) / map_size[1] * rect.size.y)
        var color = Color("#687780")
        if index == human_position:
            color = human_color
        elif index < ai_count + 1 or (human_position == 0 and index <= ai_count):
            color = ai_color
        draw_circle(p, 10, Color(0.02, 0.03, 0.04, 0.9))
        draw_circle(p, 7, color)
        draw_string(ThemeDB.fallback_font, p + Vector2(12, 5), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

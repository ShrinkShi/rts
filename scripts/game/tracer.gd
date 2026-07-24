extends Node2D

var start_point = Vector2.ZERO
var end_point = Vector2.ZERO
var color = Color.WHITE
var life = 0.12
var max_life = 0.12

func setup(from_point, to_point, tracer_color):
    start_point = from_point
    end_point = to_point
    color = tracer_color
    z_index = 80

func _process(delta):
    life -= delta
    queue_redraw()
    if life <= 0.0:
        queue_free()

func _draw():
    var alpha = clamp(life / max_life, 0.0, 1.0)
    draw_line(start_point, end_point, Color(color, alpha), 2.0)
    draw_circle(end_point, 3.5, Color(1.0, 0.85, 0.45, alpha))

extends Node2D

var facing: Vector2 = Vector2.RIGHT
var team_color: Color = Color("#D94848")
var attacking: bool = false
var damaged: bool = false
var powered: bool = true


func configure(color: Color) -> void:
    team_color = color
    z_index = 6
    queue_redraw()


func set_state(next_facing: Vector2, is_attacking: bool, is_damaged: bool, is_powered: bool) -> void:
    if next_facing.length_squared() > 0.001:
        facing = next_facing.normalized()
    attacking = is_attacking
    damaged = is_damaged
    powered = is_powered
    queue_redraw()


func _draw() -> void:
    var direction: Vector2 = facing.normalized()
    var side: Vector2 = Vector2(-direction.y, direction.x)
    var body_color: Color = Color("#50565C") if powered else Color("#3A3D40")
    var light_color: Color = Color("#8F989E") if powered else Color("#5A5E61")
    if damaged:
        body_color = body_color.darkened(0.22)
        light_color = light_color.darkened(0.18)

    draw_set_transform(Vector2(0.0, 5.0), 0.0, Vector2(1.0, 0.42))
    draw_circle(Vector2.ZERO, 11.0, Color(0.02, 0.02, 0.025, 0.42))
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

    draw_circle(Vector2(0.0, 2.0), 9.5, Color("#24282B"))
    draw_circle(Vector2.ZERO, 8.2, body_color)
    draw_arc(Vector2.ZERO, 8.0, 0.0, TAU, 24, Color("#151719"), 1.5)

    var rear: Vector2 = -direction * 3.5
    var housing: PackedVector2Array = PackedVector2Array([
        rear + side * 5.5 + Vector2(0.0, -2.0),
        rear - side * 5.5 + Vector2(0.0, -2.0),
        rear - side * 4.0 + direction * 7.0 + Vector2(0.0, 1.0),
        rear + side * 4.0 + direction * 7.0 + Vector2(0.0, 1.0)
    ])
    draw_colored_polygon(housing, body_color)
    draw_polyline(
        PackedVector2Array([housing[0], housing[1], housing[2], housing[3], housing[0]]),
        Color("#1C1F22"),
        1.2
    )

    draw_line(direction * 2.0, direction * 18.0, Color("#171A1C"), 5.5)
    draw_line(direction * 3.0, direction * 18.0, light_color, 2.2)
    draw_line(
        direction * 6.0 + side * 2.5,
        direction * 15.0 + side * 2.5,
        Color("#32373B"),
        1.5
    )
    draw_line(
        direction * 6.0 - side * 2.5,
        direction * 15.0 - side * 2.5,
        Color("#32373B"),
        1.5
    )

    draw_circle(direction * 1.0 + Vector2(0.0, -1.0), 3.0, team_color.darkened(0.18))
    draw_circle(direction * 1.0 + Vector2(0.0, -1.0), 1.4, team_color.lightened(0.16))

    if damaged:
        draw_line(Vector2(-4.0, -3.0), Vector2(2.0, 4.0), Color("#171719"), 1.3)
    if attacking:
        var muzzle: Vector2 = direction * 20.0
        draw_circle(muzzle, 3.2, Color("#FFD77A"))
        draw_line(muzzle - direction * 2.0, muzzle + direction * 5.0, Color("#FFF1B0"), 2.0)

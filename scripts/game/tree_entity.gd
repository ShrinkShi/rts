extends Node2D

const CombatEffect = preload("res://scripts/game/combat_effect.gd")

signal died(entity)

const LAYER_TREE = 8
const LAYER_VEHICLE = 2

var match_ref
var map_ref
var cell = Vector2i.ZERO
var owner_id = -1
var dense = false
var hp = 100.0
var max_hp = 100.0
var selected = false
var hover_state = ""
var team_color = Color("#507A3F")
var stats = {}
var static_body

func setup(next_match, next_map, next_cell, is_dense = false):
    match_ref = next_match
    map_ref = next_map
    cell = next_cell
    dense = bool(is_dense)
    max_hp = 180.0 if dense else 95.0
    hp = max_hp
    stats = {
        "name": "茂密树林" if dense else "稀疏树木",
        "resource_type": "环境目标",
        "armor": 0,
        "armor_type": "木质",
        "description": "步兵可进入并获得25%减伤。" + ("茂密树林会阻挡车辆。" if dense else "稀疏树木允许车辆通过。")
    }
    global_position = map_ref.cell_to_world(cell)
    z_index = 1
    if dense:
        _build_vehicle_collision()
    queue_redraw()

func _build_vehicle_collision():
    static_body = StaticBody2D.new()
    static_body.collision_layer = LAYER_TREE
    static_body.collision_mask = LAYER_VEHICLE
    var shape_node = CollisionShape2D.new()
    var circle = CircleShape2D.new()
    circle.radius = map_ref.tile_px * 0.34
    shape_node.shape = circle
    static_body.add_child(shape_node)
    add_child(static_body)

func is_tree_entity():
    return true

func is_force_attack_target():
    return true

func get_selection_rect():
    var half = map_ref.tile_px * 0.48
    return Rect2(global_position - Vector2(half, half * 1.6), Vector2(half * 2.0, half * 2.2))

func set_selected(value):
    selected = bool(value)
    queue_redraw()

func set_hover_state(value):
    hover_state = str(value)
    queue_redraw()

func get_sight_radius_cells():
    return 0

func take_damage(amount, source = null):
    var actual = max(1.0, float(amount))
    hp -= actual
    if is_instance_valid(match_ref):
        match_ref.spawn_combat_text(global_position + Vector2(0, -22), "-%d" % int(round(actual)), "damage")
    queue_redraw()
    if hp <= 0.0:
        hp = 0.0
        if is_instance_valid(source) and source.has_method("gain_experience"):
            source.gain_experience(max_hp * 0.2)
        if is_instance_valid(map_ref):
            map_ref.remove_tree(cell)
        if is_instance_valid(match_ref) and is_instance_valid(match_ref.effect_layer):
            var effect = CombatEffect.new()
            match_ref.effect_layer.add_child(effect)
            effect.global_position = global_position + Vector2(0, -12)
            effect.setup("debris", Color("#6F8C4B"), 0.75, false, get_instance_id())
        died.emit(self)
        queue_free()
    return actual

func _draw():
    var trunk = Color("#5A3E29")
    var leaf = Color("#3F6D39") if dense else Color("#5B8247")
    var leaf_light = leaf.lightened(0.18)
    draw_set_transform(Vector2(0, 10), 0.0, Vector2(1.0, 0.38))
    draw_circle(Vector2.ZERO, 15.0 if dense else 11.0, Color(0.02, 0.03, 0.02, 0.35))
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
    draw_rect(Rect2(Vector2(-3, -24), Vector2(6, 30)), trunk)
    var count = 5 if dense else 3
    for index in range(count):
        var angle = TAU * float(index) / float(count) + (0.22 if dense else 0.0)
        var offset = Vector2(cos(angle) * (8.0 if dense else 6.0), sin(angle) * 5.0 - 28.0)
        draw_circle(offset, 12.5 if dense else 10.0, leaf if index % 2 == 0 else leaf_light)
    draw_circle(Vector2(0, -35), 13.5 if dense else 10.5, leaf_light)
    if selected or hover_state != "":
        var color = Color("#75E6FF") if selected else Color("#E9CC66")
        draw_arc(Vector2(0, 5), 18.0, 0, TAU, 32, color, 2.0)
    if selected or hp < max_hp:
        var width = 40.0
        var y = -54.0
        draw_rect(Rect2(Vector2(-width * 0.5, y), Vector2(width, 5)), Color("#311D1D"))
        draw_rect(Rect2(Vector2(-width * 0.5, y), Vector2(width * clamp(hp / max_hp, 0.0, 1.0), 5)), Color("#61C46E"))

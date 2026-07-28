extends Node2D

var match_ref
var source_entity
var target_entity
var owner_id: int = 0
var start_position: Vector2 = Vector2.ZERO
var target_position: Vector2 = Vector2.ZERO
var damage: float = 0.0
var area_radius: float = 0.0
var speed: float = 320.0
var arc_height: float = 42.0
var elapsed: float = 0.0
var duration: float = 0.2
var shell_color: Color = Color("#E7D29A")
var trail_points: PackedVector2Array = PackedVector2Array()
var start_ground_height: float = 0.0
var target_ground_height: float = 0.0

func setup(
    next_match,
    source,
    target,
    destination: Vector2,
    next_damage: float,
    next_area_radius: float,
    next_speed: float = 320.0,
    next_arc_height: float = 42.0
) -> void:
    match_ref = next_match
    source_entity = source
    target_entity = target
    owner_id = int(source.owner_id) if is_instance_valid(source) else 0
    start_position = global_position
    target_position = destination
    damage = next_damage
    area_radius = next_area_radius
    speed = maxf(80.0, next_speed)
    arc_height = maxf(0.0, next_arc_height)
    duration = maxf(0.08, start_position.distance_to(target_position) / speed)
    if is_instance_valid(match_ref) and is_instance_valid(match_ref.grid) and match_ref.grid.has_method("get_ground_height"):
        start_ground_height = float(match_ref.grid.get_ground_height(start_position))
        target_ground_height = float(match_ref.grid.get_ground_height(target_position))
    z_index = 60 + int(start_ground_height / 4.0)
    trail_points.append(global_position + Vector2(0.0, -start_ground_height))
    queue_redraw()

func _process(delta: float) -> void:
    elapsed += delta
    if is_instance_valid(target_entity):
        target_position = target_entity.global_position
        if is_instance_valid(match_ref) and is_instance_valid(match_ref.grid) and match_ref.grid.has_method("get_ground_height"):
            target_ground_height = float(match_ref.grid.get_ground_height(target_position))
    var progress: float = clampf(elapsed / duration, 0.0, 1.0)
    var ground_position: Vector2 = start_position.lerp(target_position, progress)
    var terrain_height: float = lerpf(start_ground_height, target_ground_height, progress)
    var vertical_offset: float = -sin(progress * PI) * arc_height
    global_position = ground_position + Vector2(0.0, -terrain_height + vertical_offset)
    z_index = 60 + int((terrain_height - vertical_offset) / 4.0)
    if trail_points.is_empty() or trail_points[-1].distance_to(global_position) > 7.0:
        trail_points.append(global_position)
        if trail_points.size() > 7:
            trail_points.remove_at(0)
    queue_redraw()
    if progress >= 1.0:
        _impact()

func _impact() -> void:
    if is_instance_valid(match_ref):
        if is_instance_valid(target_entity) and target_entity.has_method("take_damage"):
            if is_instance_valid(source_entity):
                match_ref.apply_weapon_damage(source_entity, target_entity, damage, area_radius)
            else:
                target_entity.take_damage(damage, null)
                if area_radius > 0.0:
                    match_ref.apply_ground_damage(null, target_position, damage, area_radius, target_entity)
        else:
            match_ref.apply_ground_damage(source_entity if is_instance_valid(source_entity) else null, target_position, damage, area_radius)
        match_ref.spawn_muzzle_flash(target_position + Vector2(0.0, -target_ground_height), Color("#E5A84B"))
    queue_free()

func _draw() -> void:
    if trail_points.size() >= 2:
        for index in range(1, trail_points.size()):
            var alpha: float = float(index) / float(trail_points.size()) * 0.24
            draw_line(
                to_local(trail_points[index - 1]),
                to_local(trail_points[index]),
                Color(0.72, 0.66, 0.53, alpha),
                1.4
            )
    var direction: Vector2 = start_position.direction_to(target_position)
    if direction.length_squared() < 0.001:
        direction = Vector2.RIGHT
    draw_line(-direction * 4.5, direction * 4.5, Color("#4E3922"), 3.2)
    draw_line(-direction * 3.5, direction * 3.5, shell_color, 1.8)

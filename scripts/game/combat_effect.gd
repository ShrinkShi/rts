extends Node2D

var effect_type = "explosion"
var duration = 1.2
var elapsed = 0.0
var intensity = 1.0
var effect_color = Color.WHITE
var particles = []
var rng = RandomNumberGenerator.new()
var looping = false
var source_radius = 16.0


func setup(next_type, next_color = Color.WHITE, next_intensity = 1.0, next_looping = false, seed_value = 0):
    effect_type = str(next_type)
    effect_color = next_color
    intensity = max(0.2, float(next_intensity))
    looping = bool(next_looping)
    rng.seed = int(seed_value) if int(seed_value) != 0 else int(Time.get_ticks_usec() & 0x7fffffff)
    if effect_type == "explosion":
        duration = 1.45
        _spawn_explosion_particles()
    elif effect_type == "smoke":
        duration = 999999.0 if looping else 2.6
        source_radius = 10.0 * intensity
    elif effect_type == "building_collapse":
        duration = 2.1
        _spawn_explosion_particles(16)
    elif effect_type == "ore_harvest":
        duration = 0.72
        _spawn_ore_particles()
    elif effect_type == "muzzle":
        duration = 0.16
    queue_redraw()


func _spawn_explosion_particles(forced_count = -1):
    var count = forced_count if forced_count > 0 else int(11 + intensity * 8)
    for index in range(count):
        var angle = rng.randf_range(0.0, TAU)
        var speed = rng.randf_range(38.0, 125.0) * intensity
        particles.append({
            "position": Vector2.ZERO,
            "velocity": Vector2.from_angle(angle) * speed + Vector2(0, rng.randf_range(-55.0, -12.0)),
            "life": rng.randf_range(0.65, 1.45),
            "max_life": 1.45,
            "size": rng.randf_range(2.0, 6.5) * intensity,
            "rotation": rng.randf_range(0.0, TAU),
            "spin": rng.randf_range(-7.0, 7.0),
            "kind": "debris" if index % 3 else "smoke"
        })


func _spawn_ore_particles() -> void:
    var count: int = maxi(5, int(round(8.0 * intensity)))
    for index in range(count):
        var is_ore: bool = index % 3 != 0
        particles.append({
            "position": Vector2(rng.randf_range(-5.0, 5.0), rng.randf_range(-2.0, 3.0)),
            "velocity": Vector2(rng.randf_range(-24.0, 24.0), rng.randf_range(-58.0, -25.0)) * intensity,
            "life": rng.randf_range(0.36, 0.68),
            "max_life": 0.68,
            "size": rng.randf_range(1.5, 3.2) * intensity,
            "rotation": rng.randf_range(0.0, TAU),
            "spin": rng.randf_range(-9.0, 9.0),
            "kind": "ore" if is_ore else "ore_dust"
        })


func _process(delta):
    elapsed += delta
    if effect_type == "smoke":
        _process_smoke(delta)
    elif effect_type == "ore_harvest":
        _process_ore_harvest(delta)
    elif effect_type != "muzzle":
        _process_explosion(delta)
    queue_redraw()
    if not looping and elapsed >= duration:
        queue_free()


func _process_smoke(delta):
    var spawn_rate = 0.085 / max(0.35, intensity)
    if particles.is_empty() or elapsed - float(particles[particles.size() - 1].get("spawn_time", -1.0)) >= spawn_rate:
        particles.append({
            "position": Vector2(rng.randf_range(-source_radius * 0.35, source_radius * 0.35), rng.randf_range(-2.0, 2.0)),
            "velocity": Vector2(rng.randf_range(-7.0, 7.0), rng.randf_range(-24.0, -14.0)) * intensity,
            "life": rng.randf_range(1.2, 2.1),
            "max_life": 2.1,
            "size": rng.randf_range(4.0, 8.0) * intensity,
            "spawn_time": elapsed,
            "kind": "smoke"
        })
    for particle in particles:
        particle["position"] = Vector2(particle.get("position", Vector2.ZERO)) + Vector2(particle.get("velocity", Vector2.ZERO)) * delta
        particle["velocity"] = Vector2(particle.get("velocity", Vector2.ZERO)) + Vector2(rng.randf_range(-2.0, 2.0), -1.0) * delta
        particle["life"] = float(particle.get("life", 0.0)) - delta
        particle["size"] = float(particle.get("size", 4.0)) + delta * 4.0
    particles = particles.filter(func(particle): return float(particle.get("life", 0.0)) > 0.0)


func _process_explosion(delta):
    for particle in particles:
        var particle_position = Vector2(particle.get("position", Vector2.ZERO))
        var velocity = Vector2(particle.get("velocity", Vector2.ZERO))
        velocity += Vector2(0, 135.0) * delta
        particle_position += velocity * delta
        if particle_position.y > 13.0:
            particle_position.y = 13.0
            velocity.y *= -0.26
            velocity.x *= 0.72
        particle["position"] = particle_position
        particle["velocity"] = velocity
        particle["rotation"] = float(particle.get("rotation", 0.0)) + float(particle.get("spin", 0.0)) * delta
        particle["life"] = float(particle.get("life", 0.0)) - delta
    particles = particles.filter(func(particle): return float(particle.get("life", 0.0)) > 0.0)


func _process_ore_harvest(delta: float) -> void:
    for particle in particles:
        var particle_position: Vector2 = Vector2(particle.get("position", Vector2.ZERO))
        var velocity: Vector2 = Vector2(particle.get("velocity", Vector2.ZERO))
        velocity += Vector2(0.0, 112.0) * delta
        particle_position += velocity * delta
        if particle_position.y > 7.0:
            particle_position.y = 7.0
            velocity.y *= -0.18
            velocity.x *= 0.58
        particle["position"] = particle_position
        particle["velocity"] = velocity
        particle["rotation"] = float(particle.get("rotation", 0.0)) + float(particle.get("spin", 0.0)) * delta
        particle["life"] = float(particle.get("life", 0.0)) - delta
    particles = particles.filter(func(particle): return float(particle.get("life", 0.0)) > 0.0)


func _draw():
    if effect_type == "explosion" or effect_type == "building_collapse":
        var burst_ratio = clamp(1.0 - elapsed / 0.42, 0.0, 1.0)
        if burst_ratio > 0.0:
            draw_circle(Vector2(0, -8), (10.0 + 25.0 * (1.0 - burst_ratio)) * intensity, Color(1.0, 0.39, 0.06, 0.72 * burst_ratio))
            draw_circle(Vector2(0, -8), (5.0 + 14.0 * (1.0 - burst_ratio)) * intensity, Color(1.0, 0.84, 0.35, 0.88 * burst_ratio))
    elif effect_type == "muzzle":
        var muzzle_ratio: float = clampf(1.0 - elapsed / maxf(0.01, duration), 0.0, 1.0)
        if muzzle_ratio > 0.0:
            draw_colored_polygon(PackedVector2Array([
                Vector2(-2.0, 0.0), Vector2(0.0, -7.0), Vector2(2.0, 0.0),
                Vector2(7.0, 2.0), Vector2(2.0, 4.0), Vector2(0.0, 9.0),
                Vector2(-2.0, 4.0), Vector2(-7.0, 2.0)
            ]), Color(effect_color.r, effect_color.g, effect_color.b, 0.85 * muzzle_ratio))
            draw_circle(Vector2.ZERO, 2.8, Color(1.0, 0.92, 0.56, muzzle_ratio))

    for particle in particles:
        var life: float = clamp(float(particle.get("life", 0.0)), 0.0, 2.0)
        var max_life: float = maxf(0.01, float(particle.get("max_life", 1.0)))
        var alpha: float = clampf(life / max_life, 0.0, 1.0)
        var particle_position: Vector2 = Vector2(particle.get("position", Vector2.ZERO))
        var size_value: float = float(particle.get("size", 4.0))
        var kind: String = str(particle.get("kind", "debris"))
        if kind == "smoke":
            draw_circle(particle_position, size_value, Color(0.16, 0.18, 0.19, min(0.52, life * 0.35)))
        elif kind == "ore_dust":
            draw_circle(particle_position, size_value * 1.25, Color(0.31, 0.24, 0.10, 0.42 * alpha))
        else:
            var rotation_value: float = float(particle.get("rotation", 0.0))
            var tangent: Vector2 = Vector2.from_angle(rotation_value) * size_value
            var normal: Vector2 = tangent.orthogonal() * (0.62 if kind == "ore" else 0.45)
            var color: Color = effect_color.lightened(0.12) if kind == "ore" else effect_color.darkened(0.5)
            color.a = alpha
            draw_colored_polygon(PackedVector2Array([
                particle_position - tangent,
                particle_position + normal,
                particle_position + tangent,
                particle_position - normal
            ]), color)

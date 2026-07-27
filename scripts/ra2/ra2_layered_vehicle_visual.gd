extends Node2D

var entity_id: String = ""
var theater: String = "temperate"
var manifest: Dictionary = {}
var layer_manifest: Dictionary = {}
var canvas_size: Vector2 = Vector2.ONE
var content_rect: Rect2i = Rect2i()
var body_base: AnimatedSprite2D
var body_remap: AnimatedSprite2D
var turret_base: AnimatedSprite2D
var turret_remap: AnimatedSprite2D
var team_color: Color = Color.WHITE
var current_body_direction: int = 0
var current_turret_direction: int = 0
var current_state: String = "stand"
var _transparent_texture: Texture2D
var _shadow_center: Vector2 = Vector2.ZERO
var _shadow_radius: float = 16.0
var _shadow_alpha: float = 1.0


func setup(next_entity_id: String, next_team_color: Color, next_theater: String = "temperate") -> bool:
    entity_id = next_entity_id.to_upper()
    theater = next_theater
    var bundle: Dictionary = RA2RuntimeDatabase.get_visual_bundle(entity_id, theater)
    if bundle.is_empty():
        return false
    manifest = bundle.get("manifest", {}) as Dictionary
    layer_manifest = manifest.get("layered_vehicle", {}) as Dictionary
    if layer_manifest.is_empty():
        return false
    canvas_size = bundle.get("canvas", Vector2.ONE) as Vector2
    content_rect = bundle.get("content_rect", Rect2i()) as Rect2i
    team_color = next_team_color
    _transparent_texture = _make_transparent_texture()
    body_base = _make_sprite("BodyBase", 0, Color.WHITE)
    body_remap = _make_sprite("BodyRemap", 1, team_color)
    turret_base = _make_sprite("TurretBase", 2, Color.WHITE)
    turret_remap = _make_sprite("TurretRemap", 3, team_color)
    _build_frames()
    play_state("stand", 0, 0, true)
    queue_redraw()
    return true


func _make_sprite(node_name: String, next_z: int, tint: Color) -> AnimatedSprite2D:
    var sprite: AnimatedSprite2D = AnimatedSprite2D.new()
    sprite.name = node_name
    sprite.sprite_frames = SpriteFrames.new()
    if sprite.sprite_frames.has_animation("default"):
        sprite.sprite_frames.remove_animation("default")
    sprite.centered = true
    sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    sprite.z_index = next_z
    sprite.self_modulate = tint
    add_child(sprite)
    return sprite


func _build_frames() -> void:
    var stand: Dictionary = layer_manifest.get("stand", {}) as Dictionary
    var fire: Dictionary = layer_manifest.get("fire", {}) as Dictionary
    var base_dir: String = "res://assets/ra2_preview/%s" % entity_id.to_lower()
    for key_variant: Variant in stand.keys():
        var key: String = str(key_variant)
        var definition: Dictionary = stand[key_variant] as Dictionary
        var body_name: String = "body_%s" % key.replace(":", "_")
        var turret_name: String = "turret_%s" % key.replace(":", "_")
        _add_static_pair(
            body_base.sprite_frames,
            body_remap.sprite_frames,
            body_name,
            base_dir.path_join(str(definition.get("body", ""))),
            base_dir.path_join(str(definition.get("body_remap", "")))
        )
        _add_sequence_pair(
            turret_base.sprite_frames,
            turret_remap.sprite_frames,
            turret_name,
            base_dir,
            definition.get("turret", []) as Array,
            definition.get("turret_remap", []) as Array,
            12.0,
            true
        )
        if fire.has(key):
            var fire_definition: Dictionary = fire[key] as Dictionary
            _add_sequence_pair(
                turret_base.sprite_frames,
                turret_remap.sprite_frames,
                "fire_%s" % key.replace(":", "_"),
                base_dir,
                fire_definition.get("turret", []) as Array,
                fire_definition.get("turret_remap", []) as Array,
                1000.0 / maxf(20.0, float(layer_manifest.get("fire_rate_ms", 90))),
                true
            )


func _add_static_pair(
    base_frames: SpriteFrames,
    remap_frames: SpriteFrames,
    animation_name: String,
    frame_path: String,
    mask_path: String
) -> void:
    base_frames.add_animation(animation_name)
    remap_frames.add_animation(animation_name)
    base_frames.set_animation_loop(animation_name, true)
    remap_frames.set_animation_loop(animation_name, true)
    base_frames.add_frame(animation_name, _load_texture(frame_path))
    remap_frames.add_frame(animation_name, _load_texture(mask_path, true))


func _add_sequence_pair(
    base_frames: SpriteFrames,
    remap_frames: SpriteFrames,
    animation_name: String,
    base_dir: String,
    paths: Array,
    masks: Array,
    fps: float,
    looped: bool
) -> void:
    if paths.is_empty():
        return
    base_frames.add_animation(animation_name)
    remap_frames.add_animation(animation_name)
    base_frames.set_animation_speed(animation_name, fps)
    remap_frames.set_animation_speed(animation_name, fps)
    base_frames.set_animation_loop(animation_name, looped)
    remap_frames.set_animation_loop(animation_name, looped)
    for index in range(paths.size()):
        base_frames.add_frame(animation_name, _load_texture(base_dir.path_join(str(paths[index]))))
        var mask_texture: Texture2D = _transparent_texture
        if index < masks.size():
            mask_texture = _load_texture(base_dir.path_join(str(masks[index])), true)
        remap_frames.add_frame(animation_name, mask_texture)


func _load_texture(path: String, transparent_fallback: bool = false) -> Texture2D:
    if path.is_empty():
        return _transparent_texture
    return RA2RuntimeDatabase.load_runtime_texture(path, transparent_fallback)


func configure_layout(target_width: float, ground_y: float = 0.0, extra_offset: Vector2 = Vector2.ZERO) -> void:
    var width: float = maxf(1.0, float(content_rect.size.x))
    var scale_value: float = target_width / width
    scale = Vector2.ONE * scale_value
    var center_x: float = float(content_rect.position.x) + float(content_rect.size.x) * 0.5
    var bottom_y: float = float(content_rect.position.y + content_rect.size.y)
    _shadow_center = Vector2(
        center_x - canvas_size.x * 0.5,
        bottom_y - canvas_size.y * 0.5 + 1.0
    )
    _shadow_radius = maxf(8.0, float(content_rect.size.x) * 0.34)
    position = (Vector2(
        -(center_x - canvas_size.x * 0.5) * scale_value,
        ground_y - (bottom_y - canvas_size.y * 0.5) * scale_value
    ) + extra_offset).round()
    queue_redraw()


func play_state(
    state_name: String,
    body_direction: int = 0,
    turret_direction: int = 0,
    restart: bool = false
) -> void:
    current_state = state_name
    var turret_visible: bool = state_name != "death"
    turret_base.visible = turret_visible
    turret_remap.visible = turret_visible
    current_body_direction = posmod(body_direction, 8)
    current_turret_direction = posmod(turret_direction, 8)
    var suffix: String = "%d_%d" % [current_body_direction, current_turret_direction]
    var body_animation: String = "body_" + suffix
    var turret_animation: String = "turret_" + suffix
    if state_name == "attack" and turret_base.sprite_frames.has_animation("fire_" + suffix):
        turret_animation = "fire_" + suffix
    _play_pair(body_base, body_remap, body_animation, restart)
    _play_pair(turret_base, turret_remap, turret_animation, restart)


func _play_pair(base: AnimatedSprite2D, remap: AnimatedSprite2D, animation_name: String, restart: bool) -> void:
    if not base.sprite_frames.has_animation(animation_name):
        return
    if restart or base.animation != animation_name:
        base.play(animation_name)
        remap.play(animation_name)


func set_team_color(color: Color) -> void:
    team_color = color
    body_remap.self_modulate = color
    turret_remap.self_modulate = color


func set_alpha(value: float) -> void:
    var alpha: float = clampf(value, 0.0, 1.0)
    _shadow_alpha = alpha
    for sprite in [body_base, body_remap, turret_base, turret_remap]:
        sprite.modulate.a = alpha
    queue_redraw()


func has_state(state_name: String) -> bool:
    return state_name in ["stand", "move", "attack", "idle"]


func visual_top_y() -> float:
    return position.y + (float(content_rect.position.y) - canvas_size.y * 0.5) * scale.y


func _draw() -> void:
    if current_state == "death" or _shadow_alpha <= 0.01:
        return
    draw_set_transform(_shadow_center, 0.0, Vector2(1.0, 0.30))
    draw_circle(
        Vector2.ZERO,
        _shadow_radius,
        Color(0.018, 0.022, 0.018, 0.38 * _shadow_alpha)
    )
    draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _make_transparent_texture() -> Texture2D:
    var image: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
    image.fill(Color.TRANSPARENT)
    return ImageTexture.create_from_image(image)

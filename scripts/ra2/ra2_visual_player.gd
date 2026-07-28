extends Node2D

var entity_id: String = ""
var theater: String = "temperate"
var manifest: Dictionary = {}
var animations: Dictionary = {}
var base_sprite: AnimatedSprite2D
var remap_sprite: AnimatedSprite2D
var canvas_size: Vector2 = Vector2.ONE
var content_rect: Rect2i = Rect2i()
var current_state: String = ""
var current_direction: int = 0
var current_animation: String = ""
var _layout_position: Vector2 = Vector2.ZERO
var _layout_scale: Vector2 = Vector2.ONE
var _terrain_ground_height: float = 0.0
var _terrain_airborne_height: float = 0.0


func setup(next_entity_id: String, team_color: Color, next_theater: String = "temperate") -> bool:
    entity_id = next_entity_id.to_upper()
    theater = next_theater
    var bundle: Dictionary = RA2RuntimeDatabase.get_visual_bundle(entity_id, theater)
    if bundle.is_empty():
        return false
    manifest = bundle.get("manifest", {}) as Dictionary
    animations = bundle.get("animations", {}) as Dictionary
    theater = str(bundle.get("theater", theater))
    canvas_size = bundle.get("canvas", Vector2.ONE) as Vector2
    content_rect = bundle.get("content_rect", Rect2i()) as Rect2i

    base_sprite = AnimatedSprite2D.new()
    base_sprite.name = "Base"
    base_sprite.sprite_frames = bundle.get("base_frames") as SpriteFrames
    base_sprite.centered = true
    base_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    add_child(base_sprite)

    remap_sprite = AnimatedSprite2D.new()
    remap_sprite.name = "Remap"
    remap_sprite.sprite_frames = bundle.get("remap_frames") as SpriteFrames
    remap_sprite.centered = true
    remap_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    remap_sprite.self_modulate = team_color
    remap_sprite.z_index = 1
    add_child(remap_sprite)
    return true


func configure_layout(target_width: float, ground_y: float = 0.0, extra_offset: Vector2 = Vector2.ZERO) -> void:
    var width: float = maxf(1.0, float(content_rect.size.x))
    var scale_value: float = target_width / width
    _layout_scale = Vector2.ONE * scale_value
    scale = _layout_scale
    var content_center_x: float = float(content_rect.position.x) + float(content_rect.size.x) * 0.5
    var content_bottom_y: float = float(content_rect.position.y + content_rect.size.y)
    _layout_position = Vector2(
        -(content_center_x - canvas_size.x * 0.5) * scale_value,
        ground_y - (content_bottom_y - canvas_size.y * 0.5) * scale_value
    ) + extra_offset
    position = _layout_position


func set_terrain_pose(
    ground_height: float,
    slope_gradient: Vector2 = Vector2.ZERO,
    airborne_height: float = 0.0,
    airborne_roll: float = 0.0
) -> void:
    _terrain_ground_height = maxf(0.0, ground_height)
    _terrain_airborne_height = maxf(0.0, airborne_height)
    position = _layout_position + Vector2(0.0, -_terrain_ground_height - _terrain_airborne_height)
    rotation = clampf(-slope_gradient.x * 0.18 + airborne_roll, -0.48, 0.48)
    skew = clampf(slope_gradient.y * 0.12, -0.20, 0.20)


func play_state(state_name: String, direction: int = 0, restart: bool = false) -> void:
    current_state = state_name
    current_direction = posmod(direction, 8)
    var manifest_animation: String = _resolve_animation(state_name)
    if manifest_animation.is_empty():
        return
    var definition: Dictionary = animations.get(manifest_animation, {}) as Dictionary
    var runtime_name: String = manifest_animation
    if bool(definition.get("directional", false)):
        runtime_name = "%s_%d" % [manifest_animation, current_direction]
    if base_sprite.sprite_frames == null or not base_sprite.sprite_frames.has_animation(runtime_name):
        return
    if restart or current_animation != runtime_name:
        base_sprite.play(runtime_name)
        remap_sprite.play(runtime_name)
        current_animation = runtime_name


func set_progress(state_name: String, progress: float, direction: int = 0) -> void:
    current_state = state_name
    current_direction = posmod(direction, 8)
    var manifest_animation: String = _resolve_animation(state_name)
    if manifest_animation.is_empty():
        return
    var definition: Dictionary = animations.get(manifest_animation, {}) as Dictionary
    var runtime_name: String = manifest_animation
    if bool(definition.get("directional", false)):
        runtime_name = "%s_%d" % [manifest_animation, current_direction]
    if base_sprite.sprite_frames == null or not base_sprite.sprite_frames.has_animation(runtime_name):
        return
    if current_animation != runtime_name:
        base_sprite.play(runtime_name)
        remap_sprite.play(runtime_name)
        current_animation = runtime_name
    base_sprite.pause()
    remap_sprite.pause()
    var frame_count: int = base_sprite.sprite_frames.get_frame_count(runtime_name)
    if frame_count <= 0:
        return
    var frame_index: int = clampi(
        int(round(clampf(progress, 0.0, 1.0) * float(frame_count - 1))),
        0,
        frame_count - 1
    )
    base_sprite.frame = frame_index
    remap_sprite.frame = frame_index


func set_team_color(color: Color) -> void:
    if is_instance_valid(remap_sprite):
        remap_sprite.self_modulate = color


func set_alpha(value: float) -> void:
    var alpha: float = clampf(value, 0.0, 1.0)
    if is_instance_valid(base_sprite):
        base_sprite.modulate.a = alpha
    if is_instance_valid(remap_sprite):
        remap_sprite.modulate.a = alpha


func has_state(state_name: String) -> bool:
    return not _resolve_animation(state_name).is_empty()


func visual_top_y() -> float:
    return position.y + (float(content_rect.position.y) - canvas_size.y * 0.5) * scale.y


func _resolve_animation(state_name: String) -> String:
    var candidates: Array[String] = []
    match state_name:
        "stand":
            candidates = ["Stand", "Ready", "Guard", "HVA", "Walk", "Operational", "__body_normal"]
        "idle":
            candidates = ["Idle1", "Idle2", "Ready", "Guard", "Stand", "HVA", "Walk", "Operational"]
        "move":
            candidates = ["Walk", "HVA", "Stand", "Ready"]
        "attack":
            candidates = ["Fire", "FireUp", "DeployedFire", "HVA", "Stand", "Ready", "__body_normal"]
        "deploy":
            candidates = ["Deploy", "Deployed", "Ready", "Guard"]
        "deployed":
            candidates = ["Deployed", "Deploy", "Ready", "Guard"]
        "deployed_attack":
            candidates = ["DeployedFire", "FireUp", "Deployed", "Ready"]
        "undeploy":
            candidates = ["Deploy", "Ready", "Guard"]
        "harvest":
            candidates = ["SpecialAnim", "Walk", "HVA", "Stand", "Ready"]
        "death":
            candidates = ["Die1", "Die2", "__body_rubble", "__body_damaged"]
        "construction":
            candidates = ["Buildup"]
        "normal":
            candidates = ["Operational", "Ready", "__body_normal"]
        "damaged":
            candidates = ["DamagedOperational", "DamagedReady", "__body_damaged", "Operational", "Ready"]
        "destroyed":
            candidates = ["__body_rubble", "DamagedReady", "__body_damaged"]
        "production":
            candidates = ["ProductionAnim", "DeployingAnim", "Operational", "Ready", "__body_normal"]
        "special":
            candidates = ["SpecialAnim", "SpecialAnimTwo", "SpecialAnimThree", "Operational", "Ready", "__body_normal"]
        "repair":
            candidates = ["SpecialAnim", "SpecialAnimTwo", "SpecialAnimThree", "Operational", "Ready", "__body_normal"]
        "powered_off":
            candidates = ["Ready", "__body_normal", "Operational"]
        _:
            candidates = [state_name]
    for candidate: String in candidates:
        if animations.has(candidate):
            return candidate
        if candidate.begins_with("__body_"):
            if base_sprite != null and base_sprite.sprite_frames != null:
                if base_sprite.sprite_frames.has_animation(candidate):
                    return candidate
    return ""

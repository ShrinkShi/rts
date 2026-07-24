extends Button

const SpriteSheetFactory = preload("res://scripts/game/sprite_sheet_factory.gd")

signal preview_requested(kind, id_value, data)
signal preview_cleared

var kind = "unit"
var id_value = ""
var data = {}
var status_text = ""
var progress = 0.0
var queue_count = 0

func setup(next_kind, next_id, next_data):
    kind = next_kind
    id_value = next_id
    data = next_data
    text = ""
    flat = true
    focus_mode = Control.FOCUS_NONE
    texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    custom_minimum_size = Vector2(54, 56)
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    mouse_entered.connect(func(): preview_requested.emit(kind, id_value, data))
    mouse_exited.connect(func(): preview_cleared.emit())
    queue_redraw()

func set_runtime_state(next_status, next_progress = 0.0, next_count = 0):
    status_text = str(next_status)
    progress = clamp(float(next_progress), 0.0, 1.0)
    queue_count = int(next_count)
    queue_redraw()

func _draw():
    var bg = Color("#1A2830") if not disabled else Color("#10171B")
    var border = Color("#78A5B8") if is_hovered() and not disabled else Color("#354B55")
    draw_rect(Rect2(Vector2.ZERO, size), bg)
    draw_rect(Rect2(Vector2.ZERO, size), border, false, 1.2)
    var icon_rect = Rect2(Vector2(3, 3), Vector2(size.x - 6, size.y - 18))
    draw_rect(icon_rect, Color("#22343D"))
    _draw_icon(icon_rect)
    var name_bar = Rect2(Vector2(1, size.y - 16), Vector2(size.x - 2, 15))
    draw_rect(name_bar, Color(0.03, 0.055, 0.065, 0.96))
    var name_color = Color("#E7F0F3") if not disabled else Color("#68777D")
    draw_string(ThemeDB.fallback_font, Vector2(2, size.y - 4), str(data.get("name", id_value)), HORIZONTAL_ALIGNMENT_CENTER, size.x - 4, 8, name_color)
    draw_string(ThemeDB.fallback_font, Vector2(4, 12), "$%d" % int(data.get("cost", 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color("#E2C75E"))
    if queue_count > 0:
        draw_circle(Vector2(size.x - 9, 9), 7, Color("#152129"))
        draw_string(ThemeDB.fallback_font, Vector2(size.x - 16, 12), str(queue_count), HORIZONTAL_ALIGNMENT_CENTER, 14, 9, Color("#EAF3F5"))
    if progress > 0.0:
        draw_rect(Rect2(Vector2(2, size.y - 20), Vector2((size.x - 4) * progress, 2)), Color("#67CBE8"))
    if status_text != "":
        draw_rect(icon_rect, Color(0.05, 0.08, 0.09, 0.78))
        draw_string(ThemeDB.fallback_font, Vector2(icon_rect.position.x, icon_rect.get_center().y + 4), status_text, HORIZONTAL_ALIGNMENT_CENTER, icon_rect.size.x, 10, Color("#F0D269"))

func _fit_texture_rect(source_size, rect, scale_multiplier = 1.0, offset = Vector2.ZERO):
    var inset = rect.grow(-2.0)
    var scale_factor = min(inset.size.x / source_size.x, inset.size.y / source_size.y) * float(scale_multiplier)
    var target_size = source_size * scale_factor
    return Rect2(inset.get_center() - target_size * 0.5 + Vector2(offset), target_size)

func _draw_texture_layer(texture, source_size, rect, scale_multiplier = 1.0, offset = Vector2.ZERO):
    if texture == null:
        return Rect2()
    var target_rect = _fit_texture_rect(source_size, rect, scale_multiplier, offset)
    draw_texture_rect(texture, target_rect, false, Color("#D2E1E6"))
    return target_rect

func _draw_icon(rect):
    # Composite icons mirror the actual runtime hierarchy. Tanks show chassis +
    # independent turret; defensive buildings show fixed base + rotating weapon.
    if kind == "unit" and id_value == "tank":
        var chassis_frames = SpriteSheetFactory.get_tank_chassis_frames()
        var turret_frames = SpriteSheetFactory.get_tank_turret_frames()
        var chassis = chassis_frames.get_frame_texture("stand_2", 0) if chassis_frames != null else null
        var turret = turret_frames.get_frame_texture("stand_2", 0) if turret_frames != null else null
        var frame_size = SpriteSheetFactory.get_unit_frame_size("tank")
        var target_rect = _draw_texture_layer(chassis, frame_size, rect)
        if turret != null and target_rect.size.x > 0.0:
            draw_texture_rect(turret, target_rect, false, Color("#D2E1E6"))
        return

    if kind == "structure" and id_value in ["turret", "bunker"]:
        var base = SpriteSheetFactory.get_building_frame(id_value, 0)
        var base_size = SpriteSheetFactory.get_building_frame_size(id_value)
        var base_rect = _draw_texture_layer(base, base_size, rect)
        var head_frames = SpriteSheetFactory.get_defense_head_frames(id_value)
        var head = head_frames.get_frame_texture("stand_2", 0) if head_frames != null else null
        if head != null and base_rect.size.x > 0.0:
            var head_size = SpriteSheetFactory.get_defense_head_frame_size(id_value)
            var width_ratio = 0.88 if id_value == "bunker" else 0.80
            var head_width = base_rect.size.x * width_ratio
            var head_height = head_width * head_size.y / head_size.x
            var head_center = base_rect.get_center() + Vector2(0, -base_rect.size.y * (0.08 if id_value == "bunker" else 0.11))
            var head_rect = Rect2(head_center - Vector2(head_width, head_height) * 0.5, Vector2(head_width, head_height))
            draw_texture_rect(head, head_rect, false, Color("#D2E1E6"))
        return

    var texture = null
    var source_size = Vector2(96, 96)
    if kind == "structure":
        texture = SpriteSheetFactory.get_building_frame(id_value, 0)
        source_size = SpriteSheetFactory.get_building_frame_size(id_value)
    elif GameConfig.units.has(id_value):
        source_size = SpriteSheetFactory.get_unit_frame_size(id_value)
        var frames = SpriteSheetFactory.get_unit_frames(id_value)
        if frames != null and frames.has_animation("stand_1") and frames.get_frame_count("stand_1") > 0:
            texture = frames.get_frame_texture("stand_1", 0)
    if texture != null:
        _draw_texture_layer(texture, source_size, rect)
        return
    var center = rect.get_center()
    draw_circle(center, min(rect.size.x, rect.size.y) * 0.25, Color("#6AA9C1"))

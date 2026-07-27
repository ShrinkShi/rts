extends Control

const SpriteSheetFactory = preload("res://scripts/game/sprite_sheet_factory.gd")

var entity
var entity_id = ""
var team_color = Color("#6CA8C4")
var ra2_base_texture: Texture2D
var ra2_mask_texture: Texture2D
var ra2_source_size: Vector2 = Vector2.ZERO

func _ready():
    if custom_minimum_size == Vector2.ZERO:
        custom_minimum_size = Vector2(136, 154)
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

func set_entity(next_entity):
    entity = next_entity
    entity_id = ""
    ra2_base_texture = null
    ra2_mask_texture = null
    ra2_source_size = Vector2.ZERO
    if is_instance_valid(entity):
        if entity.has_method("is_tree_entity") and entity.is_tree_entity():
            entity_id = "tree_dense" if bool(entity.dense) else "tree_sparse"
            team_color = Color("#557D43")
        elif entity.has_method("is_resource_entity") and entity.is_resource_entity():
            entity_id = "ore_resource"
            team_color = Color("#D6B94B")
        else:
            entity_id = str(entity.unit_id) if entity.has_method("is_combat_unit") else str(entity.building_id)
            team_color = entity.team_color
            _load_ra2_portrait()
    queue_redraw()

func _load_ra2_portrait() -> void:
    if not is_instance_valid(entity):
        return
    var ra2_id: String = str(entity.get("ra2_entity_id")).to_upper()
    if ra2_id.is_empty():
        return
    var bundle: Dictionary = RA2RuntimeDatabase.get_visual_bundle(ra2_id, "temperate")
    if bundle.is_empty():
        return
    var base_frames: SpriteFrames = bundle.get("base_frames") as SpriteFrames
    var remap_frames: SpriteFrames = bundle.get("remap_frames") as SpriteFrames
    if base_frames == null:
        return
    var candidates: Array[String] = []
    if entity.has_method("is_combat_unit"):
        candidates = ["Stand_1", "Ready_1", "Guard_1", "HVA_1", "Walk_1", "Stand_0", "Ready_0"]
    else:
        candidates = ["Operational", "Ready", "__body_normal"]
    var animation_name: String = ""
    for candidate: String in candidates:
        if base_frames.has_animation(candidate) and base_frames.get_frame_count(candidate) > 0:
            animation_name = candidate
            break
    if animation_name.is_empty():
        return
    ra2_base_texture = base_frames.get_frame_texture(animation_name, 0)
    if remap_frames != null and remap_frames.has_animation(animation_name):
        if remap_frames.get_frame_count(animation_name) > 0:
            ra2_mask_texture = remap_frames.get_frame_texture(animation_name, 0)
    if ra2_base_texture != null:
        ra2_source_size = ra2_base_texture.get_size()

func _draw():
    draw_rect(Rect2(Vector2.ZERO, size), Color("#0E171D"))
    draw_rect(Rect2(Vector2(4, 4), size - Vector2(8, 8)), Color("#18272F"))
    draw_rect(Rect2(Vector2(4, 4), size - Vector2(8, 8)), Color("#526B76"), false, 2.0)
    var center = Vector2(size.x * 0.5, size.y * 0.48)
    var scale_value = min(size.x, size.y) / 92.0
    if entity_id == "":
        draw_circle(center, 28 * scale_value, Color("#263740"))
        draw_string(ThemeDB.fallback_font, Vector2(0, size.y * 0.82), "未选择", HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, Color("#8FA3AD"))
        return
    _draw_entity_icon(center, scale_value)
    draw_string(ThemeDB.fallback_font, Vector2(0, size.y - 14), _display_name(), HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, Color("#E7F0F3"))

func _display_name():
    if entity_id == "ore_resource":
        return "矿石资源"
    if entity_id.begins_with("tree_"):
        return "茂密树林" if entity_id == "tree_dense" else "稀疏树木"
    if is_instance_valid(entity):
        var entity_stats: Variant = entity.get("stats")
        if entity_stats is Dictionary:
            var runtime_name: String = str((entity_stats as Dictionary).get("name", ""))
            if not runtime_name.is_empty():
                return runtime_name
    if GameConfig.units.has(entity_id):
        return str(GameConfig.units[entity_id].get("name", entity_id))
    return str(GameConfig.buildings.get(entity_id, {}).get("name", entity_id))

func _draw_entity_icon(center, s):
    if ra2_base_texture != null and ra2_source_size.x > 0.0 and ra2_source_size.y > 0.0:
        var max_size: Vector2 = Vector2(size.x * 0.78, size.y * 0.62)
        var scale_factor: float = minf(max_size.x / ra2_source_size.x, max_size.y / ra2_source_size.y)
        var target_size: Vector2 = ra2_source_size * scale_factor
        var target_rect: Rect2 = Rect2(center - target_size * 0.5 + Vector2(0, 3), target_size)
        draw_texture_rect(ra2_base_texture, target_rect, false, Color.WHITE)
        if ra2_mask_texture != null:
            draw_texture_rect(ra2_mask_texture, target_rect, false, team_color)
        return
    if entity_id.begins_with("tree_"):
        var dense = entity_id == "tree_dense"
        draw_rect(Rect2(center + Vector2(-3, -6) * s, Vector2(6, 36) * s), Color("#5A3E29"))
        var leaf = Color("#3F6D39") if dense else Color("#5B8247")
        for offset in [Vector2(-18, -18), Vector2(0, -30), Vector2(18, -18), Vector2(0, -8)]:
            draw_circle(center + offset * s, (18 if dense else 14) * s, leaf)
        return
    if entity_id == "ore_resource":
        draw_circle(center + Vector2(-18, 8) * s, 18 * s, Color("#9F8430"))
        draw_circle(center + Vector2(10, 3) * s, 23 * s, Color("#C7A83E"))
        draw_circle(center + Vector2(0, -20) * s, 15 * s, Color("#E3CB68"))
        if is_instance_valid(entity):
            draw_string(ThemeDB.fallback_font, center + Vector2(-42, 45) * s, "%d" % entity.get_remaining(), HORIZONTAL_ALIGNMENT_CENTER, 84 * s, int(13 * s), Color("#F2DB75"))
        return
    var texture = null
    var source_size = Vector2(96, 96)
    if GameConfig.units.has(entity_id):
        source_size = SpriteSheetFactory.get_unit_frame_size(entity_id)
        var frames = SpriteSheetFactory.get_unit_frames(entity_id)
        if frames != null and frames.has_animation("stand_1") and frames.get_frame_count("stand_1") > 0:
            texture = frames.get_frame_texture("stand_1", 0)
    elif GameConfig.buildings.has(entity_id):
        texture = SpriteSheetFactory.get_building_frame(entity_id, 0)
        source_size = SpriteSheetFactory.get_building_frame_size(entity_id)
    if texture == null:
        draw_circle(center, 24 * s, team_color)
        return
    var max_size = Vector2(size.x * 0.78, size.y * 0.62)
    var scale_factor = min(max_size.x / source_size.x, max_size.y / source_size.y)
    var target_size = source_size * scale_factor
    var target_rect = Rect2(center - target_size * 0.5 + Vector2(0, 3), target_size)
    draw_texture_rect(texture, target_rect, false, team_color.lerp(Color.WHITE, 0.72))

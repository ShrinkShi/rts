extends Node2D

const RA2_TEMPERATE_ATLAS_PATH := "res://assets/ra2_terrain/temperate_atlas.png"
const ORE_ATLAS_FIRST_INDEX := 24
const ORE_VARIANT_COUNT := 8

var match_ref
var map_ref
var cell = Vector2i.ZERO
var owner_id = -1
var resource_id = "ore"
var hp = INF
var max_hp = INF
var selected = false
var hover_state = ""
var max_remaining = 1800
var team_color = Color("#D6B94B")
var ra2_ore_texture: AtlasTexture
var stats = {
    "name": "矿石",
    "resource_type": "矿石资源",
    "armor": 0,
    "armor_type": "无敌资源",
    "description": "每个矿石格都是独立资源单位。采矿车会持续消耗其储量，储量归零后无法继续采集。"
}


func setup(next_match, next_map, next_cell) -> void:
    match_ref = next_match
    map_ref = next_map
    cell = next_cell
    global_position = map_ref.cell_to_world(cell)
    max_remaining = max(1, int(map_ref.get_ore_capacity(cell)))

    # v0.15 accidentally placed every ore entity at z=-2. The terrain TileMapLayer
    # therefore covered the complete resource entity, while harvesting continued in
    # the data model. Keep ore in the y-sorted entity layer at the normal z level.
    z_index = 0
    _build_ra2_ore_texture()

    if not map_ref.ore_changed.is_connected(_on_ore_changed):
        map_ref.ore_changed.connect(_on_ore_changed)
    queue_redraw()


func _exit_tree() -> void:
    if is_instance_valid(map_ref) and map_ref.ore_changed.is_connected(_on_ore_changed):
        map_ref.ore_changed.disconnect(_on_ore_changed)


func _build_ra2_ore_texture() -> void:
    ra2_ore_texture = null
    if not ResourceLoader.exists(RA2_TEMPERATE_ATLAS_PATH):
        return
    var atlas: Texture2D = load(RA2_TEMPERATE_ATLAS_PATH) as Texture2D
    if atlas == null:
        return

    var variant: int = posmod(cell.x * 17 + cell.y * 31, ORE_VARIANT_COUNT)
    var atlas_index: int = ORE_ATLAS_FIRST_INDEX + variant
    var tile_size: int = int(map_ref.tile_px)
    ra2_ore_texture = AtlasTexture.new()
    ra2_ore_texture.atlas = atlas
    ra2_ore_texture.region = Rect2(
        float(atlas_index * tile_size),
        0.0,
        float(tile_size),
        float(tile_size)
    )
    ra2_ore_texture.filter_clip = true


func _on_ore_changed(changed_cell: Vector2i, _remaining: int) -> void:
    if changed_cell == cell:
        queue_redraw()


func is_resource_entity() -> bool:
    return true


func is_depleted() -> bool:
    return get_remaining() <= 0


func get_remaining() -> int:
    if not is_instance_valid(map_ref):
        return 0
    return int(map_ref.get_ore_amount(cell))


func get_selection_rect() -> Rect2:
    if not is_instance_valid(map_ref):
        return Rect2(global_position - Vector2(16, 16), Vector2(32, 32))
    var size_value := Vector2(map_ref.tile_px, map_ref.tile_px)
    return Rect2(global_position - size_value * 0.5, size_value)


func set_selected(value: bool) -> void:
    selected = value
    queue_redraw()


func set_hover_state(value: String) -> void:
    if hover_state == value:
        return
    hover_state = value
    queue_redraw()


func get_sight_radius_cells() -> int:
    return 0


func take_damage(_amount, _source = null) -> float:
    # 资源单位无敌，不参与战斗伤害结算。
    return 0.0


func _draw() -> void:
    if not is_instance_valid(map_ref):
        return

    var half: float = map_ref.tile_px * 0.5 - 3.0
    var remaining: int = get_remaining()
    var ratio: float = clamp(
        float(remaining) / float(max_remaining),
        0.0,
        1.0
    )

    if remaining > 0:
        if ra2_ore_texture != null:
            # Preserve the RA2-derived ore pixel texture while making depletion
            # readable: low deposits shrink towards the cell centre.
            var visual_scale: float = lerp(0.72, 1.0, ratio)
            var size_value := Vector2(map_ref.tile_px, map_ref.tile_px) * visual_scale
            draw_texture_rect(
                ra2_ore_texture,
                Rect2(-size_value * 0.5, size_value),
                false
            )
        else:
            _draw_fallback_ore(ratio)

    if selected or hover_state != "":
        var color := Color("#75E6FF") if selected else Color("#E6CB64")
        draw_rect(
            Rect2(Vector2(-half, -half), Vector2(half * 2.0, half * 2.0)),
            color,
            false,
            2.0
        )

    if selected:
        var label := "%d" % remaining
        draw_string_outline(
            ThemeDB.fallback_font,
            Vector2(-half, -half - 5),
            label,
            HORIZONTAL_ALIGNMENT_CENTER,
            half * 2.0,
            11,
            2,
            Color.BLACK
        )
        draw_string(
            ThemeDB.fallback_font,
            Vector2(-half, -half - 5),
            label,
            HORIZONTAL_ALIGNMENT_CENTER,
            half * 2.0,
            11,
            Color("#F1D66A")
        )


func _draw_fallback_ore(ratio: float) -> void:
    var base := Color("#C7A83E")
    var dark := base.darkened(0.28)
    var nugget_scale: float = lerp(0.52, 1.0, ratio)
    draw_circle(Vector2(-7, 4) * nugget_scale, 7.0 * nugget_scale, dark)
    draw_circle(Vector2(5, 1) * nugget_scale, 8.0 * nugget_scale, base)
    draw_circle(
        Vector2(1, -7) * nugget_scale,
        5.5 * nugget_scale,
        base.lightened(0.18)
    )

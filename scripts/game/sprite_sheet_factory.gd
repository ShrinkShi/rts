extends RefCounted

const UNIT_FRAME_SIZE = Vector2(96, 96)
const UNIT_DIRECTION_COUNT = 8
# AI atlases are stored as N,NW,W,SW,S,SE,E,NE for direct inspection.
# Engine direction indices are E,SE,S,SW,W,NW,N,NE.
const AI_ATLAS_COLUMN_BY_ENGINE_DIRECTION = [6, 5, 4, 3, 2, 1, 0, 7]
const UNIT_LAYOUT = {
    "stand": {"row": 0, "count": 1, "fps": 1.0, "loop": true},
    "idle": {"row": 0, "count": 2, "fps": 2.0, "loop": true},
    "move": {"row": 2, "count": 4, "fps": 8.0, "loop": true},
    "attack": {"row": 6, "count": 3, "fps": 12.0, "loop": false},
    "death": {"row": 9, "count": 6, "fps": 8.0, "loop": false}
}

const AI_UNIT_FRAME_SIZES = {
    "rifle": Vector2(128, 128),
    "tank_chassis": Vector2(224, 192),
    "tank_turret": Vector2(224, 192),
    "tank_death": Vector2(224, 192)
}
const AI_BUILDING_FRAME_SIZE = Vector2(256, 224)
const AI_BUILDINGS = ["power", "barracks", "refinery", "turret", "bunker"]

static var _unit_frame_cache = {}
static var _special_frame_cache = {}
static var _building_texture_cache = {}
static var _building_frame_cache = {}
static var _shader = null

static func _atlas_frame(texture, frame_size, column, row):
    var frame_texture = AtlasTexture.new()
    frame_texture.atlas = texture
    frame_texture.region = Rect2(Vector2(column, row) * frame_size, frame_size)
    frame_texture.filter_clip = true
    return frame_texture

static func _new_frames():
    var frames = SpriteFrames.new()
    if frames.has_animation("default"):
        frames.remove_animation("default")
    return frames

static func _add_animation(frames, name, textures, fps = 6.0, loop = true):
    frames.add_animation(name)
    frames.set_animation_speed(name, fps)
    frames.set_animation_loop_mode(name, SpriteFrames.LOOP_LINEAR if loop else SpriteFrames.LOOP_NONE)
    for texture in textures:
        frames.add_frame(name, texture)

static func get_unit_frame_size(unit_id):
    if unit_id == "rifle":
        return AI_UNIT_FRAME_SIZES.rifle
    if unit_id == "tank":
        return AI_UNIT_FRAME_SIZES.tank_chassis
    return UNIT_FRAME_SIZE

static func get_building_frame_size(building_id):
    return AI_BUILDING_FRAME_SIZE if building_id in AI_BUILDINGS else Vector2(192, 160)

static func create_team_material(team_color):
    if _shader == null:
        _shader = load("res://shaders/team_tint.gdshader")
    var material = ShaderMaterial.new()
    material.shader = _shader
    material.set_shader_parameter("team_color", team_color)
    return material

static func get_unit_frames(unit_id):
    if unit_id == "rifle":
        return _get_ai_rifle_frames()
    if unit_id == "tank":
        return get_tank_chassis_frames()
    if _unit_frame_cache.has(unit_id):
        return _unit_frame_cache[unit_id]
    var path = "res://assets/generated/units/%s.png" % unit_id
    var atlas_texture = load(path)
    if atlas_texture == null:
        push_error("Missing generated unit sprite sheet: " + path)
        return SpriteFrames.new()
    var frames = _new_frames()
    for state_name in UNIT_LAYOUT:
        var layout = UNIT_LAYOUT[state_name]
        for direction in range(UNIT_DIRECTION_COUNT):
            var textures = []
            for frame_index in range(int(layout.get("count", 1))):
                textures.append(_atlas_frame(atlas_texture, UNIT_FRAME_SIZE, direction, int(layout.get("row", 0)) + frame_index))
            _add_animation(frames, "%s_%d" % [state_name, direction], textures, float(layout.get("fps", 6.0)), bool(layout.get("loop", true)))
    _unit_frame_cache[unit_id] = frames
    return frames

static func _get_ai_rifle_frames():
    var key = "ai_rifle"
    if _special_frame_cache.has(key):
        return _special_frame_cache[key]
    var texture = load("res://assets/ai_generated/units/rifle.png")
    var frame_size = AI_UNIT_FRAME_SIZES.rifle
    var frames = _new_frames()
    for direction in range(8):
        var column = int(AI_ATLAS_COLUMN_BY_ENGINE_DIRECTION[direction])
        _add_animation(frames, "stand_%d" % direction, [_atlas_frame(texture, frame_size, column, 0)], 1.0, true)
        _add_animation(frames, "idle_%d" % direction, [_atlas_frame(texture, frame_size, column, 0)], 1.0, true)
        _add_animation(frames, "move_%d" % direction, [
            _atlas_frame(texture, frame_size, column, 1),
            _atlas_frame(texture, frame_size, column, 2)
        ], 7.0, true)
        _add_animation(frames, "attack_%d" % direction, [_atlas_frame(texture, frame_size, column, 3)], 7.0, false)
        _add_animation(frames, "death_%d" % direction, [_atlas_frame(texture, frame_size, column, 4)], 1.0, false)
    _special_frame_cache[key] = frames
    return frames

static func get_tank_chassis_frames():
    var key = "tank_chassis"
    if _special_frame_cache.has(key):
        return _special_frame_cache[key]
    var texture = load("res://assets/ai_generated/units/tank_chassis.png")
    var death_texture = load("res://assets/ai_generated/units/tank_death.png")
    var frame_size = AI_UNIT_FRAME_SIZES.tank_chassis
    var frames = _new_frames()
    for direction in range(8):
        var column = int(AI_ATLAS_COLUMN_BY_ENGINE_DIRECTION[direction])
        var idle = _atlas_frame(texture, frame_size, column, 0)
        _add_animation(frames, "stand_%d" % direction, [idle], 1.0, true)
        _add_animation(frames, "idle_%d" % direction, [idle], 1.0, true)
        _add_animation(frames, "move_%d" % direction, [
            _atlas_frame(texture, frame_size, column, 1),
            _atlas_frame(texture, frame_size, column, 2)
        ], 6.5, true)
        _add_animation(frames, "attack_%d" % direction, [idle], 1.0, true)
        _add_animation(frames, "death_%d" % direction, [_atlas_frame(death_texture, frame_size, column, 0)], 1.0, false)
    _special_frame_cache[key] = frames
    return frames

static func get_tank_turret_frames():
    var key = "tank_turret"
    if _special_frame_cache.has(key):
        return _special_frame_cache[key]
    var texture = load("res://assets/ai_generated/units/tank_turret.png")
    var frame_size = AI_UNIT_FRAME_SIZES.tank_turret
    var frames = _new_frames()
    for direction in range(8):
        var column = int(AI_ATLAS_COLUMN_BY_ENGINE_DIRECTION[direction])
        var idle = _atlas_frame(texture, frame_size, column, 0)
        var firing = _atlas_frame(texture, frame_size, column, 1)
        _add_animation(frames, "stand_%d" % direction, [idle], 1.0, true)
        _add_animation(frames, "attack_%d" % direction, [firing, idle], 12.0, false)
    _special_frame_cache[key] = frames
    return frames

static func get_defense_head_frames(building_id):
    var key = "defense_head:" + building_id
    if _special_frame_cache.has(key):
        return _special_frame_cache[key]
    var bunker = building_id == "bunker"
    var path = "res://assets/ai_generated/buildings/%s.png" % ("bunker_head" if bunker else "turret_head")
    var frame_size = Vector2(160, 144) if bunker else Vector2(192, 160)
    var texture = load(path)
    var frames = _new_frames()
    for direction in range(8):
        var column = int(AI_ATLAS_COLUMN_BY_ENGINE_DIRECTION[direction])
        var idle = _atlas_frame(texture, frame_size, column, 0)
        var firing = _atlas_frame(texture, frame_size, column, 1)
        _add_animation(frames, "stand_%d" % direction, [idle], 1.0, true)
        _add_animation(frames, "attack_%d" % direction, [firing, idle], 13.0, false)
    _special_frame_cache[key] = frames
    return frames

static func get_defense_head_frame_size(building_id):
    return Vector2(160, 144) if building_id == "bunker" else Vector2(192, 160)

static func _ai_building_path(building_id):
    if building_id == "turret":
        return "res://assets/ai_generated/buildings/turret_base.png"
    if building_id == "bunker":
        return "res://assets/ai_generated/buildings/bunker_base.png"
    return "res://assets/ai_generated/buildings/%s.png" % building_id

static func get_building_texture(building_id):
    if _building_texture_cache.has(building_id):
        return _building_texture_cache[building_id]
    var path = _ai_building_path(building_id) if building_id in AI_BUILDINGS else "res://assets/generated/buildings/%s.png" % building_id
    var texture = load(path)
    if texture == null:
        push_error("Missing building sprite sheet: " + path)
    _building_texture_cache[building_id] = texture
    return texture

static func has_ai_construction_frames(building_id):
    return building_id in AI_BUILDINGS

static func _ai_frame_index(building_id, kind, progress = 1.0):
    if kind == "construction":
        var count = 5 if building_id in ["power", "barracks", "refinery"] else 3
        return clamp(int(floor(clamp(progress, 0.0, 0.9999) * count)), 0, count - 1)
    if building_id in ["power", "barracks"]:
        return {"healthy": 5, "damage_1": 6, "damage_2": 7, "destroyed": 8}.get(kind, 5)
    if building_id == "refinery":
        return {"healthy": 5, "unload_1": 6, "unload_2": 7, "damage_1": 8, "damage_2": 9, "destroyed": 10}.get(kind, 5)
    return {"healthy": 2, "damage_1": 4, "damage_2": 5, "destroyed": 6, "inactive": 7, "repair": 8}.get(kind, 2)

static func _ai_grid_columns(building_id):
    return 4 if building_id == "refinery" else 3

static func get_building_construction_frame(building_id, progress):
    if not has_ai_construction_frames(building_id):
        return get_building_frame(building_id, 0)
    var index = _ai_frame_index(building_id, "construction", progress)
    var cols = _ai_grid_columns(building_id)
    return _atlas_frame(get_building_texture(building_id), AI_BUILDING_FRAME_SIZE, index % cols, int(index / cols))

static func get_building_frame(building_id, damage_stage = 0):
    var key = "%s:%d" % [building_id, clamp(int(damage_stage), 0, 2)]
    if _building_frame_cache.has(key):
        return _building_frame_cache[key]
    var atlas_texture = get_building_texture(building_id)
    if atlas_texture == null:
        return null
    var frame_texture
    if building_id in AI_BUILDINGS:
        var kind = "healthy" if int(damage_stage) == 0 else ("damage_1" if int(damage_stage) == 1 else "damage_2")
        var index = _ai_frame_index(building_id, kind)
        var cols = _ai_grid_columns(building_id)
        frame_texture = _atlas_frame(atlas_texture, AI_BUILDING_FRAME_SIZE, index % cols, int(index / cols))
    else:
        frame_texture = _atlas_frame(atlas_texture, Vector2(192, 160), clamp(int(damage_stage), 0, 2), 0)
    _building_frame_cache[key] = frame_texture
    return frame_texture

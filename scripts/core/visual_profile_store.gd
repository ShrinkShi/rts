extends RefCounted

const EntityVisualProfileScript = preload("res://scripts/core/entity_visual_profile.gd")

static var _cache := {}

static func get_profile(entity_id):
    var key := str(entity_id)
    if _cache.has(key):
        return _cache[key]
    var path := "res://resources/visual_profiles/%s.tres" % key
    var profile = ResourceLoader.load(path) if ResourceLoader.exists(path) else null
    if profile == null:
        profile = EntityVisualProfileScript.new()
    _cache[key] = profile
    return profile

static func clear_cache():
    _cache.clear()

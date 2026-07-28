extends RefCounted

const RA2Database = preload("res://scripts/ra2/ra2_database.gd")
const ENTITY_ROOT := "res://data/ra2/entities/"

static var _last_played_ms: Dictionary = {}


static func play_entity_role(entity_id: String, role: String, world_position: Vector2, match_ref, cooldown_ms: int = 100) -> bool:
    var entity: Dictionary = _load_entity(entity_id)
    var sounds: Dictionary = entity.get("sounds", {})
    var events: Array = _as_array(sounds.get(role, []))
    if events.is_empty():
        return false
    return _play_spatial_with_cooldown(
        "%s:%s" % [entity_id.to_upper(), role],
        str(events[0]),
        world_position,
        match_ref,
        cooldown_ms
    )


static func play_weapon_report(entity_id: String, world_position: Vector2, match_ref, cooldown_ms: int = 70) -> bool:
    var entity: Dictionary = _load_entity(entity_id)
    var weapons: Dictionary = entity.get("weapons", {})
    for slot: String in ["Primary", "Weapon1", "Secondary", "Weapon2", "ElitePrimary", "EliteSecondary"]:
        var weapon_variant: Variant = weapons.get(slot)
        if not weapon_variant is Dictionary:
            continue
        var reports: Array = _as_array((weapon_variant as Dictionary).get("report", []))
        if reports.is_empty():
            continue
        return _play_spatial_with_cooldown(
            "%s:weapon" % entity_id.to_upper(),
            str(reports[0]),
            world_position,
            match_ref,
            cooldown_ms
        )
    return false


static func _load_entity(entity_id: String) -> Dictionary:
    var normalized_id: String = entity_id.strip_edges().to_lower()
    if normalized_id.is_empty():
        return {}
    var parsed: Variant = RA2Database.load_json(ENTITY_ROOT + normalized_id + ".json", false)
    if parsed is Dictionary:
        return parsed as Dictionary
    return {}


static func _play_spatial_with_cooldown(key: String, event_id: String, world_position: Vector2, match_ref, cooldown_ms: int) -> bool:
    var now: int = Time.get_ticks_msec()
    if now - int(_last_played_ms.get(key, -1000000)) < cooldown_ms:
        return false

    var scene_tree: SceneTree = Engine.get_main_loop() as SceneTree
    if scene_tree == null:
        return false
    var audio_service: Node = scene_tree.root.get_node_or_null("RA2AudioService")
    if audio_service == null or not audio_service.has_method("play_event_spatial"):
        return false
    var played: Variant = audio_service.call("play_event_spatial", event_id, world_position, match_ref)
    if not bool(played):
        return false

    _last_played_ms[key] = now
    return true


static func _as_array(value: Variant) -> Array:
    if value is Array:
        return value as Array
    if value == null:
        return []
    return [value]

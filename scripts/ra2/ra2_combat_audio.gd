extends Node

var _last_played_ms: Dictionary = {}


func play_entity_role(entity_id: String, role: String, world_position: Vector2, match_ref, cooldown_ms: int = 100) -> bool:
    var entity: Dictionary = RA2RuntimeDatabase.load_entity(entity_id)
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


func play_weapon_report(entity_id: String, world_position: Vector2, match_ref, cooldown_ms: int = 70) -> bool:
    var entity: Dictionary = RA2RuntimeDatabase.load_entity(entity_id)
    var weapons: Dictionary = entity.get("weapons", {})
    for slot in ["Primary", "Weapon1", "Secondary", "Weapon2", "ElitePrimary", "EliteSecondary"]:
        var weapon_variant: Variant = weapons.get(slot)
        if not weapon_variant is Dictionary:
            continue
        var reports := _as_array((weapon_variant as Dictionary).get("report", []))
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


func _play_spatial_with_cooldown(key: String, event_id: String, world_position: Vector2, match_ref, cooldown_ms: int) -> bool:
    var now := Time.get_ticks_msec()
    if now - int(_last_played_ms.get(key, -1000000)) < cooldown_ms:
        return false
    if not RA2AudioService.play_event_spatial(event_id, world_position, match_ref):
        return false
    _last_played_ms[key] = now
    return true


func _as_array(value: Variant) -> Array:
    if value is Array:
        return value
    if value == null:
        return []
    return [value]

extends RefCounted

const RA2Database = preload("res://scripts/ra2/ra2_database.gd")
const WARHEADS_PATH := "res://data/ra2/warheads.json"
const ENTITY_ROOT := "res://data/ra2/entities/"
const CELL_PIXELS := 32.0
const ROF_TICKS_PER_SECOND := 30.0

static var _warheads: Dictionary = {}
static var _warheads_loaded := false


static func build_runtime_stats(base_stats: Dictionary, ra2_entity_id: String, generic_category: String) -> Dictionary:
    var result: Dictionary = base_stats.duplicate(true)
    var entity: Dictionary = _load_entity(ra2_entity_id)
    if entity.is_empty():
        _apply_project_armor_model(result, str(result.get("ra2_armor", "")), generic_category)
        return result

    result["ra2_entity_id"] = ra2_entity_id.to_upper()
    result["cost"] = int(entity.get("cost", result.get("cost", 0)))
    result["hp"] = float(entity.get("strength", result.get("hp", 100.0)))
    result["sight"] = int(entity.get("sight", result.get("sight", 6)))
    result["ra2_speed"] = float(entity.get("speed", 0.0))
    if generic_category in ["infantry", "vehicle"]:
        var ra2_speed: float = float(entity.get("speed", 0.0))
        if ra2_speed > 0.0:
            result["speed"] = ra2_speed * 10.0

    var armor_id: String = str(entity.get("armor", "none")).to_lower()
    result["ra2_armor"] = armor_id
    _apply_project_armor_model(result, armor_id, generic_category)
    _apply_primary_weapon(result, entity)
    _apply_building_rules(result, entity, generic_category)
    return result


static func _load_entity(entity_id: String) -> Dictionary:
    var normalized_id: String = entity_id.strip_edges().to_lower()
    if normalized_id.is_empty():
        return {}
    var parsed: Variant = RA2Database.load_json(ENTITY_ROOT + normalized_id + ".json", false)
    if parsed is Dictionary:
        return (parsed as Dictionary).duplicate(true)
    return {}


static func _apply_primary_weapon(result: Dictionary, entity: Dictionary) -> void:
    var weapons: Dictionary = entity.get("weapons", {})
    var weapon: Dictionary = {}
    for slot: String in ["Primary", "Weapon1", "Secondary", "Weapon2"]:
        var candidate: Variant = weapons.get(slot)
        if candidate is Dictionary:
            weapon = candidate as Dictionary
            break
    if weapon.is_empty():
        result["damage"] = 0.0 if not result.has("damage") else result["damage"]
        result["weapon_id"] = ""
        result["warhead_id"] = ""
        result["weapon_name"] = "无"
        result["damage_type"] = "无"
        return

    var values: Dictionary = weapon.get("values", {})
    var weapon_id: String = str(weapon.get("id", ""))
    var warhead_id: String = str(weapon.get("warhead", values.get("Warhead", ""))).to_upper()
    result["weapon_id"] = weapon_id
    result["warhead_id"] = warhead_id
    result["weapon_name"] = weapon_id if not weapon_id.is_empty() else "未命名武器"
    result["damage_type"] = "弹头 %s" % warhead_id if not warhead_id.is_empty() else "未指定弹头"
    result["projectile_id"] = str(weapon.get("projectile", values.get("Projectile", "")))
    result["damage"] = float(values.get("Damage", result.get("damage", 0.0)))

    var rof: float = float(values.get("ROF", 0.0))
    if rof > 0.0:
        result["reload"] = maxf(0.08, rof / ROF_TICKS_PER_SECOND)
    var range_cells: float = float(values.get("Range", 0.0))
    if range_cells > 0.0:
        result["range"] = range_cells * CELL_PIXELS
    var projectile_speed: float = float(values.get("Speed", 0.0))
    if projectile_speed > 0.0:
        result["projectile_speed"] = projectile_speed * 8.0
    result["warhead_verses"] = get_warhead_verses(warhead_id)


static func _apply_building_rules(result: Dictionary, entity: Dictionary, generic_category: String) -> void:
    if generic_category != "building":
        return
    var rules: Dictionary = entity.get("rules", {}).get("values", {})
    var power: int = int(rules.get("Power", 0))
    if power > 0:
        result["power_output"] = power
        result["power_use"] = 0
    elif power < 0:
        result["power_output"] = 0
        result["power_use"] = abs(power)

    var art: Dictionary = entity.get("art", {}).get("values", {})
    var foundation: Vector2i = parse_foundation(art.get("Foundation", ""))
    if foundation != Vector2i.ZERO:
        result["footprint"] = [foundation.x, foundation.y]
        result["foundation"] = "%dx%d" % [foundation.x, foundation.y]


static func parse_foundation(value: Variant) -> Vector2i:
    if value is Array and value.size() >= 2:
        return Vector2i(maxi(1, int(value[0])), maxi(1, int(value[1])))
    var foundation_text: String = str(value).strip_edges().to_lower().replace("×", "x")
    if foundation_text.is_empty():
        return Vector2i.ZERO
    if foundation_text.contains("x"):
        var parts: PackedStringArray = foundation_text.split("x", false)
        if parts.size() >= 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
            return Vector2i(maxi(1, int(parts[0])), maxi(1, int(parts[1])))
    if foundation_text.is_valid_int():
        var square_size: int = maxi(1, int(foundation_text))
        return Vector2i(square_size, square_size)
    return Vector2i.ZERO


static func _apply_project_armor_model(result: Dictionary, armor_id: String, generic_category: String) -> void:
    var armor_class: String = "building"
    if generic_category == "infantry":
        armor_class = "biological"
    elif generic_category in ["vehicle", "aircraft", "air"]:
        armor_class = "mechanical"

    var numeric_armor: float = armor_value_for(armor_id, armor_class)
    result["armor_class"] = armor_class
    result["armor_value"] = numeric_armor
    result["armor_rule_id"] = armor_id
    result["armor"] = 0.0

    var armor_class_name: String = "护甲"
    match armor_class:
        "biological":
            armor_class_name = "生物护甲"
        "mechanical":
            armor_class_name = "机械护甲"
        "building":
            armor_class_name = "建筑护甲"
    result["armor_type"] = "%s（%s，护甲值 %.0f）" % [armor_class_name, armor_id, numeric_armor]


static func armor_value_for(armor_id: String, armor_class: String) -> float:
    var normalized: String = armor_id.to_lower()
    var values: Dictionary = {
        "none": 0.0,
        "flak": 2.0,
        "plate": 4.0,
        "light": 3.0,
        "medium": 6.0,
        "heavy": 9.0,
        "wood": 3.0,
        "steel": 6.0,
        "concrete": 9.0,
        "special_1": 7.0,
        "special_2": 9.0
    }
    if values.has(normalized):
        return float(values[normalized])
    if armor_class == "biological":
        return 2.0
    if armor_class == "mechanical":
        return 6.0
    return 7.0


static func get_warhead_verses(warhead_id: String) -> Array[float]:
    _ensure_warheads_loaded()
    var defaults: Array[float] = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
    var entry: Dictionary = _warheads.get(warhead_id.to_upper(), {})
    if entry.is_empty():
        return defaults
    var raw: String = str(entry.get("values", {}).get("Verses", ""))
    if raw.is_empty():
        return defaults

    var result: Array[float] = []
    for token: String in raw.split(",", false):
        var cleaned: String = token.strip_edges().trim_suffix("%")
        result.append(float(cleaned) / 100.0 if cleaned.is_valid_float() else 1.0)
    while result.size() < 11:
        result.append(1.0)
    return result


static func _ensure_warheads_loaded() -> void:
    if _warheads_loaded:
        return
    _warheads_loaded = true
    _warheads.clear()
    var parsed: Variant = RA2Database.load_json(WARHEADS_PATH, false)
    if not parsed is Array:
        return
    for item_variant: Variant in parsed:
        if not item_variant is Dictionary:
            continue
        var item: Dictionary = item_variant as Dictionary
        _warheads[str(item.get("id", "")).to_upper()] = item


static func damage_multiplier(source, target) -> float:
    if not is_instance_valid(target):
        return 1.0
    var target_stats: Dictionary = target.stats if target.get("stats") is Dictionary else {}
    var armor_class: String = str(target_stats.get("armor_class", "building"))
    var armor_index: int = 8
    if armor_class == "biological":
        armor_index = 0
    elif armor_class == "mechanical":
        armor_index = 4

    var verses: Array = []
    if is_instance_valid(source) and source.get("stats") is Dictionary:
        verses = source.stats.get("warhead_verses", [])
    var verses_multiplier: float = float(verses[armor_index]) if armor_index < verses.size() else 1.0
    var armor_value: float = maxf(0.0, float(target_stats.get("armor_value", 0.0)))
    var armor_multiplier: float = clampf(1.0 - armor_value * 0.035, 0.55, 1.0)
    return maxf(0.0, verses_multiplier * armor_multiplier)


static func resolve_damage(source, target, base_damage: float) -> float:
    return maxf(0.0, base_damage * damage_multiplier(source, target))


static func is_air_target(entity) -> bool:
    return is_instance_valid(entity) and str(entity.stats.get("category", "")) in ["air", "aircraft"]

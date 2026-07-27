extends Node

const RA2Database = preload("res://scripts/ra2/ra2_database.gd")

const PROFILE_PATH: String = "res://data/ra2/runtime_profiles.json"
const LOCALIZATION_PATH: String = "res://data/ra2/localization.json"
const PREVIEW_ROOT: String = "res://assets/ra2_preview/"

var _profiles: Dictionary = {}
var _catalog_by_id: Dictionary = {}
var _entity_cache: Dictionary = {}
var _manifest_cache: Dictionary = {}
var _visual_cache: Dictionary = {}
var _texture_cache: Dictionary = {}
var _localization_lookup: Dictionary = {}
var _last_audio_ms: Dictionary = {}
var _transparent_texture: Texture2D

func _ready() -> void:
    _load_profiles()
    _load_catalog()
    _load_localization()
    _transparent_texture = _make_transparent_texture()

func _load_profiles() -> void:
    var parsed: Variant = RA2Database.load_json(PROFILE_PATH, false)
    if parsed is Dictionary:
        _profiles = parsed as Dictionary
    else:
        _profiles = {}

func _load_catalog() -> void:
    _catalog_by_id.clear()
    for item_variant: Variant in RA2Database.load_catalog():
        if item_variant is Dictionary:
            var item: Dictionary = item_variant as Dictionary
            _catalog_by_id[str(item.get("id", "")).to_upper()] = item

func _load_localization() -> void:
    _localization_lookup.clear()
    var parsed: Variant = RA2Database.load_json(LOCALIZATION_PATH, false)
    if not parsed is Dictionary:
        return
    var raw_lookup: Variant = (parsed as Dictionary).get("lookup", {})
    if not raw_lookup is Dictionary:
        return
    var lookup: Dictionary = raw_lookup as Dictionary
    for key_variant: Variant in lookup.keys():
        _localization_lookup[str(key_variant).to_lower()] = str(lookup[key_variant])

func get_profile(kind: String, faction_id: String, generic_id: String) -> Dictionary:
    var section: Dictionary = _profiles.get(kind, {}) as Dictionary
    var faction_section: Dictionary = section.get(faction_id, {}) as Dictionary
    var profile_variant: Variant = faction_section.get(generic_id)
    if profile_variant is Dictionary:
        return (profile_variant as Dictionary).duplicate(true)
    return {}

func resolve_entity_id(kind: String, faction_id: String, generic_id: String) -> String:
    return str(get_profile(kind, faction_id, generic_id).get("ra2_id", "")).to_upper()

func load_entity(entity_id: String) -> Dictionary:
    var key: String = entity_id.to_upper()
    if _entity_cache.has(key):
        return _entity_cache[key] as Dictionary
    var catalog_entry_variant: Variant = _catalog_by_id.get(key)
    if not catalog_entry_variant is Dictionary:
        _entity_cache[key] = {}
        return {}
    var entity: Dictionary = RA2Database.load_entity(catalog_entry_variant as Dictionary)
    if not entity.is_empty():
        entity["display_name"] = display_name_from_entity(entity)
    _entity_cache[key] = entity
    return entity

func resolve_name_token(token: String, fallback: String = "") -> String:
    var normalized: String = token.strip_edges()
    if normalized.is_empty():
        return fallback
    var localized: String = str(_localization_lookup.get(normalized.to_lower(), ""))
    if not localized.is_empty():
        return localized
    if normalized.begins_with("Name:") or normalized.begins_with("GUI:"):
        return fallback if not fallback.is_empty() else normalized.get_slice(":", 1)
    return normalized

func display_name_from_entity(entity: Dictionary) -> String:
    var entity_id: String = str(entity.get("id", ""))
    var rules: Dictionary = entity.get("rules", {}) as Dictionary
    var values: Dictionary = rules.get("values", {}) as Dictionary
    var fallback: String = str(values.get("Name", entity_id))
    return resolve_name_token(str(entity.get("name_token", "")), fallback)

func display_name(entity_id: String) -> String:
    var entity: Dictionary = load_entity(entity_id)
    if entity.is_empty():
        return entity_id
    return display_name_from_entity(entity)

func load_manifest(entity_id: String) -> Dictionary:
    var key: String = entity_id.to_lower()
    if _manifest_cache.has(key):
        return _manifest_cache[key] as Dictionary
    var path: String = PREVIEW_ROOT + key + "/manifest.json"
    var parsed: Variant = RA2Database.load_json(path, false)
    var manifest: Dictionary = {}
    if parsed is Dictionary:
        manifest = parsed as Dictionary
    _manifest_cache[key] = manifest
    return manifest

func get_visual_bundle(entity_id: String, theater: String = "temperate") -> Dictionary:
    var manifest: Dictionary = load_manifest(entity_id)
    if manifest.is_empty():
        return {}

    var resolved_theater: String = theater
    var animations: Dictionary = {}
    var default_animation: String = str(manifest.get("default_animation", ""))
    var canvas_value: Variant = manifest.get("canvas", [1, 1])
    var base_dir: String = PREVIEW_ROOT + entity_id.to_lower()
    if manifest.has("theaters"):
        var theaters: Dictionary = manifest.get("theaters", {}) as Dictionary
        if not theaters.has(resolved_theater):
            resolved_theater = str(manifest.get("default_theater", "temperate"))
        if not theaters.has(resolved_theater) and not theaters.is_empty():
            resolved_theater = str(theaters.keys()[0])
        var theater_data: Dictionary = theaters.get(resolved_theater, {}) as Dictionary
        animations = theater_data.get("animations", {}) as Dictionary
        default_animation = str(theater_data.get("default_animation", default_animation))
        canvas_value = theater_data.get("canvas", canvas_value)
        base_dir = base_dir.path_join(resolved_theater)
    else:
        animations = manifest.get("animations", {}) as Dictionary

    var cache_key: String = "%s|%s" % [entity_id.to_upper(), resolved_theater]
    if _visual_cache.has(cache_key):
        return _visual_cache[cache_key] as Dictionary

    var base_frames: SpriteFrames = SpriteFrames.new()
    var remap_frames: SpriteFrames = SpriteFrames.new()
    if base_frames.has_animation("default"):
        base_frames.remove_animation("default")
    if remap_frames.has_animation("default"):
        remap_frames.remove_animation("default")

    var content_rect: Rect2i = Rect2i()
    var found_content_rect: bool = false
    var default_content_rect: Rect2i = Rect2i()
    var found_default_rect: bool = false
    var runtime_animation_keys: Array[String] = _runtime_animation_keys(manifest, animations)
    for animation_key_variant: Variant in animations.keys():
        var animation_key: String = str(animation_key_variant)
        if not runtime_animation_keys.has(animation_key):
            continue
        var animation: Dictionary = animations[animation_key_variant] as Dictionary
        var directional: bool = bool(animation.get("directional", false))
        if directional:
            var directions: Dictionary = animation.get("directions", {}) as Dictionary
            for direction_variant: Variant in directions.keys():
                var direction: String = str(direction_variant)
                var direction_data: Dictionary = directions[direction_variant] as Dictionary
                var runtime_name: String = "%s_%s" % [animation_key, direction]
                var append_result: Dictionary = _append_animation(
                    base_frames,
                    remap_frames,
                    runtime_name,
                    direction_data,
                    base_dir,
                    animation
                )
                var rect_variant: Variant = append_result.get("content_rect")
                if rect_variant is Rect2i and (rect_variant as Rect2i).has_area():
                    var rect: Rect2i = rect_variant as Rect2i
                    content_rect = rect if not found_content_rect else content_rect.merge(rect)
                    found_content_rect = true
                    if animation_key == default_animation:
                        default_content_rect = rect if not found_default_rect else default_content_rect.merge(rect)
                        found_default_rect = true
        else:
            var append_result: Dictionary = _append_animation(
                base_frames,
                remap_frames,
                animation_key,
                animation,
                base_dir,
                animation
            )
            var rect_variant: Variant = append_result.get("content_rect")
            if rect_variant is Rect2i and (rect_variant as Rect2i).has_area():
                var rect: Rect2i = rect_variant as Rect2i
                content_rect = rect if not found_content_rect else content_rect.merge(rect)
                found_content_rect = true
                if animation_key == default_animation:
                    default_content_rect = rect if not found_default_rect else default_content_rect.merge(rect)
                    found_default_rect = true
            if animation_key == "BodyStates":
                _add_body_state_aliases(base_frames, remap_frames, animation_key)

    var canvas: Vector2 = Vector2.ONE
    if canvas_value is Array and (canvas_value as Array).size() >= 2:
        var canvas_array: Array = canvas_value as Array
        canvas = Vector2(float(canvas_array[0]), float(canvas_array[1]))
    if found_default_rect:
        content_rect = default_content_rect
    elif not found_content_rect:
        content_rect = Rect2i(0, 0, maxi(1, int(canvas.x)), maxi(1, int(canvas.y)))

    var bundle: Dictionary = {
        "manifest": manifest,
        "theater": resolved_theater,
        "animations": animations,
        "base_frames": base_frames,
        "remap_frames": remap_frames,
        "canvas": canvas,
        "content_rect": content_rect,
    }
    _visual_cache[cache_key] = bundle
    return bundle

func _runtime_animation_keys(manifest: Dictionary, animations: Dictionary) -> Array[String]:
    var category: String = str(manifest.get("category", ""))
    var preferred: Array[String] = []
    if category == "infantry":
        preferred = [
            "Ready", "Guard", "Walk", "FireUp", "Die1", "Die2", "Idle1", "Idle2",
            "Deploy", "Deployed", "DeployedFire", "Prone", "Crawl", "FireProne"
        ]
    elif category == "building":
        preferred = [
            "BodyStates", "Buildup", "Ready", "DamagedReady",
            "Operational", "DamagedOperational", "ProductionAnim",
            "DeployingAnim", "SpecialAnim", "SpecialAnimTwo", "SpecialAnimThree",
        ]
    else:
        preferred = ["Stand", "Fire", "HVA", "Walk", "Ready", "Die1", "Die2"]
    var result: Array[String] = []
    for animation_name: String in preferred:
        if animations.has(animation_name):
            result.append(animation_name)
    var default_animation: String = str(manifest.get("default_animation", ""))
    if animations.has(default_animation) and not result.has(default_animation):
        result.append(default_animation)
    if result.is_empty():
        for key_variant: Variant in animations.keys():
            result.append(str(key_variant))
    return result

func _append_animation(
    base_frames: SpriteFrames,
    remap_frames: SpriteFrames,
    runtime_name: String,
    frame_data: Dictionary,
    base_dir: String,
    animation: Dictionary
) -> Dictionary:
    var frame_paths: Array = _as_array(frame_data.get("frames", []))
    var mask_paths: Array = _as_array(frame_data.get("remap_masks", []))
    if frame_paths.is_empty():
        return {}

    base_frames.add_animation(runtime_name)
    remap_frames.add_animation(runtime_name)
    var rate_ms: float = maxf(20.0, float(animation.get("rate_ms", 120)))
    var fps: float = 1000.0 / rate_ms
    base_frames.set_animation_speed(runtime_name, fps)
    remap_frames.set_animation_speed(runtime_name, fps)
    var looped: bool = bool(animation.get("loop", true))
    if runtime_name.begins_with("Die") or runtime_name in ["Buildup", "Deploy"]:
        looped = false
    base_frames.set_animation_loop(runtime_name, looped)
    remap_frames.set_animation_loop(runtime_name, looped)

    var content_rect: Rect2i = Rect2i()
    var found_rect: bool = false
    for index: int in range(frame_paths.size()):
        var frame_path: String = base_dir.path_join(str(frame_paths[index]))
        var image_data: Dictionary = _load_image_texture(frame_path)
        var texture: Texture2D = image_data.get("texture") as Texture2D
        if texture == null:
            continue
        base_frames.add_frame(runtime_name, texture)
        var rect_variant: Variant = image_data.get("content_rect")
        if rect_variant is Rect2i and (rect_variant as Rect2i).has_area():
            var rect: Rect2i = rect_variant as Rect2i
            content_rect = rect if not found_rect else content_rect.merge(rect)
            found_rect = true

        var mask_texture: Texture2D = _transparent_texture
        if index < mask_paths.size():
            var mask_data: Dictionary = _load_image_texture(base_dir.path_join(str(mask_paths[index])))
            var loaded_mask: Texture2D = mask_data.get("texture") as Texture2D
            if loaded_mask != null:
                mask_texture = loaded_mask
        remap_frames.add_frame(runtime_name, mask_texture)
    return {"content_rect": content_rect}

func _add_body_state_aliases(base_frames: SpriteFrames, remap_frames: SpriteFrames, source_name: String) -> void:
    var frame_count: int = base_frames.get_frame_count(source_name)
    var aliases: Array[String] = ["__body_normal", "__body_damaged", "__body_rubble"]
    for index: int in range(mini(frame_count, aliases.size())):
        var alias: String = aliases[index]
        base_frames.add_animation(alias)
        remap_frames.add_animation(alias)
        base_frames.set_animation_loop(alias, true)
        remap_frames.set_animation_loop(alias, true)
        base_frames.add_frame(alias, base_frames.get_frame_texture(source_name, index))
        remap_frames.add_frame(alias, remap_frames.get_frame_texture(source_name, index))

func load_runtime_texture(path: String, transparent_fallback: bool = false) -> Texture2D:
    var image_data: Dictionary = _load_image_texture(path)
    var texture: Texture2D = image_data.get("texture") as Texture2D
    if texture != null:
        return texture
    if transparent_fallback:
        return _transparent_texture
    return _transparent_texture

func transparent_texture() -> Texture2D:
    return _transparent_texture

func _load_image_texture(path: String) -> Dictionary:
    if _texture_cache.has(path):
        return _texture_cache[path] as Dictionary
    if not FileAccess.file_exists(path):
        return {}
    var image: Image = Image.load_from_file(path)
    if image == null or image.is_empty():
        return {}
    var record: Dictionary = {
        "texture": ImageTexture.create_from_image(image),
        "content_rect": image.get_used_rect(),
    }
    _texture_cache[path] = record
    return record

func _make_transparent_texture() -> Texture2D:
    var image: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
    image.fill(Color.TRANSPARENT)
    return ImageTexture.create_from_image(image)

func play_entity_role(entity_id: String, role: String, cooldown_ms: int = 220) -> bool:
    var entity: Dictionary = load_entity(entity_id)
    var sounds: Dictionary = entity.get("sounds", {}) as Dictionary
    var event_ids: Array = _as_array(sounds.get(role, []))
    if event_ids.is_empty():
        return false
    return _play_event_with_cooldown(
        "%s:%s" % [entity_id.to_upper(), role],
        str(event_ids[0]),
        cooldown_ms
    )

func play_weapon_report(entity_id: String, cooldown_ms: int = 80) -> bool:
    var entity: Dictionary = load_entity(entity_id)
    var weapons: Dictionary = entity.get("weapons", {}) as Dictionary
    for slot: String in ["Primary", "Secondary", "ElitePrimary", "EliteSecondary"]:
        var weapon_variant: Variant = weapons.get(slot)
        if not weapon_variant is Dictionary:
            continue
        var reports: Array = _as_array((weapon_variant as Dictionary).get("report", []))
        if reports.is_empty():
            continue
        return _play_event_with_cooldown(
            "%s:weapon" % entity_id.to_upper(),
            str(reports[0]),
            cooldown_ms
        )
    return false

func _play_event_with_cooldown(key: String, event_id: String, cooldown_ms: int) -> bool:
    var now: int = Time.get_ticks_msec()
    if now - int(_last_audio_ms.get(key, -1000000)) < cooldown_ms:
        return false
    _last_audio_ms[key] = now
    return RA2AudioService.play_event(event_id)

func _as_array(value: Variant) -> Array:
    if value is Array:
        return value as Array
    if value == null:
        return []
    return [value]

extends RefCounted

const LEGACY_MANIFEST_PATH := "res://data/ra2_embedded/temperate_runtime_atlas.json"
const LEGACY_CHUNK_TEMPLATE := "res://data/ra2_embedded/temperate_runtime_atlas_%02d.b64"
const LEGACY_CHUNK_COUNT := 4
const RESOURCE_MANIFEST_PATH := "res://data/ra2_embedded/temperate_resources_v2.json"

static var _loaded: bool = false
static var _legacy_atlas: Texture2D
static var _legacy_manifest: Dictionary = {}
static var _legacy_textures: Dictionary = {}
static var _resource_atlas: Texture2D
static var _resource_manifest: Dictionary = {}
static var _resource_textures: Dictionary = {}


static func is_available() -> bool:
    _ensure_loaded()
    return is_instance_valid(_legacy_atlas) or is_instance_valid(_resource_atlas)


static func has_corrected_resources() -> bool:
    _ensure_loaded()
    return is_instance_valid(_resource_atlas) and not _resource_manifest.is_empty()


static func texture(asset_id: String) -> Texture2D:
    _ensure_loaded()
    var normalized: String = asset_id.to_lower()
    var corrected: Texture2D = _corrected_resource_texture(normalized)
    if corrected != null:
        return corrected
    return _legacy_texture(normalized)


static func asset_info(asset_id: String) -> Dictionary:
    _ensure_loaded()
    var normalized: String = asset_id.to_lower()
    var corrected: Dictionary = _corrected_resource_definition(normalized)
    if not corrected.is_empty():
        return corrected
    var legacy_assets: Dictionary = _legacy_manifest.get("assets", {})
    return legacy_assets.get(normalized, {})


static func shoreline_asset(mask: int) -> String:
    _ensure_loaded()
    var shore_map: Dictionary = _legacy_manifest.get("shore_mask_map", {})
    return str(shore_map.get(str(mask), ""))


static func _corrected_resource_texture(asset_id: String) -> Texture2D:
    if _resource_textures.has(asset_id):
        return _resource_textures[asset_id]
    if not is_instance_valid(_resource_atlas):
        return null
    var definition: Dictionary = _corrected_resource_definition(asset_id)
    if definition.is_empty():
        return null
    var raw_region: Variant = definition.get("region", [])
    if not raw_region is Array or raw_region.size() < 4:
        return null
    var result: AtlasTexture = AtlasTexture.new()
    result.atlas = _resource_atlas
    result.region = Rect2(
        float(raw_region[0]),
        float(raw_region[1]),
        float(raw_region[2]),
        float(raw_region[3])
    )
    result.filter_clip = true
    _resource_textures[asset_id] = result
    return result


static func _corrected_resource_definition(asset_id: String) -> Dictionary:
    var assets: Dictionary = _resource_manifest.get("assets", {})
    var definition: Variant = assets.get(asset_id, {})
    return definition if definition is Dictionary else {}


static func _legacy_texture(asset_id: String) -> Texture2D:
    if _legacy_textures.has(asset_id):
        return _legacy_textures[asset_id]
    if not is_instance_valid(_legacy_atlas):
        return null
    var assets: Dictionary = _legacy_manifest.get("assets", {})
    var definition_variant: Variant = assets.get(asset_id, {})
    if not definition_variant is Dictionary:
        return null
    var definition: Dictionary = definition_variant
    var raw_region: Variant = definition.get("region", [])
    if not raw_region is Array or raw_region.size() < 4:
        return null
    var result: AtlasTexture = AtlasTexture.new()
    result.atlas = _legacy_atlas
    result.region = Rect2(
        float(raw_region[0]),
        float(raw_region[1]),
        float(raw_region[2]),
        float(raw_region[3])
    )
    result.filter_clip = true
    _legacy_textures[asset_id] = result
    return result


static func _ensure_loaded() -> void:
    if _loaded:
        return
    _loaded = true
    var legacy: Dictionary = _load_legacy_png()
    _legacy_manifest = legacy.get("manifest", {})
    _legacy_atlas = legacy.get("texture") as Texture2D
    var corrected: Dictionary = _load_corrected_resources()
    _resource_manifest = corrected.get("manifest", {})
    _resource_atlas = corrected.get("texture") as Texture2D


static func _load_legacy_png() -> Dictionary:
    if not FileAccess.file_exists(LEGACY_MANIFEST_PATH):
        push_warning("RA2 original texture manifest is missing")
        return {}
    var parsed: Variant = JSON.parse_string(
        FileAccess.get_file_as_string(LEGACY_MANIFEST_PATH)
    )
    if not parsed is Dictionary:
        push_warning("RA2 original texture manifest is invalid")
        return {}
    var bytes: PackedByteArray = _decode_chunks(
        LEGACY_CHUNK_TEMPLATE,
        LEGACY_CHUNK_COUNT
    )
    if bytes.is_empty():
        return {}
    var image: Image = Image.new()
    var result: Error = image.load_png_from_buffer(bytes)
    if result != OK:
        push_warning(
            "RA2 legacy texture atlas PNG decode failed: %s" % error_string(result)
        )
        return {}
    return {
        "manifest": parsed,
        "texture": ImageTexture.create_from_image(image)
    }


static func _load_corrected_resources() -> Dictionary:
    if not FileAccess.file_exists(RESOURCE_MANIFEST_PATH):
        return {}
    var parsed_variant: Variant = JSON.parse_string(
        FileAccess.get_file_as_string(RESOURCE_MANIFEST_PATH)
    )
    if not parsed_variant is Dictionary:
        push_warning("Corrected RA2 resource manifest is invalid")
        return {}
    var manifest: Dictionary = parsed_variant
    if str(manifest.get("format", "")) != "ra2-resource-atlas-v2":
        push_warning("Unsupported corrected RA2 resource manifest format")
        return {}
    var chunk_template: String = str(manifest.get("chunk_template", ""))
    var chunk_count: int = int(manifest.get("chunk_count", 0))
    var bytes: PackedByteArray = _decode_chunks(chunk_template, chunk_count)
    if bytes.is_empty():
        return {}
    var image: Image = Image.new()
    var image_format: String = str(manifest.get("image_format", "png")).to_lower()
    var result: Error = ERR_FILE_UNRECOGNIZED
    match image_format:
        "png":
            result = image.load_png_from_buffer(bytes)
        "webp":
            result = image.load_webp_from_buffer(bytes)
        _:
            push_warning("Unsupported corrected RA2 resource image format: %s" % image_format)
            return {}
    if result != OK:
        push_warning(
            "Corrected RA2 resource atlas decode failed: %s" % error_string(result)
        )
        return {}
    return {
        "manifest": manifest,
        "texture": ImageTexture.create_from_image(image)
    }


static func _decode_chunks(template: String, count: int) -> PackedByteArray:
    if template.is_empty() or count <= 0:
        return PackedByteArray()
    var encoded: String = ""
    for index in range(count):
        var path: String = template % index
        if not FileAccess.file_exists(path):
            push_warning("RA2 embedded texture chunk is missing: %s" % path)
            return PackedByteArray()
        encoded += FileAccess.get_file_as_string(path).strip_edges()
    var bytes: PackedByteArray = Marshalls.base64_to_raw(encoded)
    if bytes.is_empty():
        push_warning("RA2 embedded texture Base64 decode failed: %s" % template)
    return bytes

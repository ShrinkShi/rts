extends RefCounted

const MANIFEST_PATH := "res://data/ra2_embedded/temperate_runtime_atlas.json"
const CHUNK_TEMPLATE := "res://data/ra2_embedded/temperate_runtime_atlas_%02d.b64"
const CHUNK_COUNT := 4

const RESOURCE_MANIFEST_PATH := "res://data/ra2_embedded/temperate_resources_v2.json"
const RESOURCE_CHUNK_TEMPLATE := "res://data/ra2_embedded/temperate_resources_v2_%02d.b64"
const RESOURCE_CHUNK_COUNT := 4

static var _loaded: bool = false
static var _atlas: Texture2D
static var _manifest: Dictionary = {}
static var _textures: Dictionary = {}
static var _resource_atlas: Texture2D
static var _resource_manifest: Dictionary = {}
static var _resource_textures: Dictionary = {}


static func is_available() -> bool:
    _ensure_loaded()
    return (
        (is_instance_valid(_atlas) and not _manifest.is_empty()) or
        (is_instance_valid(_resource_atlas) and not _resource_manifest.is_empty())
    )


static func texture(asset_id: String) -> Texture2D:
    _ensure_loaded()
    var normalized: String = asset_id.to_lower()
    var corrected: Texture2D = _texture_from_atlas(
        normalized,
        _resource_atlas,
        _resource_manifest,
        _resource_textures
    )
    if corrected != null:
        return corrected
    return _texture_from_atlas(normalized, _atlas, _manifest, _textures)


static func asset_info(asset_id: String) -> Dictionary:
    _ensure_loaded()
    var normalized: String = asset_id.to_lower()
    var corrected: Variant = _resource_manifest.get("assets", {}).get(normalized, null)
    if corrected is Dictionary:
        return corrected
    return _manifest.get("assets", {}).get(normalized, {})


static func shoreline_asset(mask: int) -> String:
    _ensure_loaded()
    return str(_manifest.get("shore_mask_map", {}).get(str(mask), ""))


static func _texture_from_atlas(
    asset_id: String,
    atlas: Texture2D,
    manifest: Dictionary,
    cache: Dictionary
) -> Texture2D:
    if cache.has(asset_id):
        return cache[asset_id]
    if not is_instance_valid(atlas):
        return null
    var definition: Dictionary = manifest.get("assets", {}).get(asset_id, {})
    var raw_region: Variant = definition.get("region", [])
    if not raw_region is Array or raw_region.size() < 4:
        return null
    var result: AtlasTexture = AtlasTexture.new()
    result.atlas = atlas
    result.region = Rect2(
        float(raw_region[0]),
        float(raw_region[1]),
        float(raw_region[2]),
        float(raw_region[3])
    )
    result.filter_clip = true
    cache[asset_id] = result
    return result


static func _ensure_loaded() -> void:
    if _loaded:
        return
    _loaded = true
    var legacy: Dictionary = _load_embedded_png(MANIFEST_PATH, CHUNK_TEMPLATE, CHUNK_COUNT)
    _manifest = legacy.get("manifest", {})
    _atlas = legacy.get("texture") as Texture2D
    var corrected: Dictionary = _load_embedded_png(
        RESOURCE_MANIFEST_PATH,
        RESOURCE_CHUNK_TEMPLATE,
        RESOURCE_CHUNK_COUNT
    )
    _resource_manifest = corrected.get("manifest", {})
    _resource_atlas = corrected.get("texture") as Texture2D


static func _load_embedded_png(
    manifest_path: String,
    chunk_template: String,
    chunk_count: int
) -> Dictionary:
    if not FileAccess.file_exists(manifest_path):
        push_warning("RA2 original texture manifest is missing: %s" % manifest_path)
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
    if not parsed is Dictionary:
        push_warning("RA2 original texture manifest is invalid: %s" % manifest_path)
        return {}
    var encoded: String = ""
    for index in range(chunk_count):
        var path: String = chunk_template % index
        if not FileAccess.file_exists(path):
            push_warning("RA2 original texture atlas chunk is missing: %s" % path)
            return {}
        encoded += FileAccess.get_file_as_string(path).strip_edges()
    var bytes: PackedByteArray = Marshalls.base64_to_raw(encoded)
    if bytes.is_empty():
        push_warning("RA2 original texture atlas Base64 decode failed: %s" % manifest_path)
        return {}
    var image: Image = Image.new()
    var load_error: Error = image.load_png_from_buffer(bytes)
    if load_error != OK:
        push_warning(
            "RA2 original texture atlas PNG decode failed: %s"
            % error_string(load_error)
        )
        return {}
    return {
        "manifest": parsed,
        "texture": ImageTexture.create_from_image(image),
    }

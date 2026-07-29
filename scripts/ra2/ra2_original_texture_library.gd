extends RefCounted

const MANIFEST_PATH := "res://data/ra2_embedded/temperate_runtime_atlas.json"
const CHUNK_TEMPLATE := "res://data/ra2_embedded/temperate_runtime_atlas_%02d.b64"
const CHUNK_COUNT := 4

static var _loaded := false
static var _atlas: Texture2D
static var _manifest: Dictionary = {}
static var _textures: Dictionary = {}


static func is_available() -> bool:
    _ensure_loaded()
    return is_instance_valid(_atlas) and not _manifest.is_empty()


static func texture(asset_id: String) -> Texture2D:
    _ensure_loaded()
    var normalized := asset_id.to_lower()
    if _textures.has(normalized):
        return _textures[normalized]
    if not is_instance_valid(_atlas):
        return null
    var definition: Dictionary = _manifest.get("assets", {}).get(normalized, {})
    var raw_region: Variant = definition.get("region", [])
    if not raw_region is Array or raw_region.size() < 4:
        return null
    var result := AtlasTexture.new()
    result.atlas = _atlas
    result.region = Rect2(
        float(raw_region[0]), float(raw_region[1]),
        float(raw_region[2]), float(raw_region[3])
    )
    result.filter_clip = true
    _textures[normalized] = result
    return result


static func asset_info(asset_id: String) -> Dictionary:
    _ensure_loaded()
    return _manifest.get("assets", {}).get(asset_id.to_lower(), {})


static func shoreline_asset(mask: int) -> String:
    _ensure_loaded()
    return str(_manifest.get("shore_mask_map", {}).get(str(mask), ""))


static func _ensure_loaded() -> void:
    if _loaded:
        return
    _loaded = true
    if not FileAccess.file_exists(MANIFEST_PATH):
        push_warning("RA2 original texture manifest is missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
    if not parsed is Dictionary:
        push_warning("RA2 original texture manifest is invalid")
        return
    _manifest = parsed
    var encoded := ""
    for index in range(CHUNK_COUNT):
        var path := CHUNK_TEMPLATE % index
        if not FileAccess.file_exists(path):
            push_warning("RA2 original texture atlas chunk is missing: %s" % path)
            _manifest.clear()
            return
        encoded += FileAccess.get_file_as_string(path).strip_edges()
    var bytes: PackedByteArray = Marshalls.base64_to_raw(encoded)
    if bytes.is_empty():
        push_warning("RA2 original texture atlas base64 decode failed")
        _manifest.clear()
        return
    var image := Image.new()
    var load_error := image.load_png_from_buffer(bytes)
    if load_error != OK:
        push_warning("RA2 original texture atlas PNG decode failed: %s" % error_string(load_error))
        _manifest.clear()
        return
    _atlas = ImageTexture.create_from_image(image)

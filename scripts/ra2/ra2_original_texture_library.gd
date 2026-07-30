extends RefCounted

const MANIFEST_PATH := "res://data/ra2_embedded/temperate_runtime_atlas.json"
const CHUNK_TEMPLATE := "res://data/ra2_embedded/temperate_runtime_atlas_%02d.b64"
const CHUNK_COUNT := 4

const RESOURCE_CHUNK_TEMPLATE := "res://data/ra2_embedded/temperate_resources_v2_%02d.b64"
const RESOURCE_CHUNK_COUNT := 5
const RESOURCE_COLUMNS := 23
const RESOURCE_SLOT_WIDTH := 86
const RESOURCE_SLOT_HEIGHT := 62
const TIB_FRAME_COUNT := 20 * 12
const GEM_FRAME_COUNT := 12 * 12

static var _loaded: bool = false
static var _atlas: Texture2D
static var _manifest: Dictionary = {}
static var _textures: Dictionary = {}
static var _resource_atlas: Texture2D
static var _resource_textures: Dictionary = {}


static func is_available() -> bool:
    _ensure_loaded()
    return is_instance_valid(_atlas) or is_instance_valid(_resource_atlas)


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
    return _manifest.get("assets", {}).get(normalized, {})


static func shoreline_asset(mask: int) -> String:
    _ensure_loaded()
    return str(_manifest.get("shore_mask_map", {}).get(str(mask), ""))


static func _corrected_resource_texture(asset_id: String) -> Texture2D:
    if _resource_textures.has(asset_id):
        return _resource_textures[asset_id]
    if not is_instance_valid(_resource_atlas):
        return null
    var definition: Dictionary = _corrected_resource_definition(asset_id)
    if definition.is_empty():
        return null
    var raw_region: Array = definition["region"]
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
    var parts: PackedStringArray = asset_id.split("_")
    var atlas_index: int = -1
    var is_pillar: bool = false
    if parts.size() == 3 and parts[0] == "tib":
        var resource_number: int = int(parts[1])
        var frame: int = int(parts[2])
        if resource_number >= 1 and resource_number <= 20 and frame >= 0 and frame < 12:
            atlas_index = (resource_number - 1) * 12 + frame
    elif parts.size() == 3 and parts[0] == "gem":
        var resource_number: int = int(parts[1])
        var frame: int = int(parts[2])
        if resource_number >= 1 and resource_number <= 12 and frame >= 0 and frame < 12:
            atlas_index = TIB_FRAME_COUNT + (resource_number - 1) * 12 + frame
    elif parts.size() == 2 and parts[0] == "tibtre01":
        var frame: int = int(parts[1])
        if frame >= 0 and frame < 11:
            atlas_index = TIB_FRAME_COUNT + GEM_FRAME_COUNT + frame
            is_pillar = true
    if atlas_index < 0:
        return {}

    var column: int = atlas_index % RESOURCE_COLUMNS
    var row: int = int(atlas_index / RESOURCE_COLUMNS)
    if is_pillar:
        return {
            "region": [
                column * RESOURCE_SLOT_WIDTH + 1,
                row * RESOURCE_SLOT_HEIGHT + 3,
                84,
                56
            ],
            "anchor": [42.0, 52.0],
            "palette": "unittem.pal"
        }
    return {
        "region": [
            column * RESOURCE_SLOT_WIDTH + 13,
            row * RESOURCE_SLOT_HEIGHT + 1,
            60,
            60
        ],
        "anchor": [30.0, 56.0],
        "palette": "temperat.pal"
    }


static func _legacy_texture(asset_id: String) -> Texture2D:
    if _textures.has(asset_id):
        return _textures[asset_id]
    if not is_instance_valid(_atlas):
        return null
    var definition: Dictionary = _manifest.get("assets", {}).get(asset_id, {})
    var raw_region: Variant = definition.get("region", [])
    if not raw_region is Array or raw_region.size() < 4:
        return null
    var result: AtlasTexture = AtlasTexture.new()
    result.atlas = _atlas
    result.region = Rect2(
        float(raw_region[0]), float(raw_region[1]),
        float(raw_region[2]), float(raw_region[3])
    )
    result.filter_clip = true
    _textures[asset_id] = result
    return result


static func _ensure_loaded() -> void:
    if _loaded:
        return
    _loaded = true
    var legacy: Dictionary = _load_legacy_png()
    _manifest = legacy.get("manifest", {})
    _atlas = legacy.get("texture") as Texture2D
    _resource_atlas = _load_corrected_resource_webp()


static func _load_legacy_png() -> Dictionary:
    if not FileAccess.file_exists(MANIFEST_PATH):
        push_warning("RA2 original texture manifest is missing")
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
    if not parsed is Dictionary:
        push_warning("RA2 original texture manifest is invalid")
        return {}
    var bytes: PackedByteArray = _decode_chunks(CHUNK_TEMPLATE, CHUNK_COUNT)
    if bytes.is_empty():
        return {}
    var image: Image = Image.new()
    var result: Error = image.load_png_from_buffer(bytes)
    if result != OK:
        push_warning("RA2 legacy texture atlas PNG decode failed: %s" % error_string(result))
        return {}
    return {"manifest": parsed, "texture": ImageTexture.create_from_image(image)}


static func _load_corrected_resource_webp() -> Texture2D:
    var bytes: PackedByteArray = _decode_chunks(
        RESOURCE_CHUNK_TEMPLATE,
        RESOURCE_CHUNK_COUNT
    )
    if bytes.is_empty():
        return null
    var image: Image = Image.new()
    var result: Error = image.load_webp_from_buffer(bytes)
    if result != OK:
        push_warning("Corrected RA2 resource atlas WebP decode failed: %s" % error_string(result))
        return null
    return ImageTexture.create_from_image(image)


static func _decode_chunks(template: String, count: int) -> PackedByteArray:
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

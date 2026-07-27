extends RefCounted

const CATALOG_PATH: String = "res://data/ra2/catalog.json"
const SUMMARY_PATH: String = "res://data/ra2/summary.json"
const LOCALIZATION_CATALOG_PATH: String = "res://data/ra2/localization_catalog.json"
const SOUND_EVENTS_PATH: String = "res://data/ra2/sound_events.json"
const MAPS_PATH: String = "res://data/ra2/maps_official.json"
const BASE_PATH: String = "res://data/ra2/"

static func load_json(path: String, report_errors: bool = true) -> Variant:
    if not FileAccess.file_exists(path):
        if report_errors:
            push_error("RA2 database file does not exist: %s" % path)
        return null
    var file: FileAccess = FileAccess.open(path, FileAccess.READ)
    if file == null:
        if report_errors:
            push_error("Cannot open RA2 database file: %s" % path)
        return null
    var text: String = file.get_as_text()
    var parsed: Variant = JSON.parse_string(text)
    if parsed == null and report_errors:
        push_error("Invalid JSON in RA2 database file: %s" % path)
    return parsed

static func _load_array(path: String) -> Array:
    var parsed: Variant = load_json(path)
    if parsed is Array:
        return parsed as Array
    return []

static func load_catalog() -> Array:
    return _load_array(CATALOG_PATH)

static func load_localization_catalog() -> Array:
    return _load_array(LOCALIZATION_CATALOG_PATH)

static func load_sound_events() -> Array:
    return _load_array(SOUND_EVENTS_PATH)

static func load_maps() -> Array:
    return _load_array(MAPS_PATH)

static func load_summary() -> Dictionary:
    var parsed: Variant = load_json(SUMMARY_PATH)
    if parsed is Dictionary:
        return parsed as Dictionary
    return {}

static func load_entity(catalog_entry: Dictionary) -> Dictionary:
    var relative_path: String = str(catalog_entry.get("file", ""))
    if relative_path.is_empty():
        return {}
    var parsed: Variant = load_json(BASE_PATH + relative_path)
    if parsed is Dictionary:
        return parsed as Dictionary
    return {}

static func preview_manifest_path(entity_id: String) -> String:
    return "res://assets/ra2_preview/%s/manifest.json" % entity_id.to_lower()

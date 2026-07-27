extends RefCounted

const SOUND_EVENTS_PATH: String = "res://data/ra2/sound_events.json"

static var _events: Dictionary = {}

static func _ensure_loaded() -> void:
    if not _events.is_empty():
        return
    if not FileAccess.file_exists(SOUND_EVENTS_PATH):
        return
    var file: FileAccess = FileAccess.open(SOUND_EVENTS_PATH, FileAccess.READ)
    if file == null:
        return
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if not parsed is Array:
        return
    var items: Array = parsed as Array
    for item_variant in items:
        if not item_variant is Dictionary:
            continue
        var item: Dictionary = item_variant as Dictionary
        _events[str(item.get("id", "")).to_lower()] = item

static func event(event_id: String) -> Dictionary:
    _ensure_loaded()
    var value: Variant = _events.get(event_id.to_lower())
    if value is Dictionary:
        return value as Dictionary
    return {}

static func sample_paths(event_id: String) -> PackedStringArray:
    var result: PackedStringArray = PackedStringArray()
    var definition: Dictionary = event(event_id)
    var samples: Array = definition.get("samples", []) as Array
    for sample_variant in samples:
        if not sample_variant is Dictionary:
            continue
        var path: String = str((sample_variant as Dictionary).get("resource_path", ""))
        # Check the source file itself. ResourceLoader.exists() may return true while
        # the editor is still building the .godot/imported/*.sample cache.
        if not path.is_empty() and FileAccess.file_exists(path):
            result.append(path)
    return result

static func load_stream_path(path: String) -> AudioStream:
    if path.is_empty():
        return null

    # Loading the PCM WAV source directly avoids transient or stale .sample cache
    # failures during the first import of several thousand RA2/YR voice clips.
    if path.get_extension().to_lower() == "wav" and FileAccess.file_exists(path):
        var wav_stream: AudioStreamWAV = AudioStreamWAV.load_from_file(path)
        if wav_stream != null:
            return wav_stream

    if ResourceLoader.exists(path):
        var resource: Resource = ResourceLoader.load(path)
        if resource is AudioStream:
            return resource as AudioStream
    return null

static func load_random_stream(event_id: String, random_value: int = 0) -> AudioStream:
    var paths: PackedStringArray = sample_paths(event_id)
    if paths.is_empty():
        return null
    var index: int = posmod(random_value, paths.size())
    return load_stream_path(paths[index])

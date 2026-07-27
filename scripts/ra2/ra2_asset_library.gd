class_name RA2AssetLibrary
extends RefCounted

const DEFAULT_MANIFEST := "res://assets/ra2_imported/manifest.json"


static func load_manifest(path: String = DEFAULT_MANIFEST) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {"version": 1, "assets": []}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_error("无法读取 RA2 素材清单：%s" % path)
        return {"version": 1, "assets": []}
    var parsed = JSON.parse_string(file.get_as_text())
    if parsed is Dictionary:
        return parsed
    push_error("RA2 素材清单不是有效 JSON：%s" % path)
    return {"version": 1, "assets": []}


static func find_asset(asset_name: String, path: String = DEFAULT_MANIFEST) -> Dictionary:
    var manifest := load_manifest(path)
    var assets = manifest.get("assets", [])
    if assets is not Array:
        return {}
    for entry in assets:
        if entry is not Dictionary:
            continue
        var candidate := str(entry.get("name", ""))
        if candidate.is_empty():
            candidate = str(entry.get("source", "")).get_file().get_basename()
        if candidate.to_lower() == asset_name.to_lower():
            return entry
    return {}


static func load_sprite_frames(resource_path: String) -> SpriteFrames:
    if resource_path.is_empty():
        return null
    var resource = load(resource_path)
    return resource as SpriteFrames


static func load_wav(resource_path: String) -> AudioStream:
    if resource_path.is_empty():
        return null
    var imported = load(resource_path)
    if imported is AudioStream:
        return imported
    return AudioStreamWAV.load_from_file(resource_path)

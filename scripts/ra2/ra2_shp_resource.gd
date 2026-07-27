class_name RA2SHPResource
extends Resource

@export var atlas: Texture2D
@export var frame_size: Vector2i = Vector2i.ONE
@export var frame_count: int = 0
@export var columns: int = 1
@export_file("*.json") var metadata_path: String = ""


func get_frame_texture(frame_index: int) -> AtlasTexture:
    if atlas == null or frame_count <= 0:
        return null
    var safe_index := clampi(frame_index, 0, frame_count - 1)
    var safe_columns := maxi(1, columns)
    var texture := AtlasTexture.new()
    texture.atlas = atlas
    texture.region = Rect2(
        float((safe_index % safe_columns) * frame_size.x),
        float(floori(float(safe_index) / float(safe_columns)) * frame_size.y),
        float(frame_size.x),
        float(frame_size.y)
    )
    texture.filter_clip = true
    return texture


func load_metadata() -> Dictionary:
    if metadata_path.is_empty() or not FileAccess.file_exists(metadata_path):
        return {}
    var file := FileAccess.open(metadata_path, FileAccess.READ)
    if file == null:
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    return parsed if parsed is Dictionary else {}

extends Node

signal sample_started(event_id: String, sample_name: String, resource_path: String)
signal playback_failed(event_id: String, reason: String)
signal playback_stopped

const RA2AudioLibrary = preload("res://scripts/ra2/ra2_audio_library.gd")
const PLAYER_POOL_SIZE: int = 12
const MIN_EDGE_VOLUME := 0.34

var _players: Array[AudioStreamPlayer] = []
var _next_player_index: int = 0
var _master_volume_linear: float = 0.85
var _random: RandomNumberGenerator = RandomNumberGenerator.new()
var _spatial_players: Array[AudioStreamPlayer2D] = []


func _ready() -> void:
    _random.randomize()
    for index in range(PLAYER_POOL_SIZE):
        var player := AudioStreamPlayer.new()
        player.name = "RA2AudioPlayer%d" % index
        player.volume_db = linear_to_db(_master_volume_linear)
        add_child(player)
        _players.append(player)


func set_master_volume_linear(value: float) -> void:
    _master_volume_linear = clampf(value, 0.0, 1.0)
    var volume_db := linear_to_db(maxf(_master_volume_linear, 0.0001))
    for player in _players:
        player.volume_db = volume_db
    for player in _spatial_players:
        if is_instance_valid(player):
            player.volume_db = minf(player.volume_db, volume_db)


func get_master_volume_linear() -> float:
    return _master_volume_linear


func play_event(event_id: String, random_sample: bool = true) -> bool:
    var paths := RA2AudioLibrary.sample_paths(event_id)
    if paths.is_empty():
        playback_failed.emit(event_id, "声音事件没有可用样本")
        return false
    var index := _random.randi_range(0, paths.size() - 1) if random_sample else 0
    return play_path(paths[index], event_id)


func play_event_spatial(event_id: String, world_position: Vector2, match_ref, random_sample: bool = true) -> bool:
    var paths := RA2AudioLibrary.sample_paths(event_id)
    if paths.is_empty():
        playback_failed.emit(event_id, "声音事件没有可用样本")
        return false
    var index := _random.randi_range(0, paths.size() - 1) if random_sample else 0
    return play_path_spatial(paths[index], world_position, match_ref, event_id)


func play_event_sample(event_id: String, sample_index: int) -> bool:
    var definition: Dictionary = RA2AudioLibrary.event(event_id)
    var samples: Array = definition.get("samples", [])
    if samples.is_empty():
        playback_failed.emit(event_id, "声音事件没有可用样本")
        return false
    var safe_index := posmod(sample_index, samples.size())
    var sample_variant: Variant = samples[safe_index]
    if not sample_variant is Dictionary:
        playback_failed.emit(event_id, "样本定义格式无效")
        return false
    var sample: Dictionary = sample_variant
    return play_path(str(sample.get("resource_path", "")), event_id, str(sample.get("name", "")))


func play_path(resource_path: String, event_id: String = "", sample_name: String = "") -> bool:
    var stream := _load_stream(resource_path, event_id)
    if stream == null:
        return false
    var player := _acquire_player()
    player.stream = stream
    player.volume_db = linear_to_db(maxf(_master_volume_linear, 0.0001))
    player.play()
    _emit_started(event_id, sample_name, resource_path)
    return true


func play_path_spatial(resource_path: String, world_position: Vector2, match_ref, event_id: String = "", sample_name: String = "") -> bool:
    if not is_instance_valid(match_ref) or not match_ref.has_method("get_world_battle_rect"):
        return false
    var view_rect: Rect2 = match_ref.get_world_battle_rect()
    if not view_rect.has_point(world_position):
        return false
    var stream := _load_stream(resource_path, event_id)
    if stream == null:
        return false
    var center := view_rect.get_center()
    var half_size := view_rect.size * 0.5
    var normalized_distance := Vector2(
        absf(world_position.x - center.x) / maxf(1.0, half_size.x),
        absf(world_position.y - center.y) / maxf(1.0, half_size.y)
    ).length() / sqrt(2.0)
    var distance_volume := lerpf(1.0, MIN_EDGE_VOLUME, clampf(normalized_distance, 0.0, 1.0))
    var player := AudioStreamPlayer2D.new()
    player.name = "RA2SpatialOneShot"
    player.stream = stream
    player.global_position = world_position
    player.volume_db = linear_to_db(maxf(_master_volume_linear * distance_volume, 0.0001))
    player.max_distance = maxf(view_rect.size.x, view_rect.size.y) * 1.25
    player.attenuation = 1.0
    player.panning_strength = 1.0
    var parent: Node = match_ref.effect_layer if is_instance_valid(match_ref.get("effect_layer")) else match_ref
    parent.add_child(player)
    _spatial_players.append(player)
    player.finished.connect(_on_spatial_finished.bind(player))
    player.play()
    _emit_started(event_id, sample_name, resource_path)
    return true


func stop_all() -> void:
    for player in _players:
        player.stop()
    for player in _spatial_players:
        if is_instance_valid(player):
            player.stop()
            player.queue_free()
    _spatial_players.clear()
    playback_stopped.emit()


func _load_stream(resource_path: String, event_id: String) -> AudioStream:
    if resource_path.is_empty() or not FileAccess.file_exists(resource_path):
        playback_failed.emit(event_id, "音频源文件不存在：%s" % resource_path)
        return null
    var stream := RA2AudioLibrary.load_stream_path(resource_path)
    if stream == null:
        playback_failed.emit(event_id, "无法解码音频：%s" % resource_path)
    return stream


func _emit_started(event_id: String, sample_name: String, resource_path: String) -> void:
    var resolved_name := sample_name if not sample_name.is_empty() else resource_path.get_file().get_basename()
    sample_started.emit(event_id, resolved_name, resource_path)


func _on_spatial_finished(player: AudioStreamPlayer2D) -> void:
    _spatial_players.erase(player)
    if is_instance_valid(player):
        player.queue_free()


func _acquire_player() -> AudioStreamPlayer:
    for player in _players:
        if not player.playing:
            return player
    var player := _players[_next_player_index]
    _next_player_index = (_next_player_index + 1) % _players.size()
    player.stop()
    return player

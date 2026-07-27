extends Node

signal sample_started(event_id: String, sample_name: String, resource_path: String)
signal playback_failed(event_id: String, reason: String)
signal playback_stopped

const RA2AudioLibrary = preload("res://scripts/ra2/ra2_audio_library.gd")

const PLAYER_POOL_SIZE: int = 12

var _players: Array[AudioStreamPlayer] = []
var _next_player_index: int = 0
var _master_volume_linear: float = 0.85
var _random: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
    _random.randomize()
    for index in range(PLAYER_POOL_SIZE):
        var player: AudioStreamPlayer = AudioStreamPlayer.new()
        player.name = "RA2AudioPlayer%d" % index
        player.volume_db = linear_to_db(_master_volume_linear)
        add_child(player)
        _players.append(player)

func set_master_volume_linear(value: float) -> void:
    _master_volume_linear = clampf(value, 0.0, 1.0)
    var volume_db: float = linear_to_db(maxf(_master_volume_linear, 0.0001))
    for player in _players:
        player.volume_db = volume_db

func get_master_volume_linear() -> float:
    return _master_volume_linear

func play_event(event_id: String, random_sample: bool = true) -> bool:
    var paths: PackedStringArray = RA2AudioLibrary.sample_paths(event_id)
    if paths.is_empty():
        playback_failed.emit(event_id, "声音事件没有可用样本")
        return false
    var index: int = _random.randi_range(0, paths.size() - 1) if random_sample else 0
    return play_path(paths[index], event_id)

func play_event_sample(event_id: String, sample_index: int) -> bool:
    var definition: Dictionary = RA2AudioLibrary.event(event_id)
    var samples: Array = definition.get("samples", []) as Array
    if samples.is_empty():
        playback_failed.emit(event_id, "声音事件没有可用样本")
        return false
    var safe_index: int = posmod(sample_index, samples.size())
    var sample_variant: Variant = samples[safe_index]
    if not sample_variant is Dictionary:
        playback_failed.emit(event_id, "样本定义格式无效")
        return false
    var sample: Dictionary = sample_variant as Dictionary
    return play_path(str(sample.get("resource_path", "")), event_id, str(sample.get("name", "")))

func play_path(resource_path: String, event_id: String = "", sample_name: String = "") -> bool:
    if resource_path.is_empty() or not FileAccess.file_exists(resource_path):
        playback_failed.emit(event_id, "音频源文件不存在：%s" % resource_path)
        return false
    var stream: AudioStream = RA2AudioLibrary.load_stream_path(resource_path)
    if stream == null:
        playback_failed.emit(event_id, "无法解码音频：%s" % resource_path)
        return false
    var player: AudioStreamPlayer = _acquire_player()
    player.stream = stream
    player.volume_db = linear_to_db(maxf(_master_volume_linear, 0.0001))
    player.play()
    var resolved_name: String = sample_name if not sample_name.is_empty() else resource_path.get_file().get_basename()
    sample_started.emit(event_id, resolved_name, resource_path)
    return true

func stop_all() -> void:
    for player in _players:
        player.stop()
    playback_stopped.emit()

func _acquire_player() -> AudioStreamPlayer:
    for player in _players:
        if not player.playing:
            return player
    var player: AudioStreamPlayer = _players[_next_player_index]
    _next_player_index = (_next_player_index + 1) % _players.size()
    player.stop()
    return player

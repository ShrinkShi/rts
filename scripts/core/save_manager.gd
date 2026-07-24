extends Node

signal settings_applied(settings)

const SETTINGS_PATH = "user://settings.json"
const PROFILE_PATH = "user://profile.json"
const BASE_CONTENT_SIZE = Vector2i(1280, 720)

const DEFAULT_SETTINGS = {
    "resolution": "1280x720",
    "fullscreen": false,
    "health_bar_mode": "selected_damaged",
    "game_speed": 1.0,
    "mouse_speed": 1.0,
    "master_volume": 0.8,
    "voice_volume": 0.75,
    "unit_voices": true,
    "edge_scroll": true,
    "scroll_speed": 650.0,
    "show_fps": false,
    "show_damage_numbers": true,
    "show_heal_numbers": true,
    "show_health_values": true,
    "show_experience": true
}

var display_apply_generation = 0
var last_display_status = ""

var settings = DEFAULT_SETTINGS.duplicate(true)

var profile = {
    "campaign_unlocked": ["training_01"],
    "campaign_completed": [],
    "skirmish_wins": 0,
    "skirmish_losses": 0
}

func _ready():
    settings = _merge_defaults(_read_or_default(SETTINGS_PATH, DEFAULT_SETTINGS), DEFAULT_SETTINGS)
    profile = _read_or_default(PROFILE_PATH, profile)
    call_deferred("apply_settings")

func _merge_defaults(value, defaults):
    var merged = defaults.duplicate(true)
    if value is Dictionary:
        for key in value:
            merged[key] = value[key]
    return merged

func _read_or_default(path, fallback):
    if not FileAccess.file_exists(path):
        return fallback.duplicate(true)
    var file = FileAccess.open(path, FileAccess.READ)
    if file == null:
        return fallback.duplicate(true)
    var parsed = JSON.parse_string(file.get_as_text())
    if parsed is Dictionary:
        return parsed
    return fallback.duplicate(true)

func save_settings():
    _write_json(SETTINGS_PATH, settings)

func apply_settings():
    _apply_display_settings()
    _apply_audio_settings()
    Engine.time_scale = clamp(float(settings.get("game_speed", 1.0)), 0.25, 3.0)
    settings_applied.emit(settings)

func apply_and_save():
    apply_settings()
    save_settings()

func reset_settings():
    settings = DEFAULT_SETTINGS.duplicate(true)
    apply_and_save()

func _apply_display_settings():
    display_apply_generation += 1
    var generation = display_apply_generation
    var fullscreen = bool(settings.get("fullscreen", false))
    var resolution = _parse_resolution(str(settings.get("resolution", "1280x720")))
    var window = get_tree().root

    # Keep one stable 1280×720 design canvas so HUD proportions do not change
    # between output resolutions. The selected resolution controls the native
    # window; fullscreen uses the monitor's current desktop resolution.
    window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
    window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
    window.content_scale_size = BASE_CONTENT_SIZE
    call_deferred("_commit_native_display_settings", generation, fullscreen, resolution)

func _commit_native_display_settings(generation, fullscreen, resolution):
    if generation != display_apply_generation:
        return
    var window = get_tree().root
    var editor_note = ""
    if OS.has_feature("editor"):
        editor_note = " 当前由 Godot 编辑器启动；若启用了‘嵌入游戏’，物理窗口尺寸和系统全屏会被编辑器接管，请切换为浮动运行窗口验证。"

    if fullscreen:
        window.mode = Window.MODE_FULLSCREEN
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
        await get_tree().process_frame
        if generation != display_apply_generation:
            return
        var actual_size = window.size
        last_display_status = "已应用全屏模式：%d×%d。分辨率选项 %d×%d 将作为退出全屏后的窗口尺寸。%s" % [actual_size.x, actual_size.y, resolution.x, resolution.y, editor_note]
        return

    window.mode = Window.MODE_WINDOWED
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
    await get_tree().process_frame
    if generation != display_apply_generation:
        return

    var screen = DisplayServer.window_get_current_screen()
    var usable = DisplayServer.screen_get_usable_rect(screen)
    var target_size = Vector2i(
        min(resolution.x, usable.size.x),
        min(resolution.y, usable.size.y)
    )
    window.size = target_size
    DisplayServer.window_set_size(target_size)
    await get_tree().process_frame
    if generation != display_apply_generation:
        return

    var centered = usable.position + Vector2i(
        int((usable.size.x - target_size.x) / 2),
        int((usable.size.y - target_size.y) / 2)
    )
    DisplayServer.window_set_position(centered)
    last_display_status = "已应用窗口模式：%d×%d。%s" % [target_size.x, target_size.y, editor_note]

func get_display_status_text():
    if last_display_status != "":
        return last_display_status
    var window = get_tree().root
    return "当前窗口：%d×%d。" % [window.size.x, window.size.y]

func _apply_audio_settings():
    var master = clamp(float(settings.get("master_volume", 0.8)), 0.0, 1.0)
    AudioServer.set_bus_volume_linear(0, max(master, 0.0001))
    AudioServer.set_bus_mute(0, master <= 0.001)

func _parse_resolution(value):
    var parts = value.to_lower().split("x")
    if parts.size() != 2:
        return Vector2i(1280, 720)
    return Vector2i(max(960, int(parts[0])), max(540, int(parts[1])))

func save_profile():
    _write_json(PROFILE_PATH, profile)

func record_result(kind, won, mission_id = ""):
    if kind == "campaign" and won and mission_id != "":
        if not mission_id in profile.campaign_completed:
            profile.campaign_completed.append(mission_id)
    elif kind == "skirmish":
        if won:
            profile.skirmish_wins = int(profile.get("skirmish_wins", 0)) + 1
        else:
            profile.skirmish_losses = int(profile.get("skirmish_losses", 0)) + 1
    save_profile()

func _write_json(path, value):
    var file = FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        push_error("Unable to write save file: " + path)
        return
    file.store_string(JSON.stringify(value, "  "))

extends Control

signal back_requested

const UIFactory = preload("res://scripts/ui/ui_factory.gd")
const BackgroundGrid = preload("res://scripts/ui/background_grid.gd")

const RESOLUTIONS = ["1280x720", "1366x768", "1600x900", "1920x1080", "2560x1440"]
const HEALTH_MODES = [
    {"id": "off", "name": "关闭"},
    {"id": "selected", "name": "仅选中单位"},
    {"id": "selected_damaged", "name": "选中或受伤单位"},
    {"id": "always", "name": "始终显示"}
]
const GAME_SPEEDS = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

var resolution_option
var fullscreen_check
var health_option
var game_speed_option
var mouse_speed_slider
var mouse_speed_value
var scroll_speed_slider
var scroll_speed_value
var master_slider
var master_value
var voice_slider
var voice_value
var voices_check
var edge_scroll_check
var show_fps_check
var damage_numbers_check
var heal_numbers_check
var health_values_check
var experience_check
var status_label

func _ready():
    process_mode = Node.PROCESS_MODE_ALWAYS
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _build_ui()
    _load_values()

func _build_ui():
    var background = BackgroundGrid.new()
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(background)

    var panel = PanelContainer.new()
    panel.anchor_left = 0.5
    panel.anchor_right = 0.5
    panel.anchor_top = 0.0
    panel.anchor_bottom = 1.0
    panel.offset_left = -430
    panel.offset_right = 430
    panel.offset_top = 20
    panel.offset_bottom = -20
    panel.add_theme_stylebox_override("panel", UIFactory.panel_style(Color(0.04, 0.065, 0.08, 0.97), Color("#536D79"), 6))
    add_child(panel)

    var root = VBoxContainer.new()
    root.add_theme_constant_override("separation", 12)
    panel.add_child(root)

    root.add_child(UIFactory.heading("设置", 32))
    root.add_child(UIFactory.muted_label("分辨率调整窗口尺寸；全屏使用显示器当前桌面分辨率。Godot 编辑器“嵌入游戏”会锁定系统窗口，请切换为浮动运行窗口测试。", 14))
    root.add_child(HSeparator.new())

    var scroll = ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(scroll)
    var options = VBoxContainer.new()
    options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    options.add_theme_constant_override("separation", 8)
    scroll.add_child(options)

    options.add_child(_section_title("画面"))
    resolution_option = OptionButton.new()
    UIFactory.style_option(resolution_option)
    for value in RESOLUTIONS:
        resolution_option.add_item(value)
    UIFactory.add_labeled_control(options, "分辨率", resolution_option)

    fullscreen_check = CheckButton.new()
    fullscreen_check.text = "开启全屏"
    UIFactory.add_labeled_control(options, "显示模式", fullscreen_check)

    health_option = OptionButton.new()
    UIFactory.style_option(health_option)
    for item in HEALTH_MODES:
        health_option.add_item(str(item.name))
    UIFactory.add_labeled_control(options, "单位血量", health_option)

    show_fps_check = CheckButton.new()
    show_fps_check.text = "显示帧率"
    UIFactory.add_labeled_control(options, "性能信息", show_fps_check)

    options.add_child(_section_title("战斗信息"))
    damage_numbers_check = CheckButton.new()
    damage_numbers_check.text = "在单位头顶显示受到的伤害"
    UIFactory.add_labeled_control(options, "伤害数字", damage_numbers_check)

    heal_numbers_check = CheckButton.new()
    heal_numbers_check.text = "在单位头顶显示生命恢复"
    UIFactory.add_labeled_control(options, "回血数字", heal_numbers_check)

    health_values_check = CheckButton.new()
    health_values_check.text = "在血条上显示当前生命值 / 最大生命值"
    UIFactory.add_labeled_control(options, "具体生命值", health_values_check)

    experience_check = CheckButton.new()
    experience_check.text = "在选中单位头顶显示经验值"
    UIFactory.add_labeled_control(options, "经验值", experience_check)

    options.add_child(_section_title("游戏与镜头"))
    game_speed_option = OptionButton.new()
    UIFactory.style_option(game_speed_option)
    for speed in GAME_SPEEDS:
        game_speed_option.add_item("%.2f 倍" % speed)
    UIFactory.add_labeled_control(options, "游戏速度", game_speed_option)

    var mouse_row = _make_slider_row("鼠标速度", 0.50, 2.00, 0.05)
    mouse_speed_slider = mouse_row.slider
    mouse_speed_value = mouse_row.value_label
    options.add_child(mouse_row.row)
    mouse_speed_slider.value_changed.connect(func(value): mouse_speed_value.text = "%.2f×" % value)

    var scroll_row = _make_slider_row("镜头速度", 300.0, 1200.0, 25.0)
    scroll_speed_slider = scroll_row.slider
    scroll_speed_value = scroll_row.value_label
    options.add_child(scroll_row.row)
    scroll_speed_slider.value_changed.connect(func(value): scroll_speed_value.text = "%d" % int(value))

    edge_scroll_check = CheckButton.new()
    edge_scroll_check.text = "鼠标接近屏幕边缘时滚动画面"
    UIFactory.add_labeled_control(options, "边缘滚屏", edge_scroll_check)

    options.add_child(_section_title("音频"))
    var master_row = _make_slider_row("主音量", 0.0, 1.0, 0.05)
    master_slider = master_row.slider
    master_value = master_row.value_label
    options.add_child(master_row.row)
    master_slider.value_changed.connect(func(value): master_value.text = "%d%%" % int(round(value * 100.0)))

    voices_check = CheckButton.new()
    voices_check.text = "启用系统中文文字转语音"
    UIFactory.add_labeled_control(options, "单位语音", voices_check)

    var voice_row = _make_slider_row("语音音量", 0.0, 1.0, 0.05)
    voice_slider = voice_row.slider
    voice_value = voice_row.value_label
    options.add_child(voice_row.row)
    voice_slider.value_changed.connect(func(value): voice_value.text = "%d%%" % int(round(value * 100.0)))

    status_label = UIFactory.muted_label("", 13)
    status_label.custom_minimum_size.y = 24
    root.add_child(status_label)

    var actions = HBoxContainer.new()
    actions.alignment = BoxContainer.ALIGNMENT_END
    actions.add_theme_constant_override("separation", 10)
    root.add_child(actions)

    var reset = Button.new()
    reset.text = "恢复默认"
    UIFactory.style_button(reset)
    reset.custom_minimum_size = Vector2(150, 42)
    reset.pressed.connect(_reset_defaults)
    actions.add_child(reset)

    var back = Button.new()
    back.text = "返回"
    UIFactory.style_button(back)
    back.custom_minimum_size = Vector2(150, 42)
    back.pressed.connect(func(): back_requested.emit())
    actions.add_child(back)

    var apply = Button.new()
    apply.text = "应用并保存"
    UIFactory.style_button(apply, true)
    apply.custom_minimum_size = Vector2(180, 42)
    apply.pressed.connect(_apply_values)
    actions.add_child(apply)

func _section_title(text):
    var label = UIFactory.heading(text, 19)
    label.add_theme_color_override("font_color", Color("#78BDD6"))
    label.custom_minimum_size.y = 32
    return label

func _make_slider_row(caption, minimum, maximum, step):
    var row = HBoxContainer.new()
    row.add_theme_constant_override("separation", 16)
    var label = Label.new()
    label.text = caption
    label.custom_minimum_size = Vector2(120, 36)
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.add_theme_color_override("font_color", Color("#C9D5DB"))
    row.add_child(label)
    var slider = HSlider.new()
    slider.min_value = minimum
    slider.max_value = maximum
    slider.step = step
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.custom_minimum_size = Vector2(300, 36)
    row.add_child(slider)
    var value_label = Label.new()
    value_label.custom_minimum_size = Vector2(72, 36)
    value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    row.add_child(value_label)
    return {"row": row, "slider": slider, "value_label": value_label}

func _load_values():
    var settings = SaveManager.settings
    resolution_option.select(max(0, RESOLUTIONS.find(str(settings.get("resolution", "1280x720")))))
    fullscreen_check.button_pressed = bool(settings.get("fullscreen", false))
    var health_id = str(settings.get("health_bar_mode", "selected_damaged"))
    var health_index = 0
    for index in range(HEALTH_MODES.size()):
        if str(HEALTH_MODES[index].id) == health_id:
            health_index = index
            break
    health_option.select(health_index)
    var speed = float(settings.get("game_speed", 1.0))
    var speed_index = 0
    var nearest = INF
    for index in range(GAME_SPEEDS.size()):
        var distance = abs(float(GAME_SPEEDS[index]) - speed)
        if distance < nearest:
            nearest = distance
            speed_index = index
    game_speed_option.select(speed_index)
    mouse_speed_slider.value = float(settings.get("mouse_speed", 1.0))
    scroll_speed_slider.value = float(settings.get("scroll_speed", 650.0))
    master_slider.value = float(settings.get("master_volume", 0.8))
    voice_slider.value = float(settings.get("voice_volume", 0.75))
    voices_check.button_pressed = bool(settings.get("unit_voices", true))
    edge_scroll_check.button_pressed = bool(settings.get("edge_scroll", true))
    show_fps_check.button_pressed = bool(settings.get("show_fps", false))
    damage_numbers_check.button_pressed = bool(settings.get("show_damage_numbers", true))
    heal_numbers_check.button_pressed = bool(settings.get("show_heal_numbers", true))
    health_values_check.button_pressed = bool(settings.get("show_health_values", true))
    experience_check.button_pressed = bool(settings.get("show_experience", true))
    mouse_speed_value.text = "%.2f×" % mouse_speed_slider.value
    scroll_speed_value.text = "%d" % int(scroll_speed_slider.value)
    master_value.text = "%d%%" % int(round(master_slider.value * 100.0))
    voice_value.text = "%d%%" % int(round(voice_slider.value * 100.0))

func _apply_values():
    SaveManager.settings["resolution"] = RESOLUTIONS[resolution_option.selected]
    SaveManager.settings["fullscreen"] = fullscreen_check.button_pressed
    SaveManager.settings["health_bar_mode"] = str(HEALTH_MODES[health_option.selected].id)
    SaveManager.settings["game_speed"] = float(GAME_SPEEDS[game_speed_option.selected])
    SaveManager.settings["mouse_speed"] = mouse_speed_slider.value
    SaveManager.settings["scroll_speed"] = scroll_speed_slider.value
    SaveManager.settings["master_volume"] = master_slider.value
    SaveManager.settings["voice_volume"] = voice_slider.value
    SaveManager.settings["unit_voices"] = voices_check.button_pressed
    SaveManager.settings["edge_scroll"] = edge_scroll_check.button_pressed
    SaveManager.settings["show_fps"] = show_fps_check.button_pressed
    SaveManager.settings["show_damage_numbers"] = damage_numbers_check.button_pressed
    SaveManager.settings["show_heal_numbers"] = heal_numbers_check.button_pressed
    SaveManager.settings["show_health_values"] = health_values_check.button_pressed
    SaveManager.settings["show_experience"] = experience_check.button_pressed
    SaveManager.apply_and_save()
    status_label.text = "正在应用显示设置……"
    status_label.add_theme_color_override("font_color", Color("#9FB0BA"))
    await get_tree().process_frame
    await get_tree().process_frame
    status_label.text = SaveManager.get_display_status_text()
    status_label.add_theme_color_override("font_color", Color("#E7CB6B") if OS.has_feature("editor") else Color("#74D98A"))

func _reset_defaults():
    SaveManager.reset_settings()
    _load_values()
    status_label.text = "正在恢复默认显示设置……"
    await get_tree().process_frame
    await get_tree().process_frame
    status_label.text = "已恢复默认设置。" + SaveManager.get_display_status_text()
    status_label.add_theme_color_override("font_color", Color("#E7CB6B"))

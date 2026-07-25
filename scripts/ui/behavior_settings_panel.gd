extends Control

signal applied(settings)
signal closed

const UIFactory = preload("res://scripts/ui/ui_factory.gd")

var selection_label: Label
var guard_check: CheckBox
var guard_range_slider: HSlider
var guard_range_value: Label
var auto_attack_check: CheckBox
var chase_check: CheckBox
var chase_distance_slider: HSlider
var chase_distance_value: Label
var support_same_check: CheckBox
var support_allied_check: CheckBox
var support_range_slider: HSlider
var support_range_value: Label
var current_units = []

func _ready():
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP
    process_mode = Node.PROCESS_MODE_ALWAYS
    _build_ui()
    visible = false

func _panel_style(bg, border, radius = 4):
    var style = UIFactory.panel_style(bg, border, radius)
    style.content_margin_left = 16
    style.content_margin_right = 16
    style.content_margin_top = 14
    style.content_margin_bottom = 14
    return style

func _build_ui():
    var dim = ColorRect.new()
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dim.color = Color(0.0, 0.0, 0.0, 0.58)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(dim)

    var panel = PanelContainer.new()
    panel.set_anchors_preset(Control.PRESET_CENTER)
    panel.position = Vector2(-260, -285)
    panel.size = Vector2(520, 570)
    panel.add_theme_stylebox_override("panel", _panel_style(Color("#102028"), Color("#6E8996"), 5))
    add_child(panel)

    var box = VBoxContainer.new()
    box.add_theme_constant_override("separation", 9)
    panel.add_child(box)

    var title_row = HBoxContainer.new()
    box.add_child(title_row)
    var title = Label.new()
    title.text = "单位智能逻辑"
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title.add_theme_font_size_override("font_size", 20)
    title.add_theme_color_override("font_color", Color("#8ED3EC"))
    title_row.add_child(title)
    var close_button = Button.new()
    close_button.text = "关闭 [Esc]"
    close_button.focus_mode = Control.FOCUS_NONE
    close_button.pressed.connect(close)
    title_row.add_child(close_button)

    selection_label = Label.new()
    selection_label.add_theme_color_override("font_color", Color("#AFC1C8"))
    selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    box.add_child(selection_label)

    var note = Label.new()
    note.text = "设置会应用到当前选中的全部可移动单位。H 键原地不动时始终禁止追击；S 键只中断当前指令，随后恢复这里配置的自主逻辑。"
    note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    note.add_theme_font_size_override("font_size", 12)
    note.add_theme_color_override("font_color", Color("#7F98A3"))
    box.add_child(note)

    box.add_child(HSeparator.new())

    guard_check = _make_check("启用警戒", "开启后会扫描攻击距离之外、警戒范围以内的敌人。")
    guard_check.toggled.connect(_update_enabled_states)
    box.add_child(guard_check)
    var guard_row = _make_slider_row("警戒范围", 64.0, 900.0, 10.0)
    guard_range_slider = guard_row[0]
    guard_range_value = guard_row[1]
    box.add_child(guard_row[2])

    auto_attack_check = _make_check("自动攻击进入攻击范围的敌人", "关闭后单位不会自主开火，但仍会执行玩家明确下达的攻击命令。")
    auto_attack_check.toggled.connect(_update_enabled_states)
    box.add_child(auto_attack_check)

    chase_check = _make_check("允许追击", "非 H 状态下，单位可离开警戒岗位进行有限距离追击。")
    chase_check.toggled.connect(_update_enabled_states)
    box.add_child(chase_check)
    var chase_row = _make_slider_row("最大追击距离", 0.0, 700.0, 10.0)
    chase_distance_slider = chase_row[0]
    chase_distance_value = chase_row[1]
    box.add_child(chase_row[2])

    box.add_child(HSeparator.new())

    support_same_check = _make_check("支援附近的己方单位", "同一玩家控制的单位受击时，空闲单位可前往支援。")
    support_same_check.toggled.connect(_update_enabled_states)
    box.add_child(support_same_check)
    support_allied_check = _make_check("支援附近的非己方友军", "支援同队伍、但由其他玩家控制的友军单位。")
    support_allied_check.toggled.connect(_update_enabled_states)
    box.add_child(support_allied_check)
    var support_row = _make_slider_row("支援距离", 0.0, 900.0, 10.0)
    support_range_slider = support_row[0]
    support_range_value = support_row[1]
    box.add_child(support_row[2])

    var spacer = Control.new()
    spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
    box.add_child(spacer)

    var button_row = HBoxContainer.new()
    button_row.alignment = BoxContainer.ALIGNMENT_END
    button_row.add_theme_constant_override("separation", 8)
    box.add_child(button_row)
    var reset_button = Button.new()
    reset_button.text = "恢复推荐值"
    reset_button.focus_mode = Control.FOCUS_NONE
    reset_button.pressed.connect(_reset_recommended)
    button_row.add_child(reset_button)
    var apply_button = Button.new()
    apply_button.text = "应用到所选单位"
    apply_button.focus_mode = Control.FOCUS_NONE
    apply_button.pressed.connect(_apply)
    button_row.add_child(apply_button)

func _make_check(text_value, tooltip):
    var check = CheckBox.new()
    check.text = text_value
    check.tooltip_text = tooltip
    check.focus_mode = Control.FOCUS_NONE
    check.add_theme_font_size_override("font_size", 14)
    return check

func _make_slider_row(title, minimum, maximum, step):
    var row = HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    var label = Label.new()
    label.text = title
    label.custom_minimum_size.x = 116
    row.add_child(label)
    var slider = HSlider.new()
    slider.min_value = minimum
    slider.max_value = maximum
    slider.step = step
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.focus_mode = Control.FOCUS_NONE
    row.add_child(slider)
    var value_label = Label.new()
    value_label.custom_minimum_size.x = 54
    value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    row.add_child(value_label)
    slider.value_changed.connect(func(value): value_label.text = "%.0f" % value)
    return [slider, value_label, row]

func open_for_units(units):
    current_units = []
    for unit in units:
        if is_instance_valid(unit) and unit.has_method("get_behavior_settings"):
            current_units.append(unit)
    if current_units.is_empty():
        return
    var first = current_units[0]
    var settings = first.get_behavior_settings()
    selection_label.text = "当前选择：%d 个单位。混合选择时显示第一个单位的数值，点击应用后统一覆盖。" % current_units.size()
    guard_check.button_pressed = bool(settings.get("guard_enabled", true))
    guard_range_slider.value = float(settings.get("guard_range", 250.0))
    auto_attack_check.button_pressed = bool(settings.get("auto_attack_enabled", true))
    chase_check.button_pressed = bool(settings.get("chase_enabled", true))
    chase_distance_slider.value = float(settings.get("chase_distance", 110.0))
    support_same_check.button_pressed = bool(settings.get("support_same_owner_enabled", true))
    support_allied_check.button_pressed = bool(settings.get("support_allied_enabled", false))
    support_range_slider.value = float(settings.get("support_range", 250.0))
    _refresh_value_labels()
    _update_enabled_states()
    visible = true
    move_to_front()

func _refresh_value_labels():
    guard_range_value.text = "%.0f" % guard_range_slider.value
    chase_distance_value.text = "%.0f" % chase_distance_slider.value
    support_range_value.text = "%.0f" % support_range_slider.value

func _update_enabled_states(_unused = false):
    guard_range_slider.editable = guard_check.button_pressed and auto_attack_check.button_pressed
    chase_check.disabled = not auto_attack_check.button_pressed
    chase_distance_slider.editable = auto_attack_check.button_pressed and chase_check.button_pressed
    support_range_slider.editable = support_same_check.button_pressed or support_allied_check.button_pressed

func _reset_recommended():
    guard_check.button_pressed = true
    guard_range_slider.value = 250.0
    auto_attack_check.button_pressed = true
    chase_check.button_pressed = true
    chase_distance_slider.value = 120.0
    support_same_check.button_pressed = true
    support_allied_check.button_pressed = false
    support_range_slider.value = 250.0
    _refresh_value_labels()
    _update_enabled_states()

func _apply():
    var settings = {
        "guard_enabled": guard_check.button_pressed,
        "guard_range": guard_range_slider.value,
        "auto_attack_enabled": auto_attack_check.button_pressed,
        "chase_enabled": chase_check.button_pressed,
        "chase_distance": chase_distance_slider.value,
        "support_same_owner_enabled": support_same_check.button_pressed,
        "support_allied_enabled": support_allied_check.button_pressed,
        "support_range": support_range_slider.value
    }
    applied.emit(settings)
    close()

func close():
    if not visible:
        return
    visible = false
    current_units.clear()
    closed.emit()

func is_open():
    return visible

extends Control

signal start_requested(config)
signal back_requested

const UIFactory = preload("res://scripts/ui/ui_factory.gd")
const BackgroundGrid = preload("res://scripts/ui/background_grid.gd")

var selected_mission = 1
var details: VBoxContainer
var mission_buttons = {}

func _ready():
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _build_ui()

func _build_ui():
    var bg = BackgroundGrid.new()
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(bg)

    var margin = MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_left", 36)
    margin.add_theme_constant_override("margin_right", 36)
    margin.add_theme_constant_override("margin_top", 24)
    margin.add_theme_constant_override("margin_bottom", 28)
    add_child(margin)

    var root_box = VBoxContainer.new()
    root_box.add_theme_constant_override("separation", 18)
    margin.add_child(root_box)

    var header = HBoxContainer.new()
    header.add_theme_constant_override("separation", 18)
    root_box.add_child(header)

    var back = Button.new()
    back.text = "返回"
    back.custom_minimum_size = Vector2(190, 50)
    UIFactory.style_button(back)
    back.pressed.connect(func(): back_requested.emit())
    header.add_child(back)

    var title = UIFactory.heading("战役", 32)
    title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(title)

    var panel = PanelContainer.new()
    panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    panel.add_theme_stylebox_override("panel", UIFactory.panel_style(Color(0.05, 0.075, 0.09, 0.96), Color("#3A5562"), 6))
    root_box.add_child(panel)

    var content_margin = MarginContainer.new()
    content_margin.add_theme_constant_override("margin_left", 20)
    content_margin.add_theme_constant_override("margin_right", 20)
    content_margin.add_theme_constant_override("margin_top", 18)
    content_margin.add_theme_constant_override("margin_bottom", 18)
    panel.add_child(content_margin)

    var content = HBoxContainer.new()
    content.add_theme_constant_override("separation", 30)
    content_margin.add_child(content)

    var list = VBoxContainer.new()
    list.custom_minimum_size = Vector2(340, 0)
    list.add_theme_constant_override("separation", 9)
    content.add_child(list)
    list.add_child(UIFactory.heading("联合防卫军", 22))

    for item in [[1, "01  基础训练"], [2, "02  边境反击"]]:
        var button = Button.new()
        button.text = str(item[1])
        button.custom_minimum_size = Vector2(320, 66)
        UIFactory.style_button(button, int(item[0]) == selected_mission)
        button.pressed.connect(_select_mission.bind(int(item[0])))
        list.add_child(button)
        mission_buttons[int(item[0])] = button

    var separator = VSeparator.new()
    content.add_child(separator)

    details = VBoxContainer.new()
    details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    details.size_flags_vertical = Control.SIZE_EXPAND_FILL
    details.add_theme_constant_override("separation", 14)
    content.add_child(details)
    _refresh_details()

func _select_mission(mission_id):
    selected_mission = mission_id
    for id_value in mission_buttons:
        UIFactory.style_button(mission_buttons[id_value], int(id_value) == selected_mission)
    _refresh_details()

func _refresh_details():
    for child in details.get_children():
        child.queue_free()
    var title_text = "基础训练：前线接管"
    var description = "完成选择、移动和攻击训练，然后摧毁敌方前哨建造中心。"
    var objectives = ["选择你的部队", "移动部队越过训练线", "摧毁敌方前哨指挥部"]
    if selected_mission == 2:
        title_text = "边境反击：扩大战线"
        description = "大型陆战地图。敌军拥有更多步兵、载具和防御设施，摧毁其前线司令部。"
        objectives = ["建立基础经济", "击退敌军增援", "摧毁敌军司令部"]

    details.add_child(UIFactory.heading(title_text, 28))
    var desc = UIFactory.muted_label(description, 16)
    desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    details.add_child(desc)
    for objective in objectives:
        details.add_child(UIFactory.muted_label("□  " + objective, 15))

    var spacer = Control.new()
    spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
    details.add_child(spacer)
    details.add_child(HSeparator.new())
    var start = Button.new()
    start.text = "开始任务"
    start.custom_minimum_size.y = 58
    UIFactory.style_button(start, true)
    start.pressed.connect(func():
        start_requested.emit(GameConfig.make_training_campaign() if selected_mission == 1 else GameConfig.make_training_campaign_02())
    )
    details.add_child(start)

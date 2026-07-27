extends Control

signal skirmish_requested
signal campaign_requested
signal settings_requested
signal lan_requested
signal ra2_database_requested
signal quit_requested

const UIFactory = preload("res://scripts/ui/ui_factory.gd")
const BackgroundGrid = preload("res://scripts/ui/background_grid.gd")

func _ready():
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _build_ui()

func _build_ui():
    var background = BackgroundGrid.new()
    background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(background)

    var title_stack = VBoxContainer.new()
    title_stack.position = Vector2(72, 72)
    title_stack.size = Vector2(610, 170)
    title_stack.add_theme_constant_override("separation", 4)
    add_child(title_stack)

    var eyebrow = UIFactory.muted_label("原创程序化 RTS 框架 · GODOT 4.7", 15)
    eyebrow.add_theme_color_override("font_color", Color("#72B6D1"))
    title_stack.add_child(eyebrow)
    var title = UIFactory.heading("钢铁子午线", 56)
    title.add_theme_color_override("font_color", Color("#F1F6F8"))
    title_stack.add_child(title)
    var en_title = UIFactory.muted_label("IRON MERIDIAN — REAL-TIME STRATEGY", 16)
    title_stack.add_child(en_title)

    var menu_panel = PanelContainer.new()
    menu_panel.position = Vector2(74, 272)
    menu_panel.size = Vector2(360, 390)
    menu_panel.add_theme_stylebox_override("panel", UIFactory.panel_style(Color(0.06, 0.09, 0.12, 0.94), Color("#3C5968"), 5))
    add_child(menu_panel)

    var menu = VBoxContainer.new()
    menu.add_theme_constant_override("separation", 12)
    menu_panel.add_child(menu)

    var campaign = Button.new()
    campaign.text = "战役"
    campaign.tooltip_text = "进入训练战役"
    UIFactory.style_button(campaign, true)
    campaign.pressed.connect(func(): campaign_requested.emit())
    menu.add_child(campaign)

    var skirmish = Button.new()
    skirmish.text = "遭遇战"
    skirmish.tooltip_text = "配置地图、阵营、位置、颜色和队伍"
    UIFactory.style_button(skirmish)
    skirmish.pressed.connect(func(): skirmish_requested.emit())
    menu.add_child(skirmish)


    var lan = Button.new()
    lan.text = "局域网"
    lan.tooltip_text = "创建、搜索并加入局域网房间"
    UIFactory.style_button(lan)
    lan.pressed.connect(func(): lan_requested.emit())
    menu.add_child(lan)

    var database = Button.new()
    database.text = "RA2 / YR 资源数据库"
    database.tooltip_text = "浏览单位、建筑、CSF 文本、声音事件、地图和字段来源"
    UIFactory.style_button(database)
    database.pressed.connect(func(): ra2_database_requested.emit())
    menu.add_child(database)

    var settings = Button.new()
    settings.text = "设置"
    UIFactory.style_button(settings)
    settings.pressed.connect(func(): settings_requested.emit())
    menu.add_child(settings)

    var quit = Button.new()
    quit.text = "退出"
    UIFactory.style_button(quit)
    quit.pressed.connect(func(): quit_requested.emit())
    menu.add_child(quit)

    var feature_panel = PanelContainer.new()
    feature_panel.anchor_left = 1.0
    feature_panel.anchor_right = 1.0
    feature_panel.offset_left = -486
    feature_panel.offset_right = -56
    feature_panel.offset_top = 90
    feature_panel.offset_bottom = 602
    feature_panel.add_theme_stylebox_override("panel", UIFactory.panel_style(Color(0.055, 0.078, 0.095, 0.93), Color("#355361"), 5))
    add_child(feature_panel)
    var feature_box = VBoxContainer.new()
    feature_box.add_theme_constant_override("separation", 13)
    feature_panel.add_child(feature_box)
    feature_box.add_child(UIFactory.heading("第一阶段底座", 24))
    feature_box.add_child(UIFactory.muted_label("不是对既有作品美术、剧情或商标的复制，而是一套可扩展的经典 2D RTS 机制实现。", 15))
    feature_box.add_child(HSeparator.new())
    for line in [
        "矩形瓦片地图与战争迷雾",
        "框选、编队式移动、攻击指令",
        "矿石采集、资金、电力与建造",
        "步兵/载具生产和阵营修正",
        "炮塔、AI 进攻、胜负判定",
        "战役训练关与遭遇战配置"
    ]:
        var row = HBoxContainer.new()
        var marker = Label.new()
        marker.text = "▣"
        marker.add_theme_color_override("font_color", Color("#70AFC7"))
        row.add_child(marker)
        row.add_child(UIFactory.muted_label(line, 15))
        feature_box.add_child(row)

    var footer: Label = UIFactory.muted_label("v0.12.0 · CSF 本地化、音频银行与官方地图索引 · Godot 4.7.1", 13)
    footer.anchor_top = 1.0
    footer.anchor_bottom = 1.0
    footer.offset_left = 74
    footer.offset_top = -48
    footer.offset_right = 650
    footer.offset_bottom = -20
    add_child(footer)

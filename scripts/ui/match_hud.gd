extends CanvasLayer

signal structure_requested(building_id)
signal unit_requested(unit_id)
signal pause_requested
signal minimap_world_requested(world_position)
signal minimap_command_requested(world_position)
signal command_requested(command_id)
signal behavior_settings_requested(settings)

const UIFactory = preload("res://scripts/ui/ui_factory.gd")
const Minimap = preload("res://scripts/game/minimap.gd")
const EntityPortrait = preload("res://scripts/ui/entity_portrait.gd")
const ProductionTile = preload("res://scripts/ui/production_tile.gd")
const ProductionCategoryButton = preload("res://scripts/ui/production_category_button.gd")
const CommandSkillButton = preload("res://scripts/ui/command_skill_button.gd")
const SidebarToolButton = preload("res://scripts/ui/sidebar_tool_button.gd")
const BehaviorSettingsPanel = preload("res://scripts/ui/behavior_settings_panel.gd")

const COMMAND_DEFINITIONS = {
    "move": {"name": "移动", "effect": "移动到指定位置；右键仍可快捷移动，按住 Shift 可追加路径点。", "hotkey": "M", "icon": "move"},
    "attack_move": {"name": "攻击移动", "effect": "向目标点推进并攻击沿途发现的敌人。", "hotkey": "A", "icon": "attack"},
    "stop": {"name": "停止", "effect": "立即中断并清空当前命令；下一帧恢复自主警戒与自动攻击。", "hotkey": "S", "icon": "stop"},
    "hold": {"name": "原地不动", "effect": "保持当前位置，只攻击射程内敌人。", "hotkey": "H", "icon": "hold"},
    "patrol": {"name": "巡逻", "effect": "依次设置多个巡逻点；再次点击第一个巡逻点形成闭环。", "hotkey": "P", "icon": "patrol"},
    "harvest": {"name": "采集矿石", "effect": "指定一个仍有储量的矿石格进行采集和返厂卸矿。", "hotkey": "C", "icon": "harvest"},
    "rally": {"name": "设置集结点", "effect": "设置该生产建筑新单位的出生后前往位置；选中生产建筑后可直接右键地面快捷设置。", "hotkey": "右键", "icon": "rally"},
    "primary": {"name": "设为主要", "effect": "将该建筑设为同类型单位的主要生产出口。", "hotkey": "Z", "icon": "primary"},
    "building_attack": {"name": "攻击", "effect": "命令防御建筑攻击指定敌方目标。", "hotkey": "A", "icon": "attack"},
    "building_stop": {"name": "停止", "effect": "停止防御建筑当前攻击并暂停自动索敌，重新下达攻击命令后恢复。", "hotkey": "S", "icon": "stop"},
    "force_attack": {"name": "强制攻击", "effect": "攻击指定地面、树木、矿石或其他可破坏目标。", "hotkey": "Ctrl+A", "icon": "attack"},
    "behavior": {"name": "智能逻辑", "effect": "打开单位智能逻辑面板，配置警戒、自动攻击、追击和友军支援。", "hotkey": "G", "icon": "hold"}
}

const SIDE_WIDTH = 282.0
const BOTTOM_HEIGHT = 224.0
const NAV_HEIGHT = 38.0

var match_ref
var root_control
var credits_label
var power_label
var objective_title
var objective_detail_text = ""
var build_status
var selection_label
var info_label
var portrait
var notification_label
var fps_label
var notification_timer = 0.0
var info_refresh_timer = 0.0
var structure_buttons = {}
var unit_buttons = {}
var command_buttons = {}
var command_slots = []
var command_grid
var command_card_signature = ""
var minimap
var current_selection = []
var active_command_mode = ""
var category_pages = {}
var category_buttons = {}
var category_name_label
var active_category = "primary"
var sidebar_tool_buttons = {}
var behavior_panel

func setup(next_match, map_ref):
    match_ref = next_match
    layer = 20
    _build_ui(map_ref)
    EventBus.objective_changed.connect(_on_objective_changed)
    EventBus.notification_requested.connect(show_notification)

func get_sidebar_width():
    return SIDE_WIDTH

func get_bottom_height():
    return BOTTOM_HEIGHT

func get_navigation_height():
    return NAV_HEIGHT

func _hud_panel_style(bg, border, radius = 2, horizontal_padding = 6.0, vertical_padding = 5.0):
    var style = UIFactory.panel_style(bg, border, radius)
    style.content_margin_left = horizontal_padding
    style.content_margin_right = horizontal_padding
    style.content_margin_top = vertical_padding
    style.content_margin_bottom = vertical_padding
    return style

func _apply_compact_button_style(button):
    var states = {
        "normal": [Color("#202D38"), Color("#607D8B")],
        "hover": [Color("#2B3C49"), Color("#8FB4C6")],
        "pressed": [Color("#16212A"), Color("#8FB4C6")],
        "focus": [Color("#2B3C49"), Color("#B9D7E5")],
        "disabled": [Color("#11191E"), Color("#31434B")]
    }
    for state_name in states:
        var colors = states[state_name]
        var style = UIFactory.button_style(colors[0], colors[1], 2)
        style.content_margin_left = 3
        style.content_margin_right = 3
        style.content_margin_top = 2
        style.content_margin_bottom = 2
        button.add_theme_stylebox_override(state_name, style)
    button.add_theme_color_override("font_color", Color("#EEF5F7"))
    button.add_theme_color_override("font_hover_color", Color.WHITE)
    button.add_theme_color_override("font_disabled_color", Color("#52636B"))

func _build_ui(map_ref):
    root_control = Control.new()
    root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(root_control)

    _build_top_bar()
    _build_production_sidebar()
    _build_bottom_command_panel(map_ref)
    _build_notification()
    behavior_panel = BehaviorSettingsPanel.new()
    root_control.add_child(behavior_panel)
    behavior_panel.applied.connect(func(settings): behavior_settings_requested.emit(settings))

func _build_top_bar():
    var top_bar = PanelContainer.new()
    top_bar.anchor_right = 1.0
    top_bar.offset_bottom = NAV_HEIGHT
    top_bar.add_theme_stylebox_override("panel", _hud_panel_style(Color(0.025, 0.043, 0.052, 0.985), Color("#425964"), 0, 7, 2))
    root_control.add_child(top_bar)

    var top_row = HBoxContainer.new()
    top_row.add_theme_constant_override("separation", 10)
    top_bar.add_child(top_row)

    var mission_tag = Label.new()
    mission_tag.text = "任务"
    mission_tag.custom_minimum_size.x = 50
    mission_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    mission_tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    mission_tag.add_theme_font_size_override("font_size", 13)
    mission_tag.add_theme_color_override("font_color", Color("#75C5E3"))
    top_row.add_child(mission_tag)

    objective_title = Label.new()
    objective_title.text = "等待任务信息"
    objective_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    objective_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    objective_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    objective_title.add_theme_font_size_override("font_size", 14)
    objective_title.add_theme_color_override("font_color", Color("#DCE8ED"))
    objective_title.tooltip_text = "当前任务"
    top_row.add_child(objective_title)

    var controls_hint = Label.new()
    controls_hint.text = "F2 全选作战单位  ·  Shift 路径点"
    controls_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    controls_hint.add_theme_font_size_override("font_size", 11)
    controls_hint.add_theme_color_override("font_color", Color("#8099A5"))
    top_row.add_child(controls_hint)

    fps_label = Label.new()
    fps_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    fps_label.custom_minimum_size.x = 50
    fps_label.add_theme_font_size_override("font_size", 10)
    fps_label.add_theme_color_override("font_color", Color("#8FB4C4"))
    top_row.add_child(fps_label)

    var pause = Button.new()
    pause.text = "菜单  [Esc]"
    pause.focus_mode = Control.FOCUS_NONE
    _apply_compact_button_style(pause)
    pause.custom_minimum_size = Vector2(112, 30)
    pause.add_theme_font_size_override("font_size", 12)
    pause.pressed.connect(func(): pause_requested.emit())
    top_row.add_child(pause)

func _build_production_sidebar():
    var side = PanelContainer.new()
    side.anchor_left = 1.0
    side.anchor_right = 1.0
    side.anchor_bottom = 1.0
    side.offset_left = -SIDE_WIDTH
    side.offset_top = NAV_HEIGHT
    side.offset_bottom = -BOTTOM_HEIGHT
    side.add_theme_stylebox_override("panel", _hud_panel_style(Color(0.035, 0.055, 0.065, 0.985), Color("#4B606A"), 0, 8, 6))
    root_control.add_child(side)

    var side_box = VBoxContainer.new()
    side_box.add_theme_constant_override("separation", 4)
    side.add_child(side_box)

    var resource_panel = PanelContainer.new()
    resource_panel.custom_minimum_size.y = 38
    resource_panel.add_theme_stylebox_override("panel", _hud_panel_style(Color("#0C171C"), Color("#36515C"), 2, 7, 3))
    side_box.add_child(resource_panel)
    var resource_row = HBoxContainer.new()
    resource_row.add_theme_constant_override("separation", 8)
    resource_panel.add_child(resource_row)

    credits_label = Label.new()
    credits_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    credits_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    credits_label.add_theme_font_size_override("font_size", 14)
    credits_label.add_theme_color_override("font_color", Color("#E5C859"))
    credits_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    resource_row.add_child(credits_label)

    power_label = Label.new()
    power_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    power_label.add_theme_font_size_override("font_size", 12)
    resource_row.add_child(power_label)

    var tool_row = HBoxContainer.new()
    tool_row.add_theme_constant_override("separation", 6)
    side_box.add_child(tool_row)
    var repair_tool = SidebarToolButton.new()
    repair_tool.setup("repair_building", "维修建筑", "点击后选择受损的己方建筑；再次点击可停止维修。")
    repair_tool.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    repair_tool.pressed.connect(func(): command_requested.emit("repair_building"))
    tool_row.add_child(repair_tool)
    sidebar_tool_buttons["repair_building"] = repair_tool
    var sell_tool = SidebarToolButton.new()
    sell_tool.setup("sell_building", "变卖建筑", "按建筑当前生命值返还原价的25%至75%，并反向播放建造动画。")
    sell_tool.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    sell_tool.pressed.connect(func(): command_requested.emit("sell_building"))
    tool_row.add_child(sell_tool)
    sidebar_tool_buttons["sell_building"] = sell_tool

    var heading_row = HBoxContainer.new()
    heading_row.add_theme_constant_override("separation", 6)
    side_box.add_child(heading_row)
    var production_heading = UIFactory.heading("生产与建造", 16)
    production_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    production_heading.add_theme_color_override("font_color", Color("#83BED4"))
    heading_row.add_child(production_heading)
    category_name_label = UIFactory.muted_label("主要建筑", 11)
    category_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    category_name_label.custom_minimum_size.x = 72
    heading_row.add_child(category_name_label)

    var category_row = HBoxContainer.new()
    category_row.alignment = BoxContainer.ALIGNMENT_CENTER
    category_row.add_theme_constant_override("separation", 5)
    side_box.add_child(category_row)

    var page_stack = Control.new()
    page_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
    page_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    side_box.add_child(page_stack)

    var definitions = [
        ["primary", "主要建筑", "Q", ["power", "barracks", "refinery", "war_factory", "repair_bay"], "structure"],
        ["defense", "防御建筑", "W", ["turret", "bunker"], "structure"],
        ["infantry", "士兵", "E", ["rifle", "rocket"], "unit"],
        ["vehicle", "载具", "R", ["scout", "tank", "harvester"], "unit"],
        ["air", "飞行器", "T", [], "unit"],
        ["naval", "船", "Y", [], "unit"]
    ]
    for definition in definitions:
        var category_id = str(definition[0])
        var title = str(definition[1])
        var hotkey = str(definition[2])
        var button = ProductionCategoryButton.new()
        button.setup(category_id, title, hotkey)
        button.pressed.connect(_switch_production_category.bind(category_id, title))
        button.mouse_entered.connect(_on_category_hover.bind(title))
        button.mouse_exited.connect(_on_category_hover_exit)
        category_row.add_child(button)
        category_buttons[category_id] = button
        _add_production_category(page_stack, category_id, definition[3], str(definition[4]))
    _switch_production_category("primary", "主要建筑")

    build_status = UIFactory.muted_label("建造队列空闲", 10)
    build_status.custom_minimum_size.y = 30
    build_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    build_status.tooltip_text = "生产队列状态"
    side_box.add_child(build_status)

func _on_category_hover(title):
    category_name_label.text = str(title)

func _on_category_hover_exit():
    category_name_label.text = _category_title(active_category)

func _category_title(category_id):
    var names = {"primary": "主要建筑", "defense": "防御建筑", "infantry": "士兵", "vehicle": "载具", "air": "飞行器", "naval": "船"}
    return str(names.get(category_id, category_id))

func activate_production_category(category_id):
    _switch_production_category(str(category_id), _category_title(str(category_id)))

func _switch_production_category(category_id, title = ""):
    active_category = category_id
    category_name_label.text = title if title != "" else _category_title(category_id)
    for id_value in category_pages:
        category_pages[id_value].visible = id_value == category_id
    for id_value in category_buttons:
        category_buttons[id_value].set_active(id_value == category_id)

func _add_production_category(page_stack, category_id, ids, kind):
    var scroll = ScrollContainer.new()
    scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.visible = false
    page_stack.add_child(scroll)
    category_pages[category_id] = scroll
    var grid_box = GridContainer.new()
    grid_box.columns = 4
    grid_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    grid_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    grid_box.add_theme_constant_override("h_separation", 3)
    grid_box.add_theme_constant_override("v_separation", 3)
    scroll.add_child(grid_box)
    if ids.is_empty():
        var empty = UIFactory.muted_label("当前版本尚未配置此类别。", 11)
        empty.custom_minimum_size = Vector2(238, 48)
        grid_box.add_child(empty)
        return
    for id_value in ids:
        var data = GameConfig.buildings.get(id_value, {}) if kind == "structure" else GameConfig.units.get(id_value, {})
        var tile = ProductionTile.new()
        tile.setup(kind, id_value, data)
        tile.tooltip_text = _production_tooltip(kind, id_value, data)
        tile.pressed.connect(_emit_production_request.bind(kind, id_value))
        tile.gui_input.connect(_on_production_gui_input.bind(kind, id_value, tile))
        grid_box.add_child(tile)
        if kind == "structure":
            structure_buttons[id_value] = tile
        else:
            unit_buttons[id_value] = tile

func _build_bottom_command_panel(map_ref):
    var bottom = PanelContainer.new()
    bottom.anchor_top = 1.0
    bottom.anchor_bottom = 1.0
    bottom.anchor_right = 1.0
    bottom.offset_top = -BOTTOM_HEIGHT
    bottom.add_theme_stylebox_override("panel", _hud_panel_style(Color(0.025, 0.043, 0.052, 0.99), Color("#516A75"), 0, 8, 6))
    root_control.add_child(bottom)

    var row = HBoxContainer.new()
    row.add_theme_constant_override("separation", 8)
    bottom.add_child(row)

    var minimap_panel = PanelContainer.new()
    minimap_panel.custom_minimum_size = Vector2(244, 198)
    minimap_panel.add_theme_stylebox_override("panel", _hud_panel_style(Color("#0C1418"), Color("#607A85"), 2, 6, 6))
    row.add_child(minimap_panel)
    minimap = Minimap.new()
    minimap.setup(match_ref, map_ref)
    minimap.custom_minimum_size = Vector2(230, 184)
    minimap.world_clicked.connect(func(pos): minimap_world_requested.emit(pos))
    minimap.world_commanded.connect(func(pos): minimap_command_requested.emit(pos))
    minimap_panel.add_child(minimap)

    portrait = EntityPortrait.new()
    portrait.custom_minimum_size = Vector2(142, 190)
    row.add_child(portrait)

    var info_panel = PanelContainer.new()
    info_panel.custom_minimum_size = Vector2(354, 198)
    info_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    info_panel.add_theme_stylebox_override("panel", _hud_panel_style(Color("#101B21"), Color("#405964"), 2, 8, 6))
    row.add_child(info_panel)
    var info_box = VBoxContainer.new()
    info_box.add_theme_constant_override("separation", 2)
    info_panel.add_child(info_box)
    selection_label = Label.new()
    selection_label.text = "未选择单位"
    selection_label.add_theme_font_size_override("font_size", 15)
    selection_label.add_theme_color_override("font_color", Color("#E8F1F3"))
    info_box.add_child(selection_label)
    info_label = Label.new()
    info_label.clip_text = true
    info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    info_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
    info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    info_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
    info_label.add_theme_font_size_override("font_size", 12)
    info_label.add_theme_color_override("font_color", Color("#D9E5E9"))
    info_label.text = "选择单位或建筑后显示详细资料。"
    info_box.add_child(info_label)

    var skill_panel = PanelContainer.new()
    skill_panel.custom_minimum_size = Vector2(344, 198)
    skill_panel.add_theme_stylebox_override("panel", _hud_panel_style(Color("#101B21"), Color("#405964"), 2, 6, 5))
    row.add_child(skill_panel)
    var skill_box = VBoxContainer.new()
    skill_box.add_theme_constant_override("separation", 3)
    skill_panel.add_child(skill_box)
    var skill_heading = UIFactory.heading("技能栏", 14)
    skill_heading.custom_minimum_size.y = 20
    skill_box.add_child(skill_heading)

    command_grid = GridContainer.new()
    command_grid.columns = 6
    command_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    command_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
    command_grid.add_theme_constant_override("h_separation", 3)
    command_grid.add_theme_constant_override("v_separation", 3)
    skill_box.add_child(command_grid)

    for _index in range(24):
        var slot = CommandSkillButton.new()
        _apply_compact_button_style(slot)
        slot.pressed.connect(_on_command_slot_pressed.bind(slot))
        command_grid.add_child(slot)
        command_slots.append(slot)
    _refresh_command_card(true)

func _build_notification():
    notification_label = Label.new()
    notification_label.anchor_left = 0.5
    notification_label.anchor_right = 0.5
    notification_label.offset_left = -280
    notification_label.offset_right = 280
    notification_label.offset_top = 65
    notification_label.offset_bottom = 108
    notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    notification_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    notification_label.add_theme_font_size_override("font_size", 16)
    notification_label.add_theme_stylebox_override("normal", UIFactory.panel_style(Color(0.03, 0.05, 0.06, 0.93), Color("#5D7A87"), 3))
    notification_label.visible = false
    notification_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root_control.add_child(notification_label)

func _emit_production_request(kind, id_value):
    if kind == "structure":
        structure_requested.emit(id_value)
    else:
        unit_requested.emit(id_value)

func _on_production_gui_input(event, kind, id_value, button):
    if not (event is InputEventMouseButton):
        return
    if event.button_index != MOUSE_BUTTON_RIGHT or not event.pressed:
        return
    var handled = match_ref.pause_or_cancel_structure(id_value) if kind == "structure" else match_ref.pause_or_cancel_unit(0, id_value)
    if handled:
        button.accept_event()
        _update_build_status()
        _update_button_states()

func _production_tooltip(kind, id_value, data):
    var lines = [
        "%s  ·  $%d" % [str(data.get("name", id_value)), int(data.get("cost", 0))],
        "建造时间：%.1f 秒" % float(data.get("build_time", 0.0))
    ]
    if kind == "structure":
        var output = int(data.get("power_output", 0))
        var use = int(data.get("power_use", 0))
        if output > 0:
            lines.append("发电量：+%d" % output)
        if use > 0:
            lines.append("用电量：-%d" % use)
    lines.append(str(data.get("description", "暂无介绍。")))
    return "\n".join(lines)

func _process(delta):
    if not is_instance_valid(match_ref):
        return
    notification_timer -= delta
    if notification_timer <= 0.0:
        notification_label.visible = false
    credits_label.text = "资金  $%d" % int(match_ref.credits.get(0, 0))
    var power_data = match_ref.power_state.get(0, {"produced": 0, "consumed": 0})
    power_label.text = "电力  %d / %d" % [int(power_data.produced), int(power_data.consumed)]
    power_label.add_theme_color_override("font_color", Color("#73D586") if int(power_data.produced) >= int(power_data.consumed) else Color("#EF6B63"))
    fps_label.visible = bool(SaveManager.settings.get("show_fps", false))
    if fps_label.visible:
        fps_label.text = "FPS %d" % Engine.get_frames_per_second()
    _update_build_status()
    _update_button_states()
    _update_command_button_states()
    info_refresh_timer -= delta
    if info_refresh_timer <= 0.0:
        info_refresh_timer = 0.12
        _refresh_selection_info()

func _update_build_status():
    var lines = []
    var highlighted = false
    for category in ["primary", "defense"]:
        var ready_id = match_ref.get_ready_structure(category)
        var job = match_ref.get_structure_job(category)
        var category_name = "主要" if category == "primary" else "防御"
        if ready_id != "":
            var name_value = str(GameConfig.buildings.get(ready_id, {}).get("name", ready_id))
            lines.append("%s建筑就绪：%s" % [category_name, name_value])
            highlighted = true
        elif not job.is_empty():
            var name_value = str(GameConfig.buildings.get(str(job.get("id", "")), {}).get("name", job.get("id", "")))
            var progress = int(clamp(float(job.get("progress", 0.0)) / max(0.01, float(job.get("duration", 1.0))), 0.0, 1.0) * 100.0)
            lines.append("%s%s：%s %d%%" % [category_name, "暂停" if bool(job.get("paused", false)) else "建造", name_value, progress])
        else:
            lines.append("%s建造空闲" % category_name)
    var unit_summary = match_ref.get_human_production_summary()
    if unit_summary != "":
        lines.append(unit_summary)
    build_status.text = "｜".join(lines)
    build_status.add_theme_color_override("font_color", Color("#72D8F0") if highlighted else Color("#9FB0BA"))

func _update_button_states():
    for id_value in structure_buttons:
        var button = structure_buttons[id_value]
        var state_data = match_ref.get_structure_status(id_value)
        var state = str(state_data.get("state", "idle"))
        var status = ""
        if state == "ready":
            status = "就绪"
        elif state == "paused":
            status = "暂停"
        elif state == "building":
            status = "建造中"
        button.set_runtime_state(status, float(state_data.get("progress", 0.0)), 0)
        var interactive = match_ref.has_structure_interaction(id_value)
        button.disabled = not interactive and not match_ref.can_request_structure(id_value, false)
        button.tooltip_text = _production_tooltip("structure", id_value, GameConfig.buildings[id_value]) + "\n" + match_ref.get_requirement_hint(id_value, true) + "\n左键：建造、继续或部署｜右键：暂停或取消"

    for id_value in unit_buttons:
        var button = unit_buttons[id_value]
        var count = match_ref.get_unit_queue_count(0, id_value)
        var paused = match_ref.is_unit_queue_paused(0, id_value)
        var status = "暂停" if paused else ("生产中" if count > 0 else "")
        button.set_runtime_state(status, match_ref.get_unit_queue_progress(0, id_value), count)
        button.disabled = count == 0 and not match_ref.can_request_unit(0, id_value, false)
        button.tooltip_text = _production_tooltip("unit", id_value, GameConfig.units[id_value]) + "\n" + match_ref.get_requirement_hint(id_value, false) + "\n左键：追加或继续｜右键：暂停、减少数量或取消"

func _update_command_button_states():
    for slot in command_slots:
        if not is_instance_valid(slot) or not slot.configured:
            continue
        slot.disabled = false
        slot.set_active(active_command_mode == slot.command_id)
    for tool_id in sidebar_tool_buttons:
        var tool = sidebar_tool_buttons[tool_id]
        if is_instance_valid(tool):
            tool.set_active(active_command_mode == tool_id)

func _on_command_slot_pressed(slot):
    if is_instance_valid(slot) and slot.configured and not slot.disabled:
        command_requested.emit(slot.command_id)

func _selection_command_signature():
    if current_selection.is_empty():
        return "none"
    var has_combat = false
    var has_harvester = false
    var has_mobile = false
    var has_producer = false
    var has_defense = false
    var has_other = false
    for entity in current_selection:
        if not is_instance_valid(entity):
            continue
        if entity.has_method("is_tree_entity") and entity.is_tree_entity():
            has_other = true
        elif entity.has_method("is_resource_entity") and entity.is_resource_entity():
            has_other = true
        elif entity.has_method("is_movable_unit"):
            has_mobile = true
            if str(entity.unit_id) == "harvester":
                has_harvester = true
            elif entity.is_combat_unit():
                has_combat = true
        elif entity.has_method("is_production_building") and entity.is_production_building():
            has_producer = true
        elif entity.has_method("is_defense_building") and entity.is_defense_building():
            has_defense = true
        else:
            has_other = true
    # Mixed groups expose only commands that make sense for the dominant
    # controllable role. Combat takes priority; harvest is shown only for a
    # pure harvester selection, so a mixed group never receives a fake skill.
    if has_combat:
        return "combat"
    if has_mobile and has_harvester and not has_other and not has_producer:
        return "harvester"
    if has_mobile:
        return "mobile"
    if has_producer and not has_other:
        return "producer"
    if has_defense and not has_other:
        return "defense"
    return "building"

func _skills_for_signature(signature):
    match signature:
        "combat":
            return ["move", "attack_move", "stop", "hold", "patrol", "force_attack", "behavior"]
        "harvester":
            return ["move", "stop", "hold", "patrol", "harvest", "behavior"]
        "mobile":
            return ["move", "stop", "hold", "patrol", "behavior"]
        "producer":
            return ["rally", "primary"]
        "defense":
            return ["building_attack", "building_stop", "force_attack"]
        _:
            return []

func _refresh_command_card(force = false):
    var signature = _selection_command_signature()
    if not force and signature == command_card_signature:
        _update_command_button_states()
        return
    command_card_signature = signature
    command_buttons.clear()
    var skills = _skills_for_signature(signature)
    for index in range(command_slots.size()):
        var slot = command_slots[index]
        if index >= skills.size():
            slot.clear_slot()
            continue
        var command_id = str(skills[index])
        var definition = COMMAND_DEFINITIONS.get(command_id, {})
        slot.configure(
            command_id,
            str(definition.get("name", command_id)),
            str(definition.get("effect", "")),
            str(definition.get("hotkey", "")),
            str(definition.get("icon", command_id))
        )
        command_buttons[command_id] = slot
    _update_command_button_states()

func set_selection(entities):
    current_selection = []
    for entity in entities:
        if is_instance_valid(entity):
            current_selection.append(entity)
    portrait.set_entity(current_selection[0] if not current_selection.is_empty() else null)
    _refresh_selection_info()
    _refresh_command_card(true)

func set_command_mode(mode):
    active_command_mode = mode
    _update_command_button_states()

func _refresh_selection_info():
    current_selection = current_selection.filter(func(entity): return is_instance_valid(entity))
    if current_selection.is_empty():
        selection_label.text = "未选择单位"
        info_label.text = "选择单位或建筑后显示名称、类型、护甲、武器、移动速度、经验、生命和护盾等资料。"
        portrait.set_entity(null)
        return
    if current_selection.size() > 1:
        var counts = {}
        var total_hp = 0.0
        var total_max_hp = 0.0
        for entity in current_selection:
            var id_value = ""
            var data = {}
            if entity.has_method("is_movable_unit"):
                id_value = str(entity.unit_id)
                data = GameConfig.units.get(id_value, {})
            elif entity.has_method("is_tree_entity") and entity.is_tree_entity():
                id_value = "tree"
                data = entity.stats
            elif entity.has_method("is_resource_entity") and entity.is_resource_entity():
                id_value = "ore"
                data = entity.stats
            else:
                id_value = str(entity.building_id)
                data = GameConfig.buildings.get(id_value, {})
            var name_value = str(data.get("name", id_value))
            counts[name_value] = int(counts.get(name_value, 0)) + 1
            total_hp += float(entity.hp)
            total_max_hp += float(entity.max_hp)
        var parts = []
        for name_value in counts:
            parts.append("• %s × %d" % [name_value, counts[name_value]])
        selection_label.text = "已选择 %d 个单位" % current_selection.size()
        info_label.text = "编组构成\n%s\n总生命值：%d / %d\nCtrl+数字设置编队；Shift+数字加入编队。" % ["\n".join(parts), int(total_hp), int(total_max_hp)]
        return
    var entity = current_selection[0]
    portrait.set_entity(entity)
    if entity.has_method("is_tree_entity") and entity.is_tree_entity():
        _show_tree_info(entity)
    elif entity.has_method("is_resource_entity") and entity.is_resource_entity():
        _show_resource_info(entity)
    elif entity.has_method("is_movable_unit"):
        _show_unit_info(entity)
    else:
        _show_building_info(entity)

func _show_unit_info(unit):
    var data = unit.stats
    selection_label.text = str(data.get("name", unit.unit_id))
    var experience_required = unit.get_next_experience_requirement()
    var area = float(data.get("aoe_radius", 0.0))
    var area_text = "无" if area <= 0.0 else "%.0f" % area
    var cargo_line = ""
    if unit.unit_id == "harvester":
        cargo_line = "\n矿仓：%d / %d" % [int(unit.carrying), int(data.get("capacity", 0))]
    info_label.text = "类型：%s　当前指令：%s（队列 %d）\n生命：%d / %d　护盾：%d / %d\n护甲：%d（%s）　移动速度：%.1f\n武器：%s　伤害：%.1f（%s）\n射速间隔：%.2f 秒　攻击距离：%.1f　范围半径：%s\n经验：%d / %d　等级：%s%s\n%s" % [
        str(data.get("unit_type", data.get("category", "单位"))),
        unit.get_current_order_name(),
        unit.get_order_queue_count(),
        int(unit.hp), int(unit.max_hp), int(unit.shield), int(unit.max_shield),
        int(data.get("armor", 0)), str(data.get("armor_type", "无护甲")), float(data.get("speed", 0.0)),
        str(data.get("weapon_name", "无")), float(data.get("damage", 0.0)), str(data.get("damage_type", "无")),
        float(data.get("reload", 0.0)), float(data.get("range", 0.0)), area_text,
        int(unit.experience), int(experience_required), _veterancy_name(unit.veterancy), cargo_line + "\n警戒策略：" + unit.get_behavior_policy_name(),
        str(data.get("description", ""))
    ]

func _show_building_info(building):
    var data = building.stats
    selection_label.text = str(data.get("name", building.building_id))
    var area = float(data.get("aoe_radius", 0.0))
    var area_text = "无" if area <= 0.0 else "%.0f" % area
    var production_line = ""
    if building.is_production_building():
        production_line = "集结点：%.0f, %.0f　主要建筑：%s\n" % [building.rally_point.x, building.rally_point.y, "是" if building.primary_producer else "否"]
    info_label.text = "类型：%s　供电状态：%s\n生命：%d / %d　护盾：%d / %d\n护甲：%d（%s）\n武器：%s　伤害：%.1f（%s）\n射速间隔：%.2f 秒　攻击距离：%.1f　范围半径：%s\n电力：发电 +%d / 用电 -%d\n%s%s" % [
        str(data.get("building_type", "建筑")), "正常" if building.powered else "断电",
        int(building.hp), int(building.max_hp), int(building.shield), int(building.max_shield),
        int(data.get("armor", 0)), str(data.get("armor_type", "建筑护甲")),
        str(data.get("weapon_name", "无")), float(data.get("damage", 0.0)), str(data.get("damage_type", "无")),
        float(data.get("reload", 0.0)), float(data.get("range", 0.0)), area_text,
        int(data.get("power_output", 0)), int(data.get("power_use", 0)),
        production_line, str(data.get("description", ""))
    ]

func _show_tree_info(tree):
    selection_label.text = str(tree.stats.get("name", "树木"))
    info_label.text = "类型：环境目标　状态：%s\n生命：%d / %d\n护甲类型：%s\n地形效果：林中步兵受到的伤害降低25%%\n车辆通行：%s\n%s" % [
        "茂密" if tree.dense else "稀疏", int(tree.hp), int(tree.max_hp), str(tree.stats.get("armor_type", "木质")),
        "阻挡" if tree.dense else "允许", str(tree.stats.get("description", ""))
    ]

func _show_resource_info(resource):
    selection_label.text = "矿石资源"
    var remaining = resource.get_remaining()
    var status = "已枯竭，无法采集" if remaining <= 0 else "可采集"
    info_label.text = "类型：矿石资源　状态：%s\n剩余量：%d / %d\n护甲类型：无敌资源　可被攻击：否\n格子坐标：%d, %d\n%s" % [status, remaining, resource.max_remaining, resource.cell.x, resource.cell.y, str(resource.stats.get("description", ""))]

func _veterancy_name(rank):
    if rank >= 2:
        return "精英"
    if rank == 1:
        return "老兵"
    return "新兵"

func open_behavior_panel(units):
    if is_instance_valid(behavior_panel):
        behavior_panel.open_for_units(units)

func close_behavior_panel():
    if is_instance_valid(behavior_panel):
        behavior_panel.close()

func is_behavior_panel_open():
    return is_instance_valid(behavior_panel) and behavior_panel.is_open()

func _on_objective_changed(title, detail):
    objective_title.text = title
    objective_detail_text = detail
    objective_title.tooltip_text = detail

func show_notification(text, severity = "info"):
    notification_label.text = text
    notification_label.visible = true
    notification_timer = 2.7
    var color = Color("#72D8F0")
    if severity == "warning":
        color = Color("#E5C45D")
    elif severity == "error":
        color = Color("#EE7770")
    notification_label.add_theme_color_override("font_color", color)

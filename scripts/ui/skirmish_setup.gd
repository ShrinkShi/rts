extends Control

signal start_requested(config)
signal back_requested

const UIFactory = preload("res://scripts/ui/ui_factory.gd")
const BackgroundGrid = preload("res://scripts/ui/background_grid.gd")
const MapPreview = preload("res://scripts/ui/map_preview.gd")

var map_option: OptionButton
var mode_option: OptionButton
var credits_option: OptionButton
var fog_check: CheckBox
var nickname_edit: LineEdit
var slots_box: VBoxContainer
var preview
var slot_controls = []
var colors = [
    ["天蓝", "4FA3FF"], ["赤红", "E14B4B"], ["金黄", "E1B84B"], ["翠绿", "55C271"],
    ["紫罗兰", "9D6DE3"], ["橙色", "E78B3A"], ["青色", "4BD7D1"], ["粉色", "D36BA6"]
]

func _ready():
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _build_ui()
    _rebuild_slots()

func _build_ui():
    var bg = BackgroundGrid.new()
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(bg)

    var top = HBoxContainer.new()
    top.position = Vector2(36, 22)
    top.size = Vector2(1208, 50)
    top.add_theme_constant_override("separation", 14)
    add_child(top)
    var back = Button.new()
    back.text = "返回"
    UIFactory.style_button(back)
    back.pressed.connect(func(): back_requested.emit())
    top.add_child(back)
    top.add_child(UIFactory.heading("遭遇战房间", 28))

    var panel = PanelContainer.new()
    panel.position = Vector2(36, 82)
    panel.size = Vector2(1208, 594)
    panel.add_theme_stylebox_override("panel", UIFactory.panel_style(Color(0.05, 0.075, 0.09, 0.97), Color("#3A5562"), 5))
    add_child(panel)
    var cols = HBoxContainer.new()
    cols.add_theme_constant_override("separation", 18)
    panel.add_child(cols)

    var left = VBoxContainer.new()
    left.custom_minimum_size = Vector2(390, 0)
    left.add_theme_constant_override("separation", 8)
    cols.add_child(left)
    left.add_child(UIFactory.heading("房间设置", 19))
    map_option = _make_option(GameConfig.maps)
    map_option.item_selected.connect(func(_index): _rebuild_slots())
    UIFactory.add_labeled_control(left, "地图", map_option)
    mode_option = _make_option(GameConfig.modes)
    UIFactory.add_labeled_control(left, "模式", mode_option)
    credits_option = OptionButton.new()
    for value in [5000, 10000, 20000, 50000]:
        credits_option.add_item(str(value))
        credits_option.set_item_metadata(credits_option.item_count - 1, value)
    credits_option.select(1)
    UIFactory.style_option(credits_option)
    UIFactory.add_labeled_control(left, "初始资金", credits_option)
    fog_check = CheckBox.new()
    fog_check.text = "启用战争迷雾"
    fog_check.button_pressed = true
    left.add_child(fog_check)
    nickname_edit = LineEdit.new()
    nickname_edit.text = "房主"
    nickname_edit.placeholder_text = "你的昵称"
    UIFactory.add_labeled_control(left, "昵称", nickname_edit)
    preview = MapPreview.new()
    left.add_child(preview)

    var right = VBoxContainer.new()
    right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right.add_theme_constant_override("separation", 7)
    cols.add_child(right)
    right.add_child(UIFactory.heading("玩家位置", 19))
    slots_box = VBoxContainer.new()
    slots_box.add_theme_constant_override("separation", 5)
    right.add_child(slots_box)
    right.add_child(UIFactory.muted_label("颜色列直接显示所属色色块；只有电脑玩家拥有难度选项。开放位置不会在本地对局中生成玩家。", 12))
    var start = Button.new()
    start.text = "开始遭遇战"
    UIFactory.style_button(start, true)
    start.pressed.connect(_start)
    right.add_child(start)

func _make_option(data):
    var option = OptionButton.new()
    var keys = data.keys()
    keys.sort()
    for key in keys:
        option.add_item(str(data[key].get("name", key)))
        option.set_item_metadata(option.item_count - 1, key)
    UIFactory.style_option(option)
    return option

func _rebuild_slots():
    if not is_instance_valid(slots_box):
        return
    for child in slots_box.get_children():
        child.queue_free()
    slot_controls.clear()
    var map_id = str(map_option.get_item_metadata(map_option.selected))
    var count = GameConfig.maps[map_id].positions.size()
    for index in range(count):
        var row = HBoxContainer.new()
        row.add_theme_constant_override("separation", 4)
        slots_box.add_child(row)

        var state = OptionButton.new()
        if index == 0:
            state.add_item("房主")
            state.set_item_metadata(0, "human")
            state.disabled = true
        else:
            for item in [["电脑", "ai"], ["开放", "open"], ["关闭", "closed"]]:
                state.add_item(item[0])
                state.set_item_metadata(state.item_count - 1, item[1])
        UIFactory.style_compact_option(state, 82)
        row.add_child(state)

        var faction = _make_option(GameConfig.factions)
        UIFactory.style_compact_option(faction, 102)
        row.add_child(faction)

        var color = OptionButton.new()
        UIFactory.add_color_swatch_items(color, colors)
        color.select(index % colors.size())
        UIFactory.style_compact_option(color, 48)
        color.tooltip_text = "所属色"
        row.add_child(color)

        var position = OptionButton.new()
        for position_index in range(count):
            position.add_item("位置%d" % (position_index + 1))
            position.set_item_metadata(position_index, position_index)
        position.select(index)
        UIFactory.style_compact_option(position, 76)
        row.add_child(position)

        var team = OptionButton.new()
        for team_index in range(1, count + 1):
            team.add_item("队%d" % team_index)
            team.set_item_metadata(team_index - 1, team_index)
        team.select(index)
        UIFactory.style_compact_option(team, 58)
        row.add_child(team)

        var difficulty = OptionButton.new()
        for item in [["简单", "easy"], ["普通", "normal"], ["困难", "hard"]]:
            difficulty.add_item(item[0])
            difficulty.set_item_metadata(difficulty.item_count - 1, item[1])
        difficulty.select(1)
        UIFactory.style_compact_option(difficulty, 70)
        row.add_child(difficulty)

        var controls = {
            "row": row,
            "state": state,
            "faction": faction,
            "color": color,
            "position": position,
            "team": team,
            "difficulty": difficulty
        }
        slot_controls.append(controls)
        state.item_selected.connect(_on_slot_state_changed.bind(index))
        _update_slot_row_state(index)
    preview.configure(map_id, 0, max(0, count - 1), Color("#4FA3FF"), Color("#E14B4B"))

func _on_slot_state_changed(_selected_index, slot_index):
    _update_slot_row_state(slot_index)

func _update_slot_row_state(slot_index):
    if slot_index < 0 or slot_index >= slot_controls.size():
        return
    var controls = slot_controls[slot_index]
    var state = str(_meta(controls.state))
    controls.difficulty.visible = state == "ai"
    controls.difficulty.disabled = state != "ai"

func _meta(option):
    return option.get_item_metadata(option.selected)

func _start():
    var players = []
    for index in range(slot_controls.size()):
        var controls = slot_controls[index]
        var state = str(_meta(controls.state))
        if state not in ["human", "ai"]:
            continue
        var player = {
            "controller": state,
            "nickname": nickname_edit.text if state == "human" else "电脑%d" % index,
            "faction": str(_meta(controls.faction)),
            "color": str(_meta(controls.color)),
            "position": int(_meta(controls.position)),
            "team": int(_meta(controls.team))
        }
        if state == "ai":
            player["difficulty"] = str(_meta(controls.difficulty))
        players.append(player)
    start_requested.emit({
        "kind": "skirmish",
        "map_id": str(_meta(map_option)),
        "mode_id": str(_meta(mode_option)),
        "starting_credits": int(_meta(credits_option)),
        "fog_of_war": fog_check.button_pressed,
        "players": players
    })

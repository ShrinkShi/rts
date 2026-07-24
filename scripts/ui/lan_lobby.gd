extends Control

signal back_requested
signal start_requested(config)

const UIFactory = preload("res://scripts/ui/ui_factory.gd")
const BackgroundGrid = preload("res://scripts/ui/background_grid.gd")

var room_list: ItemList
var status_label: Label
var lobby_box: VBoxContainer
var nickname_edit: LineEdit
var password_edit: LineEdit
var room_name_edit: LineEdit
var map_option: OptionButton
var host_button: Button
var join_button: Button
var start_button: Button
var selected_address = ""
var color_definitions = [
    ["蓝", "4FA3FF"], ["红", "E14B4B"], ["黄", "E1B84B"], ["绿", "55C271"],
    ["紫", "9D6DE3"], ["橙", "E78B3A"], ["青", "4BD7D1"], ["粉", "D36BA6"]
]

func _ready():
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _build_ui()
    NetworkManager.discovery_updated.connect(_on_discovery)
    NetworkManager.lobby_updated.connect(_render_lobby)
    NetworkManager.connection_status.connect(func(text): status_label.text = text)
    NetworkManager.match_received.connect(func(config): start_requested.emit(config))
    NetworkManager.rejected.connect(func(reason): status_label.text = reason)
    NetworkManager.start_discovery()

func _exit_tree():
    if not NetworkManager.is_host and NetworkManager.lobby_state.is_empty():
        NetworkManager.shutdown()

func _build_ui():
    var bg = BackgroundGrid.new()
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(bg)

    var margin = MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_left", 22)
    margin.add_theme_constant_override("margin_right", 22)
    margin.add_theme_constant_override("margin_top", 16)
    margin.add_theme_constant_override("margin_bottom", 18)
    add_child(margin)

    var page = VBoxContainer.new()
    page.add_theme_constant_override("separation", 10)
    margin.add_child(page)

    var top = HBoxContainer.new()
    top.custom_minimum_size.y = 42
    top.add_theme_constant_override("separation", 12)
    page.add_child(top)
    var back = Button.new()
    back.text = "返回"
    UIFactory.style_compact_button(back, false, 138)
    back.pressed.connect(func(): NetworkManager.shutdown(); back_requested.emit())
    top.add_child(back)
    var title = UIFactory.heading("局域网大厅", 24)
    title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    top.add_child(title)

    var panel = PanelContainer.new()
    panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    panel.add_theme_stylebox_override("panel", UIFactory.panel_style(Color(0.05, 0.075, 0.09, 0.97), Color("#3A5562"), 5))
    page.add_child(panel)
    var columns = HBoxContainer.new()
    columns.add_theme_constant_override("separation", 14)
    panel.add_child(columns)

    var left = VBoxContainer.new()
    left.custom_minimum_size = Vector2(330, 0)
    left.add_theme_constant_override("separation", 5)
    columns.add_child(left)
    left.add_child(UIFactory.heading("搜索房间", 16))
    nickname_edit = _compact_line_edit("你的昵称", "游客")
    left.add_child(nickname_edit)
    password_edit = _compact_line_edit("房间密码（没有则留空）", "")
    password_edit.secret = true
    left.add_child(password_edit)
    room_list = ItemList.new()
    room_list.custom_minimum_size = Vector2(314, 145)
    room_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    room_list.add_theme_font_size_override("font_size", 12)
    room_list.item_selected.connect(_on_room_selected)
    left.add_child(room_list)
    var refresh = Button.new()
    refresh.text = "刷新局域网房间"
    UIFactory.style_compact_button(refresh, false, 180)
    refresh.pressed.connect(func(): NetworkManager.start_discovery())
    left.add_child(refresh)
    join_button = Button.new()
    join_button.text = "加入选中房间"
    UIFactory.style_compact_button(join_button, true, 180)
    join_button.disabled = true
    join_button.pressed.connect(_join_selected)
    left.add_child(join_button)
    left.add_child(HSeparator.new())
    left.add_child(UIFactory.heading("创建房间", 16))
    room_name_edit = _compact_line_edit("房间名称", "我的战场")
    left.add_child(room_name_edit)
    map_option = OptionButton.new()
    var map_keys = GameConfig.maps.keys()
    map_keys.sort()
    for key in map_keys:
        map_option.add_item(str(GameConfig.maps[key].get("name", key)))
        map_option.set_item_metadata(map_option.item_count - 1, key)
    UIFactory.style_compact_option(map_option, 180)
    left.add_child(map_option)
    host_button = Button.new()
    host_button.text = "创建并成为房主"
    UIFactory.style_compact_button(host_button, true, 180)
    host_button.pressed.connect(_host_room)
    left.add_child(host_button)

    var right = VBoxContainer.new()
    right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right.add_theme_constant_override("separation", 5)
    columns.add_child(right)
    right.add_child(UIFactory.heading("房间玩家", 16))
    var lobby_scroll = ScrollContainer.new()
    lobby_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    lobby_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    lobby_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    right.add_child(lobby_scroll)
    lobby_box = VBoxContainer.new()
    lobby_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    lobby_box.add_theme_constant_override("separation", 4)
    lobby_scroll.add_child(lobby_box)
    status_label = UIFactory.muted_label("正在搜索局域网房间……", 12)
    status_label.custom_minimum_size.y = 26
    right.add_child(status_label)
    start_button = Button.new()
    start_button.text = "房主开始游戏"
    UIFactory.style_compact_button(start_button, true, 190)
    start_button.visible = false
    start_button.pressed.connect(_host_start)
    right.add_child(start_button)

func _compact_line_edit(placeholder, value):
    var edit = LineEdit.new()
    edit.placeholder_text = placeholder
    edit.text = value
    edit.custom_minimum_size.y = 30
    edit.add_theme_font_size_override("font_size", 13)
    return edit

func _profile():
    return {
        "nickname": nickname_edit.text.strip_edges() if nickname_edit.text.strip_edges() != "" else "玩家",
        "faction": "union",
        "color": "4FA3FF",
        "position": 0,
        "team": 1
    }

func _host_room():
    var map_id = str(map_option.get_item_metadata(map_option.selected))
    NetworkManager.host_room(room_name_edit.text, password_edit.text, map_id, _profile())

func _join_selected():
    if selected_address == "":
        return
    NetworkManager.join_room(selected_address, password_edit.text, _profile())

func _on_discovery(rooms):
    room_list.clear()
    selected_address = ""
    join_button.disabled = true
    for room in rooms:
        var suffix = " [密码]" if bool(room.get("password", false)) else ""
        room_list.add_item("%s  %d/%d  %s%s" % [room.get("name", "房间"), room.get("players", 0), room.get("capacity", 0), room.get("address", ""), suffix])
        room_list.set_item_metadata(room_list.item_count - 1, room.get("address", ""))

func _on_room_selected(index):
    selected_address = str(room_list.get_item_metadata(index))
    join_button.disabled = selected_address == ""

func _render_lobby(state):
    for child in lobby_box.get_children():
        child.queue_free()
    if state.is_empty():
        return
    var is_room_host = NetworkManager.is_host
    var own_peer = multiplayer.get_unique_id()
    start_button.visible = is_room_host
    for index in range(state.get("slots", []).size()):
        var slot = state.slots[index]
        var row = HBoxContainer.new()
        row.custom_minimum_size.y = 32
        row.add_theme_constant_override("separation", 4)
        lobby_box.add_child(row)
        var label = Label.new()
        label.custom_minimum_size = Vector2(100, 30)
        label.text = "%d. %s" % [index + 1, slot.get("nickname", slot.get("state", ""))]
        label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
        label.add_theme_font_size_override("font_size", 12)
        row.add_child(label)

        var editable_guest = str(slot.get("state", "")) == "human" and int(slot.get("peer_id", 0)) == own_peer
        var editable_ai = is_room_host and str(slot.get("state", "")) == "ai"
        if is_room_host and index > 0 and int(slot.get("peer_id", 0)) == 0:
            var state_option = OptionButton.new()
            for item in [["开放", "open"], ["关闭", "closed"], ["电脑", "ai"]]:
                state_option.add_item(item[0])
                state_option.set_item_metadata(state_option.item_count - 1, item[1])
            _select_metadata(state_option, str(slot.get("state", "open")))
            UIFactory.style_compact_option(state_option, 66)
            state_option.item_selected.connect(func(item_index, slot_index = index, option = state_option): NetworkManager.host_set_slot(slot_index, {"state": str(option.get_item_metadata(item_index))}))
            row.add_child(state_option)

        if editable_guest or editable_ai:
            var faction = OptionButton.new()
            for key in GameConfig.factions.keys():
                faction.add_item(str(GameConfig.factions[key].get("name", key)))
                faction.set_item_metadata(faction.item_count - 1, key)
            _select_metadata(faction, str(slot.get("faction", "union")))
            UIFactory.style_compact_option(faction, 82)
            row.add_child(faction)
            faction.item_selected.connect(func(item_index, slot_index = index, option = faction, ai = editable_ai): _patch_slot(slot_index, {"faction": str(option.get_item_metadata(item_index))}, ai))

            var color = OptionButton.new()
            UIFactory.add_color_swatch_items(color, color_definitions)
            _select_metadata(color, str(slot.get("color", "4FA3FF")))
            UIFactory.style_compact_option(color, 46)
            color.tooltip_text = "所属色"
            row.add_child(color)
            color.item_selected.connect(func(item_index, slot_index = index, option = color, ai = editable_ai): _patch_slot(slot_index, {"color": str(option.get_item_metadata(item_index))}, ai))

            var position = OptionButton.new()
            for position_index in range(state.get("slots", []).size()):
                position.add_item(str(position_index + 1))
                position.set_item_metadata(position_index, position_index)
            _select_metadata(position, int(slot.get("position", index)))
            UIFactory.style_compact_option(position, 46)
            row.add_child(position)
            position.item_selected.connect(func(item_index, slot_index = index, option = position, ai = editable_ai): _patch_slot(slot_index, {"position": int(option.get_item_metadata(item_index))}, ai))

            if editable_ai:
                var difficulty = OptionButton.new()
                for item in [["简", "easy"], ["普", "normal"], ["难", "hard"]]:
                    difficulty.add_item(item[0])
                    difficulty.set_item_metadata(difficulty.item_count - 1, item[1])
                _select_metadata(difficulty, str(slot.get("difficulty", "normal")))
                UIFactory.style_compact_option(difficulty, 48)
                row.add_child(difficulty)
                difficulty.item_selected.connect(func(item_index, slot_index = index, option = difficulty): NetworkManager.host_set_slot(slot_index, {"difficulty": str(option.get_item_metadata(item_index))}))
        else:
            var swatch = TextureRect.new()
            swatch.texture = UIFactory.color_swatch_texture(str(slot.get("color", "4FA3FF")), Vector2i(24, 16))
            swatch.custom_minimum_size = Vector2(26, 20)
            swatch.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
            row.add_child(swatch)
            var difficulty_text = "  难度:%s" % str(slot.get("difficulty", "normal")) if str(slot.get("state", "")) == "ai" else ""
            var details = UIFactory.muted_label("国家:%s  位置:%s  队伍:%s%s" % [slot.get("faction", "union"), int(slot.get("position", index)) + 1, slot.get("team", index + 1), difficulty_text], 11)
            details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            details.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
            row.add_child(details)
    status_label.text = "房间：" + str(state.get("room_name", "局域网房间")) + ("（有密码）" if bool(state.get("password_required", false)) else "")

func _select_metadata(option, value):
    for index in range(option.item_count):
        if option.get_item_metadata(index) == value:
            option.select(index)
            return

func _patch_slot(index, patch, ai):
    if ai:
        NetworkManager.host_set_slot(index, patch)
    else:
        NetworkManager.update_own_slot(patch)

func _host_start():
    var state = NetworkManager.lobby_state
    var config = {
        "kind": "skirmish",
        "map_id": str(state.get("map_id", "twin_rivers")),
        "mode_id": "standard",
        "starting_credits": 10000,
        "fog_of_war": true
    }
    NetworkManager.host_start_match(config)

extends Control

signal back_requested

const RA2Database = preload("res://scripts/ra2/ra2_database.gd")
const UIFactory = preload("res://scripts/ui/ui_factory.gd")
const BackgroundGrid = preload("res://scripts/ui/background_grid.gd")

const MODE_ENTITIES: int = 0
const MODE_SOUNDS: int = 1
const MODE_LOCALIZATION: int = 2
const MODE_MAPS: int = 3

const DIRECTION_LABELS_8 = [
	"东", "东南", "南", "西南", "西", "西北", "北", "东北",
]
const TEAM_COLORS: Array = [
	["蓝色", "#2F70D0"],
	["红色", "#D33B32"],
	["绿色", "#38A65A"],
	["黄色", "#D5B72D"],
	["橙色", "#D97B2B"],
	["紫色", "#8A55C6"],
	["青色", "#32A8B3"],
	["粉色", "#D66A9B"],
]

var _entity_catalog: Array = []
var _sound_catalog: Array = []
var _localization_catalog: Array = []
var _map_catalog: Array = []
var _visible_entries: Array = []
var _preview_catalog_ids: Dictionary = {}

var _mode: OptionButton
var _search: LineEdit
var _category: OptionButton
var _preview_only: CheckBox
var _item_list: ItemList
var _summary_label: Label

var _preview_base: TextureRect
var _preview_remap: TextureRect
var _preview_message: Label
var _animation_option: OptionButton
var _direction_option: OptionButton
var _theater_option: OptionButton
var _team_color_option: OptionButton
var _play_pause_button: Button
var _previous_frame_button: Button
var _next_frame_button: Button
var _loop_check: CheckBox
var _speed_slider: HSlider
var _frame_status: Label
var _preview_timer: Timer

var _detail_box: VBoxContainer

var _audio_event_option: OptionButton
var _audio_sample_option: OptionButton
var _audio_play_button: Button
var _audio_random_button: Button
var _audio_stop_button: Button
var _audio_volume: HSlider
var _audio_status: Label
var _audio_events: Array[Dictionary] = []
var _audio_samples: Array[Dictionary] = []

var _current_entity: Dictionary = {}
var _preview_manifest: Dictionary = {}
var _preview_manifest_dir: String = ""
var _current_frames: PackedStringArray = PackedStringArray()
var _current_masks: PackedStringArray = PackedStringArray()
var _current_source_indices: Array = []
var _frame_index: int = 0
var _preview_playing: bool = true
var _animation_rate_ms: int = 120
var _texture_cache: Dictionary = {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = _create_ui_theme()
	_entity_catalog = RA2Database.load_catalog()
	_enrich_entity_names()
	_sound_catalog = RA2Database.load_sound_events()
	_localization_catalog = RA2Database.load_localization_catalog()
	_map_catalog = RA2Database.load_maps()
	_load_preview_catalog()
	_build_ui()
	_connect_audio_service()
	_refresh_list()

func _enrich_entity_names() -> void:
	for entry_variant: Variant in _entity_catalog:
		if not entry_variant is Dictionary:
			continue
		var entry: Dictionary = entry_variant as Dictionary
		var entity_id: String = str(entry.get("id", ""))
		var resolved_name: String = RA2RuntimeDatabase.display_name(entity_id)
		if not resolved_name.is_empty():
			entry["display_name"] = resolved_name
			entry["search_text"] = "%s %s" % [str(entry.get("search_text", "")), resolved_name]

func _create_ui_theme() -> Theme:
	var ui_theme: Theme = Theme.new()
	var system_font: SystemFont = SystemFont.new()
	system_font.font_names = PackedStringArray([
		"Microsoft YaHei UI",
		"Microsoft YaHei",
		"Noto Sans CJK SC",
		"Source Han Sans SC",
		"PingFang SC",
		"WenQuanYi Micro Hei",
		"Arial Unicode MS",
	])
	system_font.allow_system_fallback = true
	ui_theme.default_font = system_font
	ui_theme.default_font_size = 16
	return ui_theme

func _connect_audio_service() -> void:
	if RA2AudioService.sample_started.is_connected(_on_audio_sample_started):
		return
	RA2AudioService.sample_started.connect(_on_audio_sample_started)
	RA2AudioService.playback_failed.connect(_on_audio_playback_failed)
	RA2AudioService.playback_stopped.connect(_on_audio_stopped)

func _build_ui() -> void:
	var background: Node = BackgroundGrid.new()
	if background is Control:
		(background as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		(background as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var page_margin: MarginContainer = MarginContainer.new()
	page_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_margin.add_theme_constant_override("margin_left", 18)
	page_margin.add_theme_constant_override("margin_right", 18)
	page_margin.add_theme_constant_override("margin_top", 16)
	page_margin.add_theme_constant_override("margin_bottom", 16)
	add_child(page_margin)

	var page: VBoxContainer = VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	page_margin.add_child(page)

	page.add_child(_build_header())

	var body: HSplitContainer = HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.split_offset = 292
	page.add_child(body)

	body.add_child(_build_left_panel())

	var content_split: HSplitContainer = HSplitContainer.new()
	content_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_split.split_offset = 520
	body.add_child(content_split)
	content_split.add_child(_build_preview_column())
	content_split.add_child(_build_detail_panel())

	_preview_timer = Timer.new()
	_preview_timer.wait_time = 0.12
	_preview_timer.timeout.connect(_advance_preview)
	add_child(_preview_timer)

func _build_header() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 62)
	panel.add_theme_stylebox_override("panel", UIFactory.panel_style(Color(0.045, 0.065, 0.082, 0.97), Color("#395968"), 5))
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)

	var back: Button = Button.new()
	back.text = "返回"
	UIFactory.style_compact_button(back, false, 86)
	back.pressed.connect(_emit_back)
	row.add_child(back)

	var title: Label = Label.new()
	title.text = "RA2 / 尤里的复仇资源浏览器"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("#EDF5F7"))
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)

	_summary_label = Label.new()
	_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_summary_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_summary_label.add_theme_color_override("font_color", Color("#8DB4C5"))
	_summary_label.add_theme_font_size_override("font_size", 14)
	var summary: Dictionary = RA2Database.load_summary()
	_summary_label.text = "%d 对象 · %d 预览 · %d 文本 · %d 音频事件" % [
		int(summary.get("entity_count", 0)),
		_preview_catalog_ids.size(),
		int(summary.get("localization_count", 0)),
		_sound_catalog.size(),
	]
	row.add_child(_summary_label)
	return panel

func _build_left_panel() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(278, 0)
	panel.add_theme_stylebox_override("panel", UIFactory.panel_style(Color(0.04, 0.058, 0.073, 0.97), Color("#304B58"), 4))
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	_mode = OptionButton.new()
	_mode.add_item("单位与建筑")
	_mode.add_item("声音事件")
	_mode.add_item("CSF 本地化")
	_mode.add_item("官方地图")
	_mode.item_selected.connect(_on_mode_changed)
	UIFactory.style_compact_option(_mode, 230)
	box.add_child(_mode)

	_search = LineEdit.new()
	_search.placeholder_text = "搜索 ID、名称、素材或字段"
	_search.clear_button_enabled = true
	_search.text_changed.connect(_on_search_changed)
	box.add_child(_search)

	_category = OptionButton.new()
	_category.add_item("全部类型")
	_category.add_item("步兵")
	_category.add_item("载具")
	_category.add_item("飞行器")
	_category.add_item("建筑")
	_category.item_selected.connect(_on_category_changed)
	UIFactory.style_compact_option(_category, 230)
	box.add_child(_category)

	_preview_only = CheckBox.new()
	_preview_only.text = "只显示已有动画预览的对象"
	_preview_only.button_pressed = true
	_preview_only.toggled.connect(_on_preview_only_toggled)
	box.add_child(_preview_only)

	_item_list = ItemList.new()
	_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_list.select_mode = ItemList.SELECT_SINGLE
	_item_list.allow_reselect = true
	_item_list.item_selected.connect(_on_item_selected)
	box.add_child(_item_list)
	return panel

func _build_preview_column() -> Control:
	# The preview, transport controls and audio player together are taller than a
	# 720p content area.  Put this complete column in its own vertical scroller so
	# the audio controls remain reachable instead of overflowing below the window.
	var outer_scroll: ScrollContainer = ScrollContainer.new()
	outer_scroll.custom_minimum_size = Vector2(430, 0)
	outer_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	outer_scroll.add_child(column)

	var preview_panel: PanelContainer = PanelContainer.new()
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_panel.custom_minimum_size = Vector2(0, 320)
	preview_panel.add_theme_stylebox_override("panel", UIFactory.panel_style(Color(0.027, 0.038, 0.047, 0.98), Color("#304B58"), 4))
	column.add_child(preview_panel)

	var preview_stack: VBoxContainer = VBoxContainer.new()
	preview_stack.add_theme_constant_override("separation", 8)
	preview_panel.add_child(preview_stack)

	var preview_heading: Label = Label.new()
	preview_heading.text = "动画预览"
	preview_heading.add_theme_font_size_override("font_size", 19)
	preview_heading.add_theme_color_override("font_color", Color("#E8F1F4"))
	preview_stack.add_child(preview_heading)

	var canvas: Control = Control.new()
	canvas.clip_contents = true
	canvas.custom_minimum_size = Vector2(360, 240)
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_stack.add_child(canvas)

	var canvas_bg: ColorRect = ColorRect.new()
	canvas_bg.color = Color("#080D11")
	canvas_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(canvas_bg)

	_preview_base = TextureRect.new()
	_preview_base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_base.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_base.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_base.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_preview_base)

	_preview_remap = TextureRect.new()
	_preview_remap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_remap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_remap.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_remap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview_remap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_preview_remap)

	_preview_message = Label.new()
	_preview_message.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_preview_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_message.add_theme_color_override("font_color", Color("#8EA5AF"))
	_preview_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_preview_message)

	var controls_panel: PanelContainer = PanelContainer.new()
	controls_panel.add_theme_stylebox_override("panel", UIFactory.panel_style(Color(0.04, 0.058, 0.073, 0.97), Color("#304B58"), 4))
	column.add_child(controls_panel)
	var controls: VBoxContainer = VBoxContainer.new()
	controls.add_theme_constant_override("separation", 7)
	controls_panel.add_child(controls)

	var selector_grid: GridContainer = GridContainer.new()
	selector_grid.columns = 2
	selector_grid.add_theme_constant_override("h_separation", 8)
	selector_grid.add_theme_constant_override("v_separation", 6)
	controls.add_child(selector_grid)

	_animation_option = _add_selector_row(selector_grid, "动画", _on_animation_changed)
	_direction_option = _add_selector_row(selector_grid, "方向", _on_direction_changed)
	_theater_option = _add_selector_row(selector_grid, "剧院", _on_theater_changed)
	_team_color_option = _add_selector_row(selector_grid, "所属色", _on_team_color_changed)
	for color_data in TEAM_COLORS:
		_team_color_option.add_item(str(color_data[0]))
		_team_color_option.set_item_metadata(_team_color_option.item_count - 1, str(color_data[1]))
	_team_color_option.select(0)

	var playback_row: HBoxContainer = HBoxContainer.new()
	playback_row.add_theme_constant_override("separation", 6)
	controls.add_child(playback_row)

	_previous_frame_button = Button.new()
	_previous_frame_button.text = "上一帧"
	UIFactory.style_compact_button(_previous_frame_button, false, 78)
	_previous_frame_button.pressed.connect(_step_previous_frame)
	playback_row.add_child(_previous_frame_button)

	_play_pause_button = Button.new()
	_play_pause_button.text = "暂停"
	UIFactory.style_compact_button(_play_pause_button, true, 78)
	_play_pause_button.pressed.connect(_toggle_preview_playback)
	playback_row.add_child(_play_pause_button)

	_next_frame_button = Button.new()
	_next_frame_button.text = "下一帧"
	UIFactory.style_compact_button(_next_frame_button, false, 78)
	_next_frame_button.pressed.connect(_step_next_frame)
	playback_row.add_child(_next_frame_button)

	_loop_check = CheckBox.new()
	_loop_check.text = "循环"
	_loop_check.button_pressed = true
	playback_row.add_child(_loop_check)

	_frame_status = Label.new()
	_frame_status.text = "0 / 0"
	_frame_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_frame_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_frame_status.add_theme_color_override("font_color", Color("#9FB8C3"))
	playback_row.add_child(_frame_status)

	var speed_row: HBoxContainer = HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 8)
	controls.add_child(speed_row)
	var speed_label: Label = Label.new()
	speed_label.text = "播放速度"
	speed_label.custom_minimum_size = Vector2(80, 0)
	speed_row.add_child(speed_label)
	_speed_slider = HSlider.new()
	_speed_slider.min_value = 0.25
	_speed_slider.max_value = 3.0
	_speed_slider.step = 0.05
	_speed_slider.value = 1.0
	_speed_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speed_slider.value_changed.connect(_on_speed_changed)
	speed_row.add_child(_speed_slider)

	column.add_child(_build_audio_panel())
	return outer_scroll

func _add_selector_row(grid: GridContainer, caption: String, callback: Callable) -> OptionButton:
	var label: Label = Label.new()
	label.text = caption
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(64, 32)
	label.add_theme_color_override("font_color", Color("#B9C9D0"))
	grid.add_child(label)
	var option: OptionButton = OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIFactory.style_compact_option(option, 180)
	option.item_selected.connect(callback)
	grid.add_child(option)
	return option

func _build_audio_panel() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIFactory.panel_style(Color(0.04, 0.058, 0.073, 0.97), Color("#304B58"), 4))
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var heading: Label = Label.new()
	heading.text = "声音试听"
	heading.add_theme_font_size_override("font_size", 18)
	box.add_child(heading)

	var selector_grid: GridContainer = GridContainer.new()
	selector_grid.columns = 2
	selector_grid.add_theme_constant_override("h_separation", 8)
	selector_grid.add_theme_constant_override("v_separation", 6)
	box.add_child(selector_grid)
	_audio_event_option = _add_selector_row(selector_grid, "事件", _on_audio_event_changed)
	_audio_sample_option = _add_selector_row(selector_grid, "样本", _on_audio_sample_changed)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	box.add_child(buttons)
	_audio_play_button = Button.new()
	_audio_play_button.text = "播放样本"
	UIFactory.style_compact_button(_audio_play_button, true, 92)
	_audio_play_button.pressed.connect(_play_current_audio_sample)
	buttons.add_child(_audio_play_button)
	_audio_random_button = Button.new()
	_audio_random_button.text = "随机事件"
	UIFactory.style_compact_button(_audio_random_button, false, 92)
	_audio_random_button.pressed.connect(_play_random_audio_event)
	buttons.add_child(_audio_random_button)
	_audio_stop_button = Button.new()
	_audio_stop_button.text = "停止"
	UIFactory.style_compact_button(_audio_stop_button, false, 66)
	_audio_stop_button.pressed.connect(_stop_audio)
	buttons.add_child(_audio_stop_button)

	var volume_row: HBoxContainer = HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 8)
	box.add_child(volume_row)
	var volume_label: Label = Label.new()
	volume_label.text = "音量"
	volume_label.custom_minimum_size = Vector2(64, 0)
	volume_row.add_child(volume_label)
	_audio_volume = HSlider.new()
	_audio_volume.min_value = 0.0
	_audio_volume.max_value = 1.0
	_audio_volume.step = 0.02
	_audio_volume.value = RA2AudioService.get_master_volume_linear()
	_audio_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_audio_volume.value_changed.connect(_on_audio_volume_changed)
	volume_row.add_child(_audio_volume)

	_audio_status = Label.new()
	_audio_status.text = "选择对象后可试听其选择、移动、攻击和死亡语音。"
	_audio_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_audio_status.add_theme_color_override("font_color", Color("#8DB4C5"))
	_audio_status.add_theme_constant_override("line_spacing", 3)
	box.add_child(_audio_status)
	return panel

func _build_detail_panel() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	panel.add_theme_stylebox_override("panel", UIFactory.panel_style(Color(0.04, 0.058, 0.073, 0.97), Color("#304B58"), 4))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)
	_detail_box = VBoxContainer.new()
	_detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_detail_box)
	return panel

func _load_preview_catalog() -> void:
	var parsed: Variant = RA2Database.load_json("res://assets/ra2_preview/catalog.json", false)
	if not parsed is Array:
		return
	var catalog_entries: Array = parsed as Array
	for item_variant in catalog_entries:
		if item_variant is Dictionary:
			var item: Dictionary = item_variant as Dictionary
			_preview_catalog_ids[str(item.get("entity_id", "")).to_lower()] = true

func _as_array(value: Variant) -> Array:
	if value is Array:
		return value as Array
	return []

func _string_array(value: Variant) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for item_variant in _as_array(value):
		result.append(str(item_variant))
	return result

func _emit_back() -> void:
	back_requested.emit()

func _on_search_changed(_value: String) -> void:
	_refresh_list()

func _on_category_changed(_index: int) -> void:
	_refresh_list()

func _on_preview_only_toggled(_enabled: bool) -> void:
	_refresh_list()

func _on_mode_changed(_index: int) -> void:
	_category.visible = _mode.selected == MODE_ENTITIES
	_preview_only.visible = _mode.selected == MODE_ENTITIES
	_search.text = ""
	_stop_audio()
	_refresh_list()

func _category_key() -> String:
	match _category.selected:
		1:
			return "infantry"
		2:
			return "vehicle"
		3:
			return "aircraft"
		4:
			return "building"
		_:
			return ""

func _source_for_mode() -> Array:
	match _mode.selected:
		MODE_SOUNDS:
			return _sound_catalog
		MODE_LOCALIZATION:
			return _localization_catalog
		MODE_MAPS:
			return _map_catalog
		_:
			return _entity_catalog

func _entry_haystack(entry: Dictionary) -> String:
	match _mode.selected:
		MODE_SOUNDS:
			return "%s %s %s" % [entry.get("id", ""), entry.get("sample_tokens", []), entry.get("raw_values", {})]
		MODE_LOCALIZATION:
			return "%s %s" % [entry.get("label", ""), entry.get("text", "")]
		MODE_MAPS:
			return "%s %s %s %s" % [entry.get("id", ""), entry.get("display_name", ""), entry.get("author", ""), entry.get("theater", "")]
		_:
			return str(entry.get("search_text", "%s %s %s" % [entry.get("id", ""), entry.get("display_name", ""), entry.get("art_id", "")]))

func _entry_label(entry: Dictionary) -> String:
	match _mode.selected:
		MODE_SOUNDS:
			return "%s  [%d/%d]" % [
				str(entry.get("id", "")),
				int(entry.get("resolved_sample_count", 0)),
				_as_array(entry.get("sample_tokens", [])).size(),
			]
		MODE_LOCALIZATION:
			var localized_text: String = str(entry.get("text", "")).replace("\n", " ")
			if localized_text.length() > 20:
				localized_text = localized_text.left(20) + "…"
			return "%s  %s" % [str(entry.get("label", "")), localized_text]
		MODE_MAPS:
			return "%s  %s" % [str(entry.get("id", "")), str(entry.get("display_name", entry.get("name", "")))]
		_:
			var mark: String = "●" if _preview_catalog_ids.has(str(entry.get("id", "")).to_lower()) else "○"
			return "%s %-11s  %s" % [mark, str(entry.get("id", "")), str(entry.get("display_name", entry.get("name_token", "")))]

func _refresh_list() -> void:
	_item_list.clear()
	_visible_entries.clear()
	_reset_preview("请选择条目。")
	_clear_audio_options()
	_clear_details()

	var query: String = _search.text.strip_edges().to_lower()
	var category_key: String = _category_key()
	for item_variant in _source_for_mode():
		if not item_variant is Dictionary:
			continue
		var entry: Dictionary = item_variant as Dictionary
		if _mode.selected == MODE_ENTITIES:
			if not category_key.is_empty() and str(entry.get("category", "")) != category_key:
				continue
			if _preview_only.button_pressed and not _preview_catalog_ids.has(str(entry.get("id", "")).to_lower()):
				continue
		if not query.is_empty() and not _entry_haystack(entry).to_lower().contains(query):
			continue
		_visible_entries.append(entry)
		_item_list.add_item(_entry_label(entry))
		_item_list.set_item_metadata(_item_list.item_count - 1, _visible_entries.size() - 1)

	if _visible_entries.is_empty():
		_add_empty_detail("没有匹配条目。")
		return
	_item_list.select(0)
	_show_entry(_visible_entries[0] as Dictionary)

func _on_item_selected(index: int) -> void:
	var visible_index: int = int(_item_list.get_item_metadata(index))
	if visible_index < 0 or visible_index >= _visible_entries.size():
		return
	_show_entry(_visible_entries[visible_index] as Dictionary)

func _show_entry(entry: Dictionary) -> void:
	match _mode.selected:
		MODE_SOUNDS:
			_show_sound(entry)
		MODE_LOCALIZATION:
			_show_localization(entry)
		MODE_MAPS:
			_show_map(entry)
		_:
			_show_entity(entry)

func _show_entity(catalog_entry: Dictionary) -> void:
	_current_entity = RA2Database.load_entity(catalog_entry)
	if not _current_entity.is_empty():
		_current_entity["display_name"] = RA2RuntimeDatabase.display_name(str(_current_entity.get("id", "")))
	if _current_entity.is_empty():
		_reset_preview("对象详情无法加载。")
		_clear_details()
		_add_empty_detail("无法加载对象详情。")
		return
	_load_entity_preview(str(_current_entity.get("id", "")))
	_populate_entity_audio(_current_entity)
	_build_entity_details(_current_entity)

func _show_sound(entry: Dictionary) -> void:
	_current_entity.clear()
	_reset_preview("声音事件没有图像预览。")
	_populate_audio_events([entry])
	_clear_details()
	_add_detail_title(str(entry.get("id", "")), "声音事件")
	var values: Dictionary = entry.get("raw_values", {}) as Dictionary
	_add_detail_section("事件属性")
	for key_variant in values.keys():
		_add_detail_property(str(key_variant), str(values[key_variant]))
	_add_detail_section("样本")
	var samples: Array = entry.get("samples", []) as Array
	_add_detail_property("可播放", str(samples.size()))
	_add_detail_property("缺失", str(_as_array(entry.get("missing_samples", [])).size()))
	for sample_variant in samples:
		if sample_variant is Dictionary:
			var sample: Dictionary = sample_variant as Dictionary
			_add_detail_paragraph("%s · %s Hz · %s · %s" % [
				str(sample.get("name", "")),
				str(sample.get("sample_rate", "")),
				str(sample.get("source_bank", "unknown")),
				str(sample.get("resource_path", "")),
			], Color("#B8CBD3"))

func _show_localization(entry: Dictionary) -> void:
	_current_entity.clear()
	_reset_preview("CSF 文本没有图像预览。")
	_clear_audio_options()
	_clear_details()
	_add_detail_title(str(entry.get("label", "")), "CSF 本地化")
	_add_detail_section("文本")
	_add_detail_paragraph(str(entry.get("text", "")), Color("#F1F5F6"), 20)
	_add_detail_section("来源")
	_add_detail_property("文件", str(entry.get("source", "")))
	_add_detail_property("数据层", str(entry.get("layer", "")))
	_add_detail_property("覆盖历史", str(entry.get("history_count", 0)))

func _show_map(entry: Dictionary) -> void:
	_current_entity.clear()
	_reset_preview("地图图像渲染将在地图阶段实现。")
	_clear_audio_options()
	_clear_details()
	_add_detail_title(str(entry.get("display_name", entry.get("name", entry.get("id", "")))), str(entry.get("filename", "")))
	_add_detail_section("地图属性")
	_add_detail_property("作者", str(entry.get("author", "")))
	_add_detail_property("剧院", str(entry.get("theater", "")))
	_add_detail_property("尺寸", "%s × %s" % [str(entry.get("width", 0)), str(entry.get("height", 0))])
	_add_detail_property("模式", str(entry.get("game_mode", "")))
	_add_detail_property("路径点", str(entry.get("waypoint_count", 0)))
	_add_detail_section("脚本结构")
	_add_detail_property("Triggers", str(entry.get("trigger_count", 0)))
	_add_detail_property("TeamTypes", str(entry.get("team_type_count", 0)))
	_add_detail_property("ScriptTypes", str(entry.get("script_type_count", 0)))
	_add_detail_property("TaskForces", str(entry.get("task_force_count", 0)))
	_add_detail_section("原始文件")
	_add_detail_paragraph(str(entry.get("resource_path", "")), Color("#93B1BE"))

func _load_entity_preview(entity_id: String) -> void:
	_reset_preview("正在读取预览……")
	var manifest_path: String = RA2Database.preview_manifest_path(entity_id)
	# A missing preview is a normal catalog state, not a database failure.
	# Some civilian, dummy and unsupported objects intentionally have no manifest.
	if not FileAccess.file_exists(manifest_path):
		_preview_message.text = "此对象尚未生成动画预览。\n资源定义仍可在右侧查看，不会写入调试器错误。"
		return
	var parsed: Variant = RA2Database.load_json(manifest_path, false)
	if not parsed is Dictionary:
		_preview_message.text = "预览清单无法解析。\n请重新运行 RA2 资源预览生成器。"
		return
	_preview_manifest = parsed as Dictionary
	_preview_manifest_dir = manifest_path.get_base_dir()
	_populate_theater_options()
	_populate_animation_options()

func _populate_theater_options() -> void:
	_theater_option.clear()
	var theaters: Array = []
	if _preview_manifest.has("theaters"):
		theaters = _as_array(_preview_manifest.get("available_theaters", []))
		if theaters.is_empty():
			theaters = (_preview_manifest.get("theaters", {}) as Dictionary).keys()
	else:
		var single_theater: String = str(_preview_manifest.get("theater", ""))
		if not single_theater.is_empty():
			theaters.append(single_theater)
	if theaters.is_empty():
		_theater_option.add_item("通用")
		_theater_option.disabled = true
		return
	for theater_variant in theaters:
		var theater_name: String = str(theater_variant)
		_theater_option.add_item(_theater_display_name(theater_name))
		_theater_option.set_item_metadata(_theater_option.item_count - 1, theater_name)
	var default_theater: String = str(_preview_manifest.get("default_theater", _preview_manifest.get("theater", "")))
	for index in range(_theater_option.item_count):
		if str(_theater_option.get_item_metadata(index)) == default_theater:
			_theater_option.select(index)
			break
	_theater_option.disabled = _theater_option.item_count <= 1

func _theater_display_name(theater_name: String) -> String:
	match theater_name:
		"temperate":
			return "温带"
		"snow":
			return "雪地"
		"urban":
			return "城市"
		"desert":
			return "沙漠"
		"lunar":
			return "月球"
		"newurban":
			return "新城市"
		_:
			return theater_name

func _current_animation_dictionary() -> Dictionary:
	if _preview_manifest.has("theaters"):
		var theater_name: String = _selected_theater_name()
		var theater_data: Dictionary = (_preview_manifest.get("theaters", {}) as Dictionary).get(theater_name, {}) as Dictionary
		return theater_data.get("animations", {}) as Dictionary
	return _preview_manifest.get("animations", {}) as Dictionary

func _selected_theater_name() -> String:
	if _theater_option.item_count == 0:
		return ""
	var metadata: Variant = _theater_option.get_item_metadata(_theater_option.selected)
	return str(metadata) if metadata != null else ""

func _populate_animation_options() -> void:
	_animation_option.clear()
	var animations: Dictionary = _current_animation_dictionary()
	for animation_key_variant in animations.keys():
		var animation_key: String = str(animation_key_variant)
		var animation: Dictionary = animations[animation_key_variant] as Dictionary
		_animation_option.add_item(str(animation.get("label", animation_key)))
		_animation_option.set_item_metadata(_animation_option.item_count - 1, animation_key)
	if _animation_option.item_count == 0:
		_preview_message.text = "预览清单中没有有效动画。"
		return
	var default_animation: String = str(_preview_manifest.get("default_animation", ""))
	for index in range(_animation_option.item_count):
		if str(_animation_option.get_item_metadata(index)) == default_animation:
			_animation_option.select(index)
			break
	_load_selected_animation()

func _load_selected_animation() -> void:
	_current_frames.clear()
	_current_masks.clear()
	_current_source_indices.clear()
	_frame_index = 0
	if _animation_option.item_count == 0:
		_render_preview_frame()
		return
	var animation_key: String = str(_animation_option.get_item_metadata(_animation_option.selected))
	var animations: Dictionary = _current_animation_dictionary()
	var animation: Dictionary = animations.get(animation_key, {}) as Dictionary
	_animation_rate_ms = int(animation.get("rate_ms", 120))
	_populate_direction_options(animation)
	_read_animation_frames(animation)
	_apply_timer_rate()
	_preview_playing = true
	_play_pause_button.text = "暂停"
	_render_preview_frame()
	if _current_frames.size() > 1:
		_preview_timer.start()

func _populate_direction_options(animation: Dictionary) -> void:
	_direction_option.clear()
	var directional: bool = bool(animation.get("directional", false))
	if not directional:
		_direction_option.add_item("不分方向")
		_direction_option.set_item_metadata(0, 0)
		_direction_option.disabled = true
		return
	var facing_count: int = max(1, int(animation.get("facing_count", 8)))
	for facing in range(facing_count):
		var label_text: String = DIRECTION_LABELS_8[facing] if facing_count == 8 and facing < DIRECTION_LABELS_8.size() else "方向 %02d" % facing
		_direction_option.add_item(label_text)
		_direction_option.set_item_metadata(_direction_option.item_count - 1, facing)
	_direction_option.disabled = facing_count <= 1

func _read_animation_frames(animation: Dictionary) -> void:
	if bool(animation.get("directional", false)):
		var facing: int = 0
		if _direction_option.item_count > 0:
			facing = int(_direction_option.get_item_metadata(_direction_option.selected))
		var directions: Dictionary = animation.get("directions", {}) as Dictionary
		var direction_data: Dictionary = directions.get(str(facing), {}) as Dictionary
		_current_frames = _packed_strings(direction_data.get("frames", []))
		_current_masks = _packed_strings(direction_data.get("remap_masks", []))
		_current_source_indices = _as_array(direction_data.get("source_indices", []))
	else:
		_current_frames = _packed_strings(animation.get("frames", []))
		_current_masks = _packed_strings(animation.get("remap_masks", []))
		_current_source_indices = _as_array(animation.get("source_indices", []))

func _packed_strings(value: Variant) -> PackedStringArray:
	var output: PackedStringArray = PackedStringArray()
	for item_variant in _as_array(value):
		output.append(str(item_variant))
	return output

func _preview_asset_base_dir() -> String:
	if _preview_manifest.has("theaters"):
		return _preview_manifest_dir.path_join(_selected_theater_name())
	return _preview_manifest_dir

func _render_preview_frame() -> void:
	if _current_frames.is_empty():
		_preview_base.texture = null
		_preview_remap.texture = null
		_preview_message.text = "该动画或方向没有有效帧。"
		_frame_status.text = "0 / 0"
		_preview_timer.stop()
		return
	_frame_index = clampi(_frame_index, 0, _current_frames.size() - 1)
	var base_dir: String = _preview_asset_base_dir()
	var frame_path: String = base_dir.path_join(_current_frames[_frame_index])
	_preview_base.texture = _load_image_texture(frame_path)
	if _frame_index < _current_masks.size():
		var mask_path: String = base_dir.path_join(_current_masks[_frame_index])
		_preview_remap.texture = _load_image_texture(mask_path)
	else:
		_preview_remap.texture = null
	_preview_message.text = "" if _preview_base.texture != null else "无法读取帧：%s" % frame_path
	var source_text: String = ""
	if _frame_index < _current_source_indices.size():
		source_text = " · 源帧 %s" % str(_current_source_indices[_frame_index])
	_frame_status.text = "%d / %d%s" % [_frame_index + 1, _current_frames.size(), source_text]

func _load_image_texture(resource_path: String) -> Texture2D:
	var cached: Variant = _texture_cache.get(resource_path)
	if cached is Texture2D:
		return cached as Texture2D
	if not FileAccess.file_exists(resource_path):
		return null
	var image: Image = Image.load_from_file(resource_path)
	if image == null or image.is_empty():
		return null
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	_texture_cache[resource_path] = texture
	if _texture_cache.size() > 256:
		_texture_cache.erase(_texture_cache.keys()[0])
	return texture

func _reset_preview(message: String) -> void:
	if _preview_timer != null:
		_preview_timer.stop()
	_preview_manifest.clear()
	_preview_manifest_dir = ""
	_current_frames.clear()
	_current_masks.clear()
	_current_source_indices.clear()
	_frame_index = 0
	if _preview_base != null:
		_preview_base.texture = null
		_preview_remap.texture = null
		_preview_message.text = message
		_animation_option.clear()
		_direction_option.clear()
		_theater_option.clear()
		_frame_status.text = "0 / 0"

func _on_animation_changed(_index: int) -> void:
	_load_selected_animation()

func _on_direction_changed(_index: int) -> void:
	var animations: Dictionary = _current_animation_dictionary()
	if _animation_option.item_count == 0:
		return
	var animation_key: String = str(_animation_option.get_item_metadata(_animation_option.selected))
	var animation: Dictionary = animations.get(animation_key, {}) as Dictionary
	_current_frames.clear()
	_current_masks.clear()
	_current_source_indices.clear()
	_frame_index = 0
	_read_animation_frames(animation)
	_render_preview_frame()

func _on_theater_changed(_index: int) -> void:
	_populate_animation_options()

func _on_team_color_changed(_index: int) -> void:
	if _team_color_option.item_count == 0:
		return
	var color_hex: String = str(_team_color_option.get_item_metadata(_team_color_option.selected))
	_preview_remap.modulate = Color(color_hex)

func _toggle_preview_playback() -> void:
	_preview_playing = not _preview_playing
	_play_pause_button.text = "暂停" if _preview_playing else "播放"
	if _preview_playing and _current_frames.size() > 1:
		_preview_timer.start()
	else:
		_preview_timer.stop()

func _step_previous_frame() -> void:
	if _current_frames.is_empty():
		return
	_preview_timer.stop()
	_preview_playing = false
	_play_pause_button.text = "播放"
	_frame_index = posmod(_frame_index - 1, _current_frames.size())
	_render_preview_frame()

func _step_next_frame() -> void:
	if _current_frames.is_empty():
		return
	_preview_timer.stop()
	_preview_playing = false
	_play_pause_button.text = "播放"
	_frame_index = (_frame_index + 1) % _current_frames.size()
	_render_preview_frame()

func _advance_preview() -> void:
	if not _preview_playing or _current_frames.size() <= 1:
		_preview_timer.stop()
		return
	if _frame_index + 1 >= _current_frames.size():
		if not _loop_check.button_pressed:
			_preview_playing = false
			_play_pause_button.text = "播放"
			_preview_timer.stop()
			return
		_frame_index = 0
	else:
		_frame_index += 1
	_render_preview_frame()

func _on_speed_changed(_value: float) -> void:
	_apply_timer_rate()

func _apply_timer_rate() -> void:
	if _preview_timer == null:
		return
	var speed: float = maxf(float(_speed_slider.value), 0.05)
	_preview_timer.wait_time = maxf(0.02, (float(_animation_rate_ms) / 1000.0) / speed)

func _populate_entity_audio(entity: Dictionary) -> void:
	var events: Array = []
	var resolved: Dictionary = entity.get("resolved_sounds", {}) as Dictionary
	for role_variant in resolved.keys():
		var role: String = str(role_variant)
		for event_variant in _as_array(resolved[role_variant]):
			if event_variant is Dictionary:
				var event_copy: Dictionary = (event_variant as Dictionary).duplicate(true)
				event_copy["browser_role"] = role
				events.append(event_copy)
	_populate_audio_events(events)

func _populate_audio_events(events: Array) -> void:
	_audio_events.clear()
	_audio_event_option.clear()
	for event_variant in events:
		if not event_variant is Dictionary:
			continue
		var event: Dictionary = event_variant as Dictionary
		if _as_array(event.get("samples", [])).is_empty():
			continue
		_audio_events.append(event)
		var role: String = str(event.get("browser_role", ""))
		var label_text: String = str(event.get("id", ""))
		if not role.is_empty():
			label_text = "%s · %s" % [role, label_text]
		_audio_event_option.add_item(label_text)
		_audio_event_option.set_item_metadata(_audio_event_option.item_count - 1, _audio_events.size() - 1)
	_audio_event_option.disabled = _audio_events.is_empty()
	_audio_play_button.disabled = _audio_events.is_empty()
	_audio_random_button.disabled = _audio_events.is_empty()
	if _audio_events.is_empty():
		_audio_sample_option.clear()
		_audio_sample_option.disabled = true
		_audio_status.text = "当前条目没有可播放声音。"
		return
	_audio_event_option.select(0)
	_load_audio_event_samples(0)

func _on_audio_event_changed(index: int) -> void:
	_load_audio_event_samples(index)

func _load_audio_event_samples(option_index: int) -> void:
	_audio_samples.clear()
	_audio_sample_option.clear()
	if option_index < 0 or option_index >= _audio_event_option.item_count:
		return
	var event_index: int = int(_audio_event_option.get_item_metadata(option_index))
	if event_index < 0 or event_index >= _audio_events.size():
		return
	var event: Dictionary = _audio_events[event_index]
	for sample_variant in _as_array(event.get("samples", [])):
		if sample_variant is Dictionary:
			var sample: Dictionary = sample_variant as Dictionary
			_audio_samples.append(sample)
			_audio_sample_option.add_item("%s · %s" % [str(sample.get("name", "")), str(sample.get("source_bank", ""))])
			_audio_sample_option.set_item_metadata(_audio_sample_option.item_count - 1, _audio_samples.size() - 1)
	_audio_sample_option.disabled = _audio_samples.is_empty()
	if not _audio_samples.is_empty():
		_audio_sample_option.select(0)
	_audio_status.text = "%s：%d 个样本" % [str(event.get("id", "")), _audio_samples.size()]

func _on_audio_sample_changed(_index: int) -> void:
	if _audio_sample_option.item_count == 0:
		return
	var sample_index: int = int(_audio_sample_option.get_item_metadata(_audio_sample_option.selected))
	if sample_index >= 0 and sample_index < _audio_samples.size():
		var sample: Dictionary = _audio_samples[sample_index]
		_audio_status.text = "%s · %s Hz · %s" % [str(sample.get("name", "")), str(sample.get("sample_rate", "")), str(sample.get("resource_path", ""))]

func _selected_audio_event() -> Dictionary:
	if _audio_event_option.item_count == 0:
		return {}
	var event_index: int = int(_audio_event_option.get_item_metadata(_audio_event_option.selected))
	if event_index >= 0 and event_index < _audio_events.size():
		return _audio_events[event_index]
	return {}

func _play_current_audio_sample() -> void:
	var event: Dictionary = _selected_audio_event()
	if event.is_empty() or _audio_sample_option.item_count == 0:
		return
	var sample_index: int = int(_audio_sample_option.get_item_metadata(_audio_sample_option.selected))
	RA2AudioService.play_event_sample(str(event.get("id", "")), sample_index)

func _play_random_audio_event() -> void:
	var event: Dictionary = _selected_audio_event()
	if event.is_empty():
		return
	RA2AudioService.play_event(str(event.get("id", "")), true)

func _stop_audio() -> void:
	RA2AudioService.stop_all()

func _on_audio_volume_changed(value: float) -> void:
	RA2AudioService.set_master_volume_linear(value)

func _on_audio_sample_started(event_id: String, sample_name: String, resource_path: String) -> void:
	_audio_status.text = "正在播放：%s / %s\n%s" % [event_id, sample_name, resource_path]

func _on_audio_playback_failed(event_id: String, reason: String) -> void:
	_audio_status.text = "播放失败：%s\n%s" % [event_id, reason]

func _on_audio_stopped() -> void:
	_audio_status.text = "已停止播放。"

func _clear_audio_options() -> void:
	_audio_events.clear()
	_audio_samples.clear()
	if _audio_event_option != null:
		_audio_event_option.clear()
		_audio_sample_option.clear()
		_audio_event_option.disabled = true
		_audio_sample_option.disabled = true
		_audio_play_button.disabled = true
		_audio_random_button.disabled = true
		_audio_status.text = "当前条目没有可播放声音。"

func _build_entity_details(entity: Dictionary) -> void:
	_clear_details()
	_add_detail_title(str(entity.get("display_name", entity.get("id", ""))), "%s · %s" % [str(entity.get("id", "")), str(entity.get("name_token", ""))])
	_add_detail_section("基础属性")
	_add_detail_property("类别", str(entity.get("category", "")))
	_add_detail_property("Art ID", str(entity.get("art_id", "")))
	_add_detail_property("视觉格式", str((entity.get("visuals", {}) as Dictionary).get("kind", "missing")))
	_add_detail_property("所属国家", ", ".join(_string_array(entity.get("owners", []))))
	_add_detail_property("造价", str(entity.get("cost", 0)))
	_add_detail_property("科技等级", str(entity.get("tech_level", -1)))
	_add_detail_property("生命", str(entity.get("strength", 0)))
	_add_detail_property("护甲", str(entity.get("armor", "")))
	_add_detail_property("速度", str(entity.get("speed", 0)))
	_add_detail_property("视野", str(entity.get("sight", 0)))

	_add_detail_section("武器引用")
	var weapons: Dictionary = entity.get("weapons", {}) as Dictionary
	if weapons.is_empty():
		_add_detail_paragraph("无武器。", Color("#8EA5AF"))
	else:
		for key_variant in weapons.keys():
			var weapon: Dictionary = weapons[key_variant] as Dictionary
			_add_detail_property(str(key_variant), "%s → %s → %s" % [str(weapon.get("id", "")), str(weapon.get("projectile", "")), str(weapon.get("warhead", ""))])

	_add_detail_section("素材解析")
	var visuals: Dictionary = entity.get("visuals", {}) as Dictionary
	if str(visuals.get("kind", "")) == "voxel":
		for asset_key in ["body", "body_hva", "turret", "turret_hva", "barrel", "barrel_hva"]:
			var asset: Variant = visuals.get(asset_key)
			if asset is Dictionary:
				_add_detail_property(asset_key, str((asset as Dictionary).get("relative_path", "")))
		_add_detail_property("TurretOffset", str(visuals.get("turret_offset_leptons", 0)))
		_add_detail_property("PrimaryFireFLH", str(visuals.get("primary_fire_flh", "")))
		_add_detail_property("SecondaryFireFLH", str(visuals.get("secondary_fire_flh", "")))
	else:
		var theaters: Dictionary = visuals.get("theaters", {}) as Dictionary
		for theater_variant in theaters.keys():
			var theater_data: Dictionary = theaters[theater_variant] as Dictionary
			var body_variant: Variant = theater_data.get("body")
			if body_variant is Dictionary:
				_add_detail_property(_theater_display_name(str(theater_variant)), str((body_variant as Dictionary).get("relative_path", "")))
		var sequence_id: String = str(visuals.get("sequence_id", ""))
		if not sequence_id.is_empty():
			_add_detail_property("Sequence", sequence_id)
			_add_detail_property("序列数量", str((visuals.get("sequences", {}) as Dictionary).size()))
		var components: Dictionary = visuals.get("components", {}) as Dictionary
		if not components.is_empty():
			_add_detail_property("建筑组件", ", ".join(_string_array(components.keys())))

	_add_detail_section("声音")
	var resolved_sounds: Dictionary = entity.get("resolved_sounds", {}) as Dictionary
	if resolved_sounds.is_empty():
		_add_detail_paragraph("无可用声音。", Color("#8EA5AF"))
	else:
		for role_variant in resolved_sounds.keys():
			var events: Array = _as_array(resolved_sounds[role_variant])
			var sample_count: int = 0
			var event_names: PackedStringArray = PackedStringArray()
			for event_variant in events:
				if event_variant is Dictionary:
					var event: Dictionary = event_variant as Dictionary
					sample_count += _as_array(event.get("samples", [])).size()
					event_names.append(str(event.get("id", "")))
			_add_detail_property(str(role_variant), "%s（%d 样本）" % [", ".join(event_names), sample_count])

	_add_detail_section("字段来源")
	var rules: Dictionary = entity.get("rules", {}) as Dictionary
	var provenance: Dictionary = rules.get("provenance", {}) as Dictionary
	for source_key in ["UIName", "Image", "Owner", "Primary", "Secondary", "Prerequisite", "Cost", "Strength"]:
		var source_item: Variant = provenance.get(source_key)
		if source_item is Dictionary:
			var source_dict: Dictionary = source_item as Dictionary
			var origin: Dictionary = source_dict.get("origin", {}) as Dictionary
			_add_detail_property(source_key, "%s\n%s:%s · %s" % [str(source_dict.get("value", "")), str(origin.get("file", "")), str(origin.get("line", 0)), str(origin.get("layer", ""))])

func _clear_details() -> void:
	if _detail_box == null:
		return
	for child in _detail_box.get_children():
		_detail_box.remove_child(child)
		child.queue_free()

func _add_empty_detail(message: String) -> void:
	_add_detail_paragraph(message, Color("#9FB0BA"), 17)

func _add_detail_title(title_text: String, subtitle_text: String) -> void:
	var title: Label = Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", Color("#F1F6F7"))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_constant_override("line_spacing", 4)
	_detail_box.add_child(title)
	var subtitle: Label = Label.new()
	subtitle.text = subtitle_text
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color("#83B9CF"))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_constant_override("line_spacing", 3)
	_detail_box.add_child(subtitle)

func _add_detail_section(title_text: String) -> void:
	var separator: HSeparator = HSeparator.new()
	separator.custom_minimum_size = Vector2(0, 8)
	_detail_box.add_child(separator)
	var heading: Label = Label.new()
	heading.text = title_text
	heading.add_theme_font_size_override("font_size", 19)
	heading.add_theme_color_override("font_color", Color("#E3EDF0"))
	heading.custom_minimum_size = Vector2(0, 30)
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_detail_box.add_child(heading)

func _add_detail_property(caption: String, value: String) -> void:
	var row: VBoxContainer = VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	_detail_box.add_child(row)
	var caption_label: Label = Label.new()
	caption_label.text = caption
	caption_label.add_theme_font_size_override("font_size", 13)
	caption_label.add_theme_color_override("font_color", Color("#82A7B7"))
	caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(caption_label)
	var value_label: Label = Label.new()
	value_label.text = value if not value.is_empty() else "—"
	value_label.add_theme_font_size_override("font_size", 16)
	value_label.add_theme_color_override("font_color", Color("#E7EFF2"))
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value_label.add_theme_constant_override("line_spacing", 4)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value_label)

func _add_detail_paragraph(text_value: String, text_color: Color, font_size: int = 15) -> void:
	var label: Label = Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", text_color)
	label.add_theme_constant_override("line_spacing", 5)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_box.add_child(label)

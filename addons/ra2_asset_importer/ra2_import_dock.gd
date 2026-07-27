@tool
extends VBoxContainer

var source_path_edit: LineEdit
var output_path_edit: LineEdit
var config_path_edit: LineEdit
var status_label: RichTextLabel
var import_button: Button


func _ready() -> void:
    name = "RA2 素材导入"
    custom_minimum_size = Vector2(330, 360)

    var title := Label.new()
    title.text = "红警 2 / 尤里的复仇素材导入"
    title.add_theme_font_size_override("font_size", 16)
    add_child(title)

    var help := Label.new()
    help.text = "将 SHP(TS)、VXL/HVA 转为 PNG/TRES；WAV 直接交给 Godot 导入。"
    help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    add_child(help)

    source_path_edit = _add_path_row("源目录", "res://assets/ra2_sources/samples")
    output_path_edit = _add_path_row("输出目录", "res://assets/ra2_imported")
    config_path_edit = _add_path_row("配置文件", "res://assets/ra2_sources/samples/ra2_import.json")

    import_button = Button.new()
    import_button.text = "扫描并导入全部素材"
    import_button.pressed.connect(_run_import)
    add_child(import_button)

    var rescan_button := Button.new()
    rescan_button.text = "仅刷新 Godot 文件系统"
    rescan_button.pressed.connect(_rescan_filesystem)
    add_child(rescan_button)

    status_label = RichTextLabel.new()
    status_label.bbcode_enabled = true
    status_label.fit_content = false
    status_label.custom_minimum_size = Vector2(0, 180)
    status_label.text = "[color=gray]等待导入。需要本机 Python 3 和 Pillow。[/color]"
    add_child(status_label)


func _add_path_row(label_text: String, default_value: String) -> LineEdit:
    var label := Label.new()
    label.text = label_text
    add_child(label)
    var edit := LineEdit.new()
    edit.text = default_value
    edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    add_child(edit)
    return edit


func _run_import() -> void:
    import_button.disabled = true
    status_label.text = "[color=yellow]正在转换，请等待……[/color]"
    var script_path := ProjectSettings.globalize_path("res://tools/ra2_import.py")
    var source_path := ProjectSettings.globalize_path(source_path_edit.text.strip_edges())
    var output_path := ProjectSettings.globalize_path(output_path_edit.text.strip_edges())
    var config_path := ProjectSettings.globalize_path(config_path_edit.text.strip_edges())
    var project_root := ProjectSettings.globalize_path("res://")
    var base_arguments := PackedStringArray([
        script_path,
        "--project-root",
        project_root,
        "scan",
        source_path,
        output_path,
        "--config",
        config_path,
    ])

    var attempts := [
        {"executable": "py", "prefix": PackedStringArray(["-3"])},
        {"executable": "python", "prefix": PackedStringArray()},
        {"executable": "python3", "prefix": PackedStringArray()},
    ]
    var messages: Array[String] = []
    var success := false
    for attempt in attempts:
        var command_output: Array = []
        var arguments := PackedStringArray(attempt["prefix"])
        arguments.append_array(base_arguments)
        var executable := str(attempt["executable"])
        var exit_code := OS.execute(executable, arguments, command_output, true, false)
        messages.append("%s：退出码 %d\n%s" % [executable, exit_code, "\n".join(PackedStringArray(command_output))])
        if exit_code == 0:
            success = true
            break

    if success:
        status_label.text = "[color=green]导入完成。[/color]\n" + "\n\n".join(messages)
        _rescan_filesystem()
    else:
        status_label.text = "[color=red]导入失败。确认 Python 3 与 Pillow 已安装。[/color]\n" + "\n\n".join(messages)
    import_button.disabled = false


func _rescan_filesystem() -> void:
    EditorInterface.get_resource_filesystem().scan()

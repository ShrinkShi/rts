extends RefCounted

static func panel_style(bg = Color("#18212A"), border = Color("#4D5D6B"), radius = 4):
    var style = StyleBoxFlat.new()
    style.bg_color = bg
    style.border_color = border
    style.set_border_width_all(1)
    style.corner_radius_top_left = radius
    style.corner_radius_top_right = radius
    style.corner_radius_bottom_left = radius
    style.corner_radius_bottom_right = radius
    style.content_margin_left = 16
    style.content_margin_right = 16
    style.content_margin_top = 14
    style.content_margin_bottom = 14
    return style

static func button_style(bg, border, radius = 3):
    var style = StyleBoxFlat.new()
    style.bg_color = bg
    style.border_color = border
    style.set_border_width_all(1)
    style.corner_radius_top_left = radius
    style.corner_radius_top_right = radius
    style.corner_radius_bottom_left = radius
    style.corner_radius_bottom_right = radius
    style.content_margin_left = 14
    style.content_margin_right = 14
    style.content_margin_top = 10
    style.content_margin_bottom = 10
    return style

static func style_button(button, primary = false):
    var normal_bg = Color("#31566B") if primary else Color("#202D38")
    var hover_bg = Color("#3C6A82") if primary else Color("#2B3C49")
    button.add_theme_stylebox_override("normal", button_style(normal_bg, Color("#607D8B")))
    button.add_theme_stylebox_override("hover", button_style(hover_bg, Color("#8FB4C6")))
    button.add_theme_stylebox_override("pressed", button_style(Color("#16212A"), Color("#8FB4C6")))
    button.add_theme_stylebox_override("focus", button_style(hover_bg, Color("#B9D7E5")))
    button.add_theme_color_override("font_color", Color("#EEF5F7"))
    button.add_theme_color_override("font_hover_color", Color.WHITE)
    button.add_theme_font_size_override("font_size", 17)
    button.custom_minimum_size = Vector2(250, 48)

static func style_option(option):
    option.add_theme_stylebox_override("normal", button_style(Color("#131C24"), Color("#526572")))
    option.add_theme_stylebox_override("hover", button_style(Color("#1D2B35"), Color("#7893A3")))
    option.add_theme_font_size_override("font_size", 15)
    option.custom_minimum_size = Vector2(220, 38)

static func heading(text, size = 24):
    var label = Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", size)
    label.add_theme_color_override("font_color", Color("#EAF2F5"))
    return label

static func muted_label(text, size = 14):
    var label = Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", size)
    label.add_theme_color_override("font_color", Color("#9FB0BA"))
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    return label

static func add_labeled_control(parent, caption, control):
    var row = HBoxContainer.new()
    row.add_theme_constant_override("separation", 16)
    var label = Label.new()
    label.text = caption
    label.custom_minimum_size = Vector2(120, 36)
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.add_theme_color_override("font_color", Color("#C9D5DB"))
    row.add_child(label)
    control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(control)
    parent.add_child(row)
    return row


static func style_compact_button(button, primary = false, minimum_width = 132.0):
    var normal_bg = Color("#31566B") if primary else Color("#202D38")
    var hover_bg = Color("#3C6A82") if primary else Color("#2B3C49")
    for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
        var bg = normal_bg
        var border = Color("#607D8B")
        if state_name == "hover" or state_name == "focus":
            bg = hover_bg
            border = Color("#8FB4C6")
        elif state_name == "pressed":
            bg = Color("#16212A")
        elif state_name == "disabled":
            bg = Color("#11191E")
            border = Color("#31434B")
        var style = button_style(bg, border, 3)
        style.content_margin_left = 9
        style.content_margin_right = 9
        style.content_margin_top = 5
        style.content_margin_bottom = 5
        button.add_theme_stylebox_override(state_name, style)
    button.add_theme_color_override("font_color", Color("#EEF5F7"))
    button.add_theme_color_override("font_hover_color", Color.WHITE)
    button.add_theme_color_override("font_disabled_color", Color("#62727A"))
    button.add_theme_font_size_override("font_size", 13)
    button.custom_minimum_size = Vector2(minimum_width, 34)

static func style_compact_option(option, minimum_width = 82.0):
    for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
        var bg = Color("#131C24")
        var border = Color("#526572")
        if state_name == "hover" or state_name == "focus":
            bg = Color("#1D2B35")
            border = Color("#7893A3")
        elif state_name == "pressed":
            bg = Color("#101820")
        elif state_name == "disabled":
            bg = Color("#111619")
            border = Color("#304049")
        var style = button_style(bg, border, 3)
        style.content_margin_left = 7
        style.content_margin_right = 7
        style.content_margin_top = 4
        style.content_margin_bottom = 4
        option.add_theme_stylebox_override(state_name, style)
    option.add_theme_font_size_override("font_size", 12)
    option.custom_minimum_size = Vector2(minimum_width, 32)

static func color_swatch_texture(hex_value, swatch_size = Vector2i(28, 18)):
    var color_text = str(hex_value)
    if not color_text.begins_with("#"):
        color_text = "#" + color_text
    var image = Image.create(swatch_size.x, swatch_size.y, false, Image.FORMAT_RGBA8)
    image.fill(Color("#0A1014"))
    var fill_color = Color(color_text)
    for y in range(2, swatch_size.y - 2):
        for x in range(2, swatch_size.x - 2):
            image.set_pixel(x, y, fill_color)
    return ImageTexture.create_from_image(image)

static func add_color_swatch_items(option, color_definitions):
    for item in color_definitions:
        var label_text = str(item[0])
        var hex_value = str(item[1])
        option.add_icon_item(color_swatch_texture(hex_value), "")
        var index = option.item_count - 1
        option.set_item_metadata(index, hex_value)
        option.get_popup().set_item_tooltip(index, label_text)

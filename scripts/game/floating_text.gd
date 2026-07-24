extends Node2D

var lifetime = 0.85
var elapsed = 0.0
var rise_speed = 34.0
var text_label

func setup(text_value, color_value):
    z_index = 110
    text_label = Label.new()
    text_label.text = str(text_value)
    text_label.position = Vector2(-48, -22)
    text_label.size = Vector2(96, 28)
    text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    text_label.add_theme_font_size_override("font_size", 16)
    text_label.add_theme_color_override("font_color", color_value)
    text_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
    text_label.add_theme_constant_override("shadow_offset_x", 1)
    text_label.add_theme_constant_override("shadow_offset_y", 1)
    text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(text_label)

func _process(delta):
    elapsed += delta
    position.y -= rise_speed * delta
    if is_instance_valid(text_label):
        text_label.modulate.a = clamp(1.0 - elapsed / lifetime, 0.0, 1.0)
    if elapsed >= lifetime:
        queue_free()

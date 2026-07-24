extends Resource
class_name EntityVisualProfile

## Visual-only tuning. These values never scale the logical Node2D or navigation grid.
@export var visual_scale_multiplier := Vector2.ONE
@export var visual_offset := Vector2.ZERO
@export var turret_scale_multiplier := Vector2.ONE
@export var turret_offset := Vector2.ZERO
@export_range(0.25, 3.0, 0.01) var selection_scale := 1.0

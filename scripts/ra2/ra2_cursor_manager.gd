extends Node

# Runtime RA2/YR cursor loader. Source mouse.shp and mousepal.pal are converted
# offline to compressed palette-index chunks so public builds do not need the
# original source archives.
const FrameChunk00 = preload("res://scripts/ra2/cursor_chunks/frame_00.gd")
const FrameChunk01 = preload("res://scripts/ra2/cursor_chunks/frame_01.gd")
const FrameChunk02 = preload("res://scripts/ra2/cursor_chunks/frame_02.gd")
const FrameChunk03 = preload("res://scripts/ra2/cursor_chunks/frame_03.gd")
const FrameChunk04 = preload("res://scripts/ra2/cursor_chunks/frame_04.gd")
const FrameChunk05 = preload("res://scripts/ra2/cursor_chunks/frame_05.gd")
const FrameChunk06 = preload("res://scripts/ra2/cursor_chunks/frame_06.gd")
const FrameChunk07 = preload("res://scripts/ra2/cursor_chunks/frame_07.gd")
const FrameChunk08 = preload("res://scripts/ra2/cursor_chunks/frame_08.gd")
const FrameChunk09 = preload("res://scripts/ra2/cursor_chunks/frame_09.gd")
const PaletteChunk = preload("res://scripts/ra2/cursor_chunks/palette.gd")

const FRAME_WIDTH := 55
const FRAME_HEIGHT := 43
const SOURCE_FRAME_INDICES := [0, 2, 3, 4, 5, 6, 7, 8, 9, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248]
const STATES := {
    "default": {"frames": [0], "fps": 0.0, "hotspot": [1, 1]},
    "edge_n": {"frames": [2], "fps": 0.0, "hotspot": [27, 1]},
    "edge_ne": {"frames": [3], "fps": 0.0, "hotspot": [53, 1]},
    "edge_e": {"frames": [4], "fps": 0.0, "hotspot": [53, 21]},
    "edge_se": {"frames": [5], "fps": 0.0, "hotspot": [53, 41]},
    "edge_s": {"frames": [6], "fps": 0.0, "hotspot": [27, 41]},
    "edge_sw": {"frames": [7], "fps": 0.0, "hotspot": [1, 41]},
    "edge_w": {"frames": [8], "fps": 0.0, "hotspot": [1, 21]},
    "edge_nw": {"frames": [9], "fps": 0.0, "hotspot": [1, 1]},
    "select": {"frames": [18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30], "fps": 15.625, "hotspot": [27, 21]},
    "selected": {"frames": [18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30], "fps": 15.625, "hotspot": [27, 21]},
    "move": {"frames": [31, 32, 33, 34, 35, 36, 37, 38, 39, 40], "fps": 15.625, "hotspot": [27, 21]},
    "move_invalid": {"frames": [41], "fps": 0.0, "hotspot": [27, 21]},
    "attack": {"frames": [53, 54, 55, 56, 57], "fps": 15.625, "hotspot": [27, 21]},
    "enemy": {"frames": [58, 59, 60, 61, 62], "fps": 15.625, "hotspot": [27, 21]},
    "build_valid": {"frames": [110, 111, 112, 113, 114, 115, 116, 117, 118], "fps": 15.625, "hotspot": [27, 21]},
    "build_invalid": {"frames": [119], "fps": 0.0, "hotspot": [27, 21]},
    "primary": {"frames": [239, 240, 241, 242, 243, 244, 245, 246, 247, 248], "fps": 15.625, "hotspot": [27, 21]},
    "pan": {"frames": [31, 32, 33, 34, 35, 36, 37, 38, 39, 40], "fps": 15.625, "hotspot": [27, 21]},
}

var textures: Dictionary = {}
var hotspots: Dictionary = {}
var animation_fps: Dictionary = {}
var current_state: String = ""
var current_frame_index: int = 0
var current_frame_elapsed: float = 0.0
var loaded: bool = false


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    loaded = _decode_cursor_frames()
    if not loaded:
        push_warning("RA2 cursor data failed to load; using the operating-system cursor.")
        Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
    set_state("default", true)


func _process(delta: float) -> void:
    if not loaded or current_state.is_empty():
        return
    var frames: Array = textures.get(current_state, [])
    if frames.size() <= 1:
        return
    var fps: float = float(animation_fps.get(current_state, 0.0))
    if fps <= 0.0:
        return
    var frame_duration: float = 1.0 / fps
    current_frame_elapsed += delta
    while current_frame_elapsed >= frame_duration:
        current_frame_elapsed -= frame_duration
        current_frame_index = (current_frame_index + 1) % frames.size()
        _apply_current_cursor()


func set_state(state: String, force: bool = false) -> void:
    if not loaded:
        return
    var next_state: String = state if textures.has(state) else "default"
    if current_state == next_state and not force:
        return
    current_state = next_state
    current_frame_index = 0
    current_frame_elapsed = 0.0
    _apply_current_cursor()


func reset() -> void:
    if loaded:
        set_state("default", true)
    else:
        Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)


func is_using_ra2_cursor() -> bool:
    return loaded


func _apply_current_cursor() -> void:
    var frames: Array = textures.get(current_state, [])
    if frames.is_empty():
        return
    current_frame_index = clampi(current_frame_index, 0, frames.size() - 1)
    var texture: Texture2D = frames[current_frame_index] as Texture2D
    if texture == null:
        return
    Input.set_custom_mouse_cursor(
        texture,
        Input.CURSOR_ARROW,
        hotspots.get(current_state, Vector2(27, 21))
    )


func _decode_cursor_frames() -> bool:
    var encoded: String = FrameChunk00.DATA + FrameChunk01.DATA + FrameChunk02.DATA + FrameChunk03.DATA + FrameChunk04.DATA + FrameChunk05.DATA + FrameChunk06.DATA + FrameChunk07.DATA + FrameChunk08.DATA + FrameChunk09.DATA
    var compressed: PackedByteArray = Marshalls.base64_to_raw(encoded)
    var palette: PackedByteArray = Marshalls.base64_to_raw(PaletteChunk.DATA)
    var pixels_per_frame: int = FRAME_WIDTH * FRAME_HEIGHT
    var expected_size: int = pixels_per_frame * SOURCE_FRAME_INDICES.size()
    var indexed: PackedByteArray = compressed.decompress(
        expected_size,
        FileAccess.COMPRESSION_DEFLATE
    )
    if indexed.size() != expected_size or palette.size() != 768:
        return false

    var source_textures: Dictionary = {}
    for slot in range(SOURCE_FRAME_INDICES.size()):
        var rgba := PackedByteArray()
        rgba.resize(pixels_per_frame * 4)
        var source_offset: int = slot * pixels_per_frame
        for pixel_index in range(pixels_per_frame):
            var palette_index: int = int(indexed[source_offset + pixel_index])
            var output_offset: int = pixel_index * 4
            if palette_index == 0:
                rgba[output_offset + 3] = 0
                continue
            var palette_offset: int = palette_index * 3
            rgba[output_offset] = _expand_component(int(palette[palette_offset]))
            rgba[output_offset + 1] = _expand_component(int(palette[palette_offset + 1]))
            rgba[output_offset + 2] = _expand_component(int(palette[palette_offset + 2]))
            rgba[output_offset + 3] = 255
        var image := Image.create_from_data(
            FRAME_WIDTH,
            FRAME_HEIGHT,
            false,
            Image.FORMAT_RGBA8,
            rgba
        )
        source_textures[int(SOURCE_FRAME_INDICES[slot])] = ImageTexture.create_from_image(image)

    for state_key_variant in STATES.keys():
        var state_key: String = str(state_key_variant)
        var definition: Dictionary = STATES[state_key_variant]
        var frames: Array = []
        for source_frame_variant in definition.get("frames", []):
            var source_frame: int = int(source_frame_variant)
            if source_textures.has(source_frame):
                frames.append(source_textures[source_frame])
        if frames.is_empty():
            continue
        textures[state_key] = frames
        animation_fps[state_key] = float(definition.get("fps", 0.0))
        var hotspot: Array = definition.get("hotspot", [27, 21])
        hotspots[state_key] = Vector2(
            clamp(float(hotspot[0]), 0.0, float(FRAME_WIDTH - 1)),
            clamp(float(hotspot[1]), 0.0, float(FRAME_HEIGHT - 1))
        )

    print(
        "RA2 cursor loaded: %d states from %d source frames."
        % [textures.size(), source_textures.size()]
    )
    return textures.has("default")


func _expand_component(component: int) -> int:
    return clampi(int(round(float(component) * 255.0 / 63.0)), 0, 255)

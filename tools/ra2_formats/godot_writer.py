from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import json
import math
from typing import Iterable, Mapping, Sequence


@dataclass(frozen=True)
class AnimationSpec:
    name: str
    frame_indices: tuple[int, ...]
    fps: float = 8.0
    loop: bool = True


def godot_path(path: Path, project_root: Path) -> str:
    return "res://" + path.resolve().relative_to(project_root.resolve()).as_posix()


def _atlas_subresources(frame_count: int, columns: int, width: int, height: int) -> list[str]:
    blocks: list[str] = []
    for index in range(frame_count):
        x = (index % columns) * width
        y = (index // columns) * height
        blocks.append(
            "\n".join(
                [
                    f'[sub_resource type="AtlasTexture" id="AtlasTexture_{index}"]',
                    'atlas = ExtResource("1_atlas")',
                    f"region = Rect2({x}, {y}, {width}, {height})",
                    "filter_clip = true",
                ]
            )
        )
    return blocks


def write_sprite_frames(
    path: Path,
    atlas_res_path: str,
    frame_size: tuple[int, int],
    frame_count: int,
    columns: int,
    animations: Sequence[AnimationSpec],
) -> None:
    width, height = frame_size
    subresources = _atlas_subresources(frame_count, columns, width, height)
    animation_entries = []
    for spec in animations:
        safe_indices = [index for index in spec.frame_indices if 0 <= index < frame_count]
        if not safe_indices:
            continue
        frame_rows = []
        duration = 1.0
        for index in safe_indices:
            frame_rows.append(
                '{"duration": %.6f, "texture": SubResource("AtlasTexture_%d")}' % (duration, index)
            )
        animation_entries.append(
            "{\n"
            f'"frames": [{", ".join(frame_rows)}],\n'
            f'"loop": {str(spec.loop).lower()},\n'
            f'"name": &"{spec.name}",\n'
            f'"speed": {float(spec.fps):.6f}\n'
            "}"
        )
    content = [
        f"[gd_resource type=\"SpriteFrames\" load_steps={2 + len(subresources)} format=3]",
        "",
        f'[ext_resource type="Texture2D" path="{atlas_res_path}" id="1_atlas"]',
        "",
        *subresources,
        "",
        "[resource]",
        "animations = [" + ",\n".join(animation_entries) + "]",
        "",
    ]
    path.write_text("\n".join(content), encoding="utf-8")


def write_shp_resource(
    path: Path,
    atlas_res_path: str,
    frame_size: tuple[int, int],
    frame_count: int,
    columns: int,
    metadata_path: str,
) -> None:
    width, height = frame_size
    path.write_text(
        "\n".join(
            [
                '[gd_resource type="Resource" script_class="RA2SHPResource" load_steps=3 format=3]',
                "",
                '[ext_resource type="Script" path="res://scripts/ra2/ra2_shp_resource.gd" id="1_script"]',
                f'[ext_resource type="Texture2D" path="{atlas_res_path}" id="2_atlas"]',
                "",
                "[resource]",
                'script = ExtResource("1_script")',
                'atlas = ExtResource("2_atlas")',
                f"frame_size = Vector2i({width}, {height})",
                f"frame_count = {frame_count}",
                f"columns = {columns}",
                f'metadata_path = "{metadata_path}"',
                "",
            ]
        ),
        encoding="utf-8",
    )


def default_directional_animations(frame_count: int, facing_count: int = 8) -> list[AnimationSpec]:
    if frame_count <= 0:
        return []
    animations = [AnimationSpec("all_frames", tuple(range(frame_count)), 8.0, True)]
    for direction in range(facing_count):
        source = min(direction, frame_count - 1)
        for state in ("stand", "idle", "move", "attack", "death"):
            animations.append(AnimationSpec(f"{state}_{direction}", (source,), 1.0, state not in ("attack", "death")))
    return animations


def animations_from_config(
    config: Mapping[str, object] | None,
    frame_count: int,
    facing_count: int = 8,
) -> list[AnimationSpec]:
    if not config:
        return default_directional_animations(frame_count, facing_count)
    result = [AnimationSpec("all_frames", tuple(range(frame_count)), float(config.get("all_fps", 8.0)), True)]
    states = config.get("states", {})
    if not isinstance(states, Mapping):
        return default_directional_animations(frame_count, facing_count)
    for state_name, raw_state in states.items():
        if not isinstance(raw_state, Mapping):
            continue
        start = int(raw_state.get("start", 0))
        facings = int(raw_state.get("facings", facing_count))
        frames_per_facing = max(1, int(raw_state.get("frames_per_facing", 1)))
        fps = float(raw_state.get("fps", 8.0))
        loop = bool(raw_state.get("loop", state_name not in ("attack", "death")))
        direction_order = raw_state.get("direction_order", list(range(facings)))
        if not isinstance(direction_order, Sequence):
            direction_order = list(range(facings))
        for engine_direction in range(facing_count):
            source_direction = int(direction_order[engine_direction % len(direction_order)]) if direction_order else engine_direction
            base = start + source_direction * frames_per_facing
            indices = tuple(base + index for index in range(frames_per_facing))
            result.append(AnimationSpec(f"{state_name}_{engine_direction}", indices, fps, loop))
    return result


def write_json(path: Path, payload: object) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

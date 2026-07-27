from __future__ import annotations

from dataclasses import dataclass
import math
from typing import Sequence

from PIL import Image, ImageDraw

from .hva import HvaFile
from .vxl import VxlFile, VxlSection


@dataclass(frozen=True)
class VoxelPart:
    model: VxlFile
    animation: HvaFile | None = None
    frame_index: int = 0
    offset: tuple[float, float, float] = (0.0, 0.0, 0.0)


@dataclass(frozen=True)
class RenderSettings:
    canvas_width: int = 160
    canvas_height: int = 120
    pixel_size: int = 2
    horizontal_scale: float = 0.90
    vertical_scale: float = 0.45
    height_scale: float = 0.90
    anchor_x: float = 0.50
    anchor_y: float = 0.64
    yaw_offset_degrees: float = 0.0


def _matrix_point(point: tuple[float, float, float], matrix: Sequence[float]) -> tuple[float, float, float]:
    x, y, z = point
    return (
        matrix[0] * x + matrix[1] * y + matrix[2] * z + matrix[3],
        matrix[4] * x + matrix[5] * y + matrix[6] * z + matrix[7],
        matrix[8] * x + matrix[9] * y + matrix[10] * z + matrix[11],
    )


def _section_point(section: VxlSection, x: int, y: int, z: int) -> tuple[float, float, float]:
    min_x, min_y, min_z, max_x, max_y, max_z = section.bounds
    size_x, size_y, size_z = section.size
    return (
        min_x + (float(x) / max(1, size_x - 1)) * (max_x - min_x),
        min_y + (float(y) / max(1, size_y - 1)) * (max_y - min_y),
        min_z + (float(z) / max(1, size_z - 1)) * (max_z - min_z),
    )


def _shade(color: tuple[int, int, int, int], normal_index: int) -> tuple[int, int, int, int]:
    # Accurate Westwood lighting requires the theatre VPL and normal tables.
    # This deterministic fallback preserves color and supplies enough surface
    # contrast for logic-development placeholders.
    phase = (int(normal_index) * 37) & 0xFF
    brightness = 0.70 + 0.30 * (phase / 255.0)
    return (
        min(255, int(color[0] * brightness)),
        min(255, int(color[1] * brightness)),
        min(255, int(color[2] * brightness)),
        color[3],
    )


def render_voxel_parts(
    parts: Sequence[VoxelPart],
    facing_index: int,
    facing_count: int = 8,
    settings: RenderSettings = RenderSettings(),
) -> Image.Image:
    yaw = math.radians(settings.yaw_offset_degrees) + (math.tau * facing_index / max(1, facing_count))
    cosine = math.cos(yaw)
    sine = math.sin(yaw)
    projected: list[tuple[float, float, float, tuple[int, int, int, int]]] = []

    for part in parts:
        for section_index, section in enumerate(part.model.sections):
            hva_matrix = (
                part.animation.matrix(part.frame_index, section_index)
                if part.animation is not None
                else section.transform
            )
            for voxel in section.voxels:
                point = _section_point(section, voxel.x, voxel.y, voxel.z)
                world_x, world_y, world_z = _matrix_point(point, hva_matrix)
                world_x += part.offset[0]
                world_y += part.offset[1]
                world_z += part.offset[2]
                rotated_x = world_x * cosine - world_y * sine
                rotated_y = world_x * sine + world_y * cosine
                screen_x = (rotated_x - rotated_y) * settings.horizontal_scale
                screen_y = (rotated_x + rotated_y) * settings.vertical_scale - world_z * settings.height_scale
                depth = rotated_x + rotated_y + world_z * 0.20
                color = _shade(part.model.palette.rgba(voxel.color_index), voxel.normal_index)
                if color[3] > 0:
                    projected.append((depth, screen_x, screen_y, color))

    image = Image.new("RGBA", (settings.canvas_width, settings.canvas_height), (0, 0, 0, 0))
    if not projected:
        return image
    min_x = min(item[1] for item in projected)
    max_x = max(item[1] for item in projected)
    min_y = min(item[2] for item in projected)
    max_y = max(item[2] for item in projected)
    origin_x = settings.canvas_width * settings.anchor_x - (min_x + max_x) * 0.5
    origin_y = settings.canvas_height * settings.anchor_y - max_y
    draw = ImageDraw.Draw(image)
    pixel_size = max(1, int(settings.pixel_size))
    for _depth, screen_x, screen_y, color in sorted(projected, key=lambda item: item[0]):
        x = int(round(screen_x + origin_x))
        y = int(round(screen_y + origin_y))
        draw.rectangle((x, y, x + pixel_size - 1, y + pixel_size - 1), fill=color)
    return image


def pack_atlas(frames: Sequence[Image.Image], columns: int | None = None) -> tuple[Image.Image, int]:
    if not frames:
        raise ValueError("Cannot pack an empty frame list")
    width, height = frames[0].size
    if columns is None:
        columns = max(1, math.ceil(math.sqrt(len(frames))))
    rows = math.ceil(len(frames) / columns)
    atlas = Image.new("RGBA", (columns * width, rows * height), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        if frame.size != (width, height):
            raise ValueError("All atlas frames must share dimensions")
        atlas.alpha_composite(frame, ((index % columns) * width, (index // columns) * height))
    return atlas, columns

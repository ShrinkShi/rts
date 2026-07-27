from __future__ import annotations

from dataclasses import dataclass
import math
from typing import Sequence

from PIL import Image, ImageDraw

from .hva import HvaFile
from .vpl import VplFile
from .vxl import VxlFile, VxlSection


@dataclass(frozen=True)
class VoxelPart:
    model: VxlFile
    animation: HvaFile | None = None
    frame_index: int = 0
    offset: tuple[float, float, float] = (0.0, 0.0, 0.0)
    facing_index: int | None = None
    visible: bool = True


@dataclass(frozen=True)
class RenderSettings:
    canvas_width: int = 192
    canvas_height: int = 160
    pixel_size: int = 2
    horizontal_scale: float = 1.05
    vertical_scale: float = 0.52
    height_scale: float = 1.05
    anchor_x: float = 0.50
    anchor_y: float = 0.76
    yaw_offset_degrees: float = -45.0
    ambient_level: int = 20
    fit_width_ratio: float = 0.68
    fit_height_ratio: float = 0.58


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


def _light_level(normal_index: int, level_count: int, ambient_level: int) -> int:
    # The VXL stores an index into one of Westwood's normal tables. A full
    # normal-vector implementation is a later renderer stage; this deterministic
    # mapping still uses the authentic VPL ramps instead of multiplying RGB.
    # It preserves color ramps/remap behavior and avoids the old arbitrary hash.
    if level_count <= 1:
        return 0
    normalized = (int(normal_index) & 0xFF) / 255.0
    directional = int(round(normalized * (level_count - 1)))
    return max(0, min(level_count - 1, int(round((directional + ambient_level) * 0.5))))



def voxel_projection_bounds(
    parts: Sequence[VoxelPart],
    facing_index: int,
    facing_count: int = 8,
    settings: RenderSettings = RenderSettings(),
) -> tuple[float, float, float, float] | None:
    points: list[tuple[float, float]] = []
    for part in parts:
        part_facing = facing_index if part.facing_index is None else int(part.facing_index)
        yaw = math.radians(settings.yaw_offset_degrees) + (math.tau * part_facing / max(1, facing_count))
        cosine = math.cos(yaw)
        sine = math.sin(yaw)
        for section_index, section in enumerate(part.model.sections):
            if part.animation is not None:
                raw_matrix = part.animation.matrix(part.frame_index, section_index)
                mutable_matrix = list(raw_matrix)
                mutable_matrix[3] *= section.scale
                mutable_matrix[7] *= section.scale
                mutable_matrix[11] *= section.scale
                matrix = tuple(mutable_matrix)
            else:
                matrix = section.transform
            for voxel in section.voxels:
                point = _section_point(section, voxel.x, voxel.y, voxel.z)
                world_x, world_y, world_z = _matrix_point(point, matrix)
                world_x += part.offset[0]
                world_y += part.offset[1]
                world_z += part.offset[2]
                rotated_x = world_x * cosine - world_y * sine
                rotated_y = world_x * sine + world_y * cosine
                screen_x = (rotated_x - rotated_y) * settings.horizontal_scale
                screen_y = (rotated_x + rotated_y) * settings.vertical_scale - world_z * settings.height_scale
                points.append((screen_x, screen_y))
    if not points:
        return None
    return (
        min(point[0] for point in points),
        max(point[0] for point in points),
        min(point[1] for point in points),
        max(point[1] for point in points),
    )


def merge_projection_bounds(
    bounds: Sequence[tuple[float, float, float, float] | None],
) -> tuple[float, float, float, float] | None:
    present = [item for item in bounds if item is not None]
    if not present:
        return None
    return (
        min(item[0] for item in present),
        max(item[1] for item in present),
        min(item[2] for item in present),
        max(item[3] for item in present),
    )


def render_voxel_parts(
    parts: Sequence[VoxelPart],
    facing_index: int,
    facing_count: int = 8,
    settings: RenderSettings = RenderSettings(),
    vpl: VplFile | None = None,
    remap_mask: bool = False,
    fixed_bounds: tuple[float, float, float, float] | None = None,
) -> Image.Image:
    projected: list[tuple[float, float, float, tuple[int, int, int, int]]] = []

    for part in parts:
        part_facing = facing_index if part.facing_index is None else int(part.facing_index)
        yaw = math.radians(settings.yaw_offset_degrees) + (math.tau * part_facing / max(1, facing_count))
        cosine = math.cos(yaw)
        sine = math.sin(yaw)
        for section_index, section in enumerate(part.model.sections):
            if part.animation is not None:
                # HVA translations are stored in voxel-cell units.  The VXL footer's
                # per-section scale converts them to the world-space units used by
                # the section bounds.  Applying the raw values separates multi-part
                # models (notably the Gatling Tank and Siege Chopper) by 12x/18x.
                raw_matrix = part.animation.matrix(part.frame_index, section_index)
                mutable_matrix = list(raw_matrix)
                mutable_matrix[3] *= section.scale
                mutable_matrix[7] *= section.scale
                mutable_matrix[11] *= section.scale
                matrix = tuple(mutable_matrix)
            else:
                matrix = section.transform
            for voxel in section.voxels:
                point = _section_point(section, voxel.x, voxel.y, voxel.z)
                world_x, world_y, world_z = _matrix_point(point, matrix)
                world_x += part.offset[0]
                world_y += part.offset[1]
                world_z += part.offset[2]
                rotated_x = world_x * cosine - world_y * sine
                rotated_y = world_x * sine + world_y * cosine
                screen_x = (rotated_x - rotated_y) * settings.horizontal_scale
                screen_y = (rotated_x + rotated_y) * settings.vertical_scale - world_z * settings.height_scale
                depth = rotated_x + rotated_y + world_z * 0.25
                if not part.visible:
                    color = (0, 0, 0, 0)
                elif remap_mask:
                    if 16 <= int(voxel.color_index) <= 31:
                        shade = 72 + int(round((int(voxel.color_index) - 16) / 15.0 * 183.0))
                        color = (shade, shade, shade, 255)
                    else:
                        color = (0, 0, 0, 0)
                elif vpl is not None:
                    level = _light_level(voxel.normal_index, vpl.level_count, settings.ambient_level)
                    color = vpl.rgba(voxel.color_index, level)
                else:
                    color = part.model.palette.rgba(voxel.color_index)
                # Keep transparent non-remap voxels in the projected bounds.
                # Otherwise a remap-only pass is fitted and centered around just
                # the team-colored subset, so its mask no longer aligns with the
                # full vehicle render.
                projected.append((depth, screen_x, screen_y, color))

    image = Image.new("RGBA", (settings.canvas_width, settings.canvas_height), (0, 0, 0, 0))
    if not projected:
        return image
    if fixed_bounds is None:
        min_x = min(item[1] for item in projected)
        max_x = max(item[1] for item in projected)
        min_y = min(item[2] for item in projected)
        max_y = max(item[2] for item in projected)
    else:
        min_x, max_x, min_y, max_y = fixed_bounds
    span_x = max(1.0, max_x - min_x)
    span_y = max(1.0, max_y - min_y)
    fit_scale = min(
        (settings.canvas_width * settings.fit_width_ratio) / span_x,
        (settings.canvas_height * settings.fit_height_ratio) / span_y,
        8.0,
    )
    center_x = (min_x + max_x) * 0.5
    origin_x = settings.canvas_width * settings.anchor_x
    origin_y = settings.canvas_height * settings.anchor_y
    draw = ImageDraw.Draw(image)
    # Each VXL sample represents a volume cell, not a zero-area point.  The old
    # renderer always painted a fixed 2x2 square after projection; once the model
    # was fitted to the preview canvas the distance between adjacent projected
    # samples became larger than that square, producing the blue/black comb lines
    # seen on vehicles.  Scale the splat with the fitted voxel spacing and center
    # it on the projected point.  Depth sorting still provides the visible surface.
    pixel_size = max(3, int(settings.pixel_size), int(math.ceil(fit_scale * 1.35)))
    half_pixel = pixel_size // 2
    for _depth, screen_x, screen_y, color in sorted(projected, key=lambda item: item[0]):
        if color[3] <= 0:
            continue
        px = int(round((screen_x - center_x) * fit_scale + origin_x))
        py = int(round((screen_y - max_y) * fit_scale + origin_y))
        draw.rectangle(
            (px - half_pixel, py - half_pixel, px - half_pixel + pixel_size - 1, py - half_pixel + pixel_size - 1),
            fill=color,
        )
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

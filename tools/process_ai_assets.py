#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
from PIL import Image
import numpy as np
import shutil
import cv2

ROOT = Path(__file__).resolve().parents[1]
OUT_UNITS = ROOT / 'assets' / 'ai_generated' / 'units'
OUT_BUILDINGS = ROOT / 'assets' / 'ai_generated' / 'buildings'
SOURCE_OUT = ROOT / 'assets' / 'ai_generated' / 'source_sheets'
for p in (OUT_UNITS, OUT_BUILDINGS, SOURCE_OUT):
    p.mkdir(parents=True, exist_ok=True)

SOURCES = {
    'tank_chassis': SOURCE_OUT / 'tank_chassis.png',
    'tank_turret': SOURCE_OUT / 'tank_turret.png',
    'rifle': SOURCE_OUT / 'rifle.png',
    'tank_death': SOURCE_OUT / 'tank_death.png',
    'power': SOURCE_OUT / 'power.png',
    'barracks': SOURCE_OUT / 'barracks.png',
    'refinery': SOURCE_OUT / 'refinery.png',
    'turret_base': SOURCE_OUT / 'turret_base.png',
    'turret_head': SOURCE_OUT / 'turret_head.png',
    'bunker_base': SOURCE_OUT / 'bunker_base.png',
    'bunker_head': SOURCE_OUT / 'bunker_head.png',
}


def bounds(length: int, count: int) -> list[int]:
    return [round(i * length / count) for i in range(count + 1)]


def remove_gray_background(image: Image.Image) -> Image.Image:
    rgb = np.asarray(image.convert('RGB'))
    h, w = rgb.shape[:2]
    kernel = min(101, max(31, (min(h, w) // 2) | 1))
    if kernel >= min(h, w):
        kernel = max(3, (min(h, w) - 1) | 1)
    predicted = np.empty_like(rgb)
    for channel in range(3):
        predicted[:, :, channel] = cv2.medianBlur(rgb[:, :, channel], kernel)
    residual = np.sqrt(np.sum((rgb.astype(np.float32) - predicted.astype(np.float32)) ** 2, axis=2))
    alpha = np.clip((residual - 6.5) / 7.5 * 255.0, 0.0, 255.0).astype(np.uint8)
    alpha = cv2.medianBlur(alpha, 3)
    binary = (alpha > 22).astype(np.uint8) * 255
    count, labels, stats, centroids = cv2.connectedComponentsWithStats(binary, connectivity=8)
    if count > 1:
        largest = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
        largest_area = max(1, int(stats[largest, cv2.CC_STAT_AREA]))
        main_center = centroids[largest]
        cleaned = np.zeros_like(binary)
        for label in range(1, count):
            area = int(stats[label, cv2.CC_STAT_AREA])
            distance = float(np.linalg.norm(centroids[label] - main_center))
            if label == largest or (area >= max(4, int(largest_area * 0.004)) and distance < max(w, h) * 0.48):
                cleaned[labels == label] = 255
        alpha = np.where(cleaned > 0, alpha, 0).astype(np.uint8)
    alpha = cv2.GaussianBlur(alpha, (0, 0), 0.45)
    rgba = np.dstack((rgb, alpha))
    return Image.fromarray(rgba, 'RGBA')


def split_grid(source: Path, cols: int, rows: int, overlap: int = 0) -> list[Image.Image]:
    """Split an AI contact sheet while optionally retaining spill outside nominal cells.

    Generative sheets frequently let a long barrel or vehicle corner cross an
    invisible cell boundary. A small overlap recovers that content; the caller
    then removes detached neighbour fragments before normalisation.
    """
    image = Image.open(source).convert('RGB')
    xs, ys = bounds(image.width, cols), bounds(image.height, rows)
    result = []
    for row in range(rows):
        for col in range(cols):
            left = max(0, xs[col] - overlap)
            top = max(0, ys[row] - overlap)
            right = min(image.width, xs[col + 1] + overlap)
            bottom = min(image.height, ys[row + 1] + overlap)
            cell = image.crop((left, top, right, bottom))
            result.append(remove_gray_background(cell))
    return result



def clean_detached_fragments(image: Image.Image, keep_warm: bool = False) -> Image.Image:
    # AI sprite sheets sometimes leak a neighbour's barrel tip through a faint alpha bridge.
    # Build connectivity from a stronger alpha core, retain the main sprite, then restore only
    # a narrow antialiased fringe around that core. Firing frames may also keep warm muzzle flash.
    rgba = np.asarray(image.convert('RGBA')).copy()
    alpha = rgba[:, :, 3]
    core = (alpha > 64).astype(np.uint8) * 255
    count, labels, stats, _centroids = cv2.connectedComponentsWithStats(core, connectivity=8)
    if count <= 1:
        return image
    largest = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    keep_core = np.zeros_like(core)
    keep_core[labels == largest] = 255
    if keep_warm:
        for label in range(1, count):
            if label == largest:
                continue
            component = labels == label
            area = int(stats[label, cv2.CC_STAT_AREA])
            if area < 3:
                continue
            pixels = rgba[:, :, :3][component]
            if not len(pixels):
                continue
            mean = pixels.mean(axis=0)
            if mean[0] > 135 and mean[0] > mean[2] * 1.25 and mean[1] > 70:
                keep_core[component] = 255
    keep = cv2.dilate(keep_core, np.ones((5, 5), np.uint8), iterations=1)
    rgba[:, :, 3] = np.where(keep > 0, alpha, 0).astype(np.uint8)
    return Image.fromarray(rgba, 'RGBA')

def alpha_bbox(image: Image.Image):
    alpha = np.asarray(image.getchannel('A'))
    ys, xs = np.where(alpha > 18)
    if len(xs) == 0:
        return (0, 0, image.width, image.height)
    return (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)


def _alpha_points(image: Image.Image, threshold: int = 18):
    alpha = np.asarray(image.getchannel('A'))
    ys, xs = np.where(alpha > threshold)
    return xs, ys


def _bottom_anchor(image: Image.Image, inset_ratio: float = 0.0):
    box = alpha_bbox(image)
    left, top, right, bottom = box
    alpha = np.asarray(image.getchannel('A'))
    band_top = max(top, int(bottom - max(5, (bottom - top) * 0.24)))
    yy, xx = np.where((alpha > 48) & (np.indices(alpha.shape)[0] >= band_top))
    anchor_x = float(np.median(xx)) if len(xx) else (left + right) * 0.5
    anchor_y = float(bottom - max(0.0, (bottom - top) * inset_ratio))
    return anchor_x, anchor_y


def _turret_mount_anchor(image: Image.Image):
    # Ignore long barrels and muzzle flashes; the dense lower body identifies the mount.
    box = alpha_bbox(image)
    left, top, right, bottom = box
    alpha = np.asarray(image.getchannel('A'))
    y_grid = np.indices(alpha.shape)[0]
    band_top = int(top + (bottom - top) * 0.58)
    yy, xx = np.where((alpha > 64) & (y_grid >= band_top))
    anchor_x = float(np.median(xx)) if len(xx) else (left + right) * 0.5
    anchor_y = float(bottom - max(5.0, (bottom - top) * 0.16))
    return anchor_x, anchor_y


def _tank_ring_anchor(image: Image.Image):
    # Detect the dark elliptical turret ring. This is the chassis' true visual pivot.
    rgba = np.asarray(image.convert('RGBA'))
    rgb = rgba[:, :, :3]
    alpha = rgba[:, :, 3]
    box = alpha_bbox(image)
    left, top, right, bottom = box
    gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
    mask = ((gray < 52) & (alpha > 64)).astype(np.uint8) * 255
    region = np.zeros_like(mask)
    region[int(top + (bottom - top) * 0.02):int(top + (bottom - top) * 0.70),
           int(left + (right - left) * 0.10):int(left + (right - left) * 0.90)] = 255
    mask = cv2.bitwise_and(mask, region)
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))
    count, labels, stats, centroids = cv2.connectedComponentsWithStats(mask, connectivity=8)
    target_x = (left + right) * 0.5
    target_y = top + (bottom - top) * 0.30
    candidates = []
    for label in range(1, count):
        x, y, width, height, area = stats[label]
        aspect = width / max(1.0, float(height))
        if not (70 <= area <= 1900 and 14 <= width <= 85 and 8 <= height <= 48 and 1.10 <= aspect <= 3.8):
            continue
        cx, cy = centroids[label]
        score = (abs(cx - target_x) / max(1.0, right - left) * 1.2
                 + abs(cy - target_y) / max(1.0, bottom - top)
                 + abs(aspect - 1.85) * 0.08
                 - min(float(area), 750.0) / 750.0 * 0.16)
        candidates.append((score, float(cx), float(cy)))
    if candidates:
        candidates.sort(key=lambda item: item[0])
        return candidates[0][1], candidates[0][2]
    return (left + right) * 0.5, top + (bottom - top) * 0.30


def normalize_frames_anchored(
    frames: list[Image.Image],
    frame_size: tuple[int, int],
    anchor_fn,
    target_anchor: tuple[float, float],
    padding: int = 6,
) -> list[Image.Image]:
    boxes = [alpha_bbox(frame) for frame in frames]
    anchors = [anchor_fn(frame) for frame in frames]
    target_w, target_h = frame_size
    target_x, target_y = target_anchor

    scale_limits = []
    for box, anchor in zip(boxes, anchors):
        left, top, right, bottom = box
        ax, ay = anchor
        extents = [
            (ax - left, max(1.0, target_x - padding)),
            (right - ax, max(1.0, target_w - target_x - padding)),
            (ay - top, max(1.0, target_y - padding)),
            (bottom - ay, max(1.0, target_h - target_y - padding)),
        ]
        for source_extent, target_extent in extents:
            if source_extent > 0.5:
                scale_limits.append(target_extent / source_extent)
    scale = min(scale_limits) if scale_limits else 1.0

    output = []
    for frame, box, anchor in zip(frames, boxes, anchors):
        left, top, right, bottom = box
        crop = frame.crop(box)
        resized_w = max(1, round(crop.width * scale))
        resized_h = max(1, round(crop.height * scale))
        crop = crop.resize((resized_w, resized_h), Image.Resampling.LANCZOS)
        ax = (anchor[0] - left) * scale
        ay = (anchor[1] - top) * scale
        x = round(target_x - ax)
        y = round(target_y - ay)
        canvas = Image.new('RGBA', frame_size, (0, 0, 0, 0))
        canvas.alpha_composite(crop, (x, y))
        output.append(canvas)
    return output


def normalize_frames(frames: list[Image.Image], frame_size: tuple[int, int], padding: int = 6) -> list[Image.Image]:
    # Default assets use a stable ground contact point instead of the source cell center.
    return normalize_frames_anchored(
        frames, frame_size, lambda image: _bottom_anchor(image, 0.0),
        (frame_size[0] * 0.5, frame_size[1] - padding), padding
    )

def save_atlas(frames: list[Image.Image], cols: int, rows: int, frame_size: tuple[int, int], path: Path):
    assert len(frames) == cols * rows, (path, len(frames), cols, rows)
    atlas = Image.new('RGBA', (cols * frame_size[0], rows * frame_size[1]), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        atlas.alpha_composite(frame, ((index % cols) * frame_size[0], (index // cols) * frame_size[1]))
    atlas.save(path, optimize=True)


def reorder_rows(frames, cols, rows, column_map):
    out = []
    for row in range(rows):
        base = row * cols
        out.extend(frames[base + source_col] for source_col in column_map)
    return out


def mirror_frame(frame: Image.Image) -> Image.Image:
    return frame.transpose(Image.Transpose.FLIP_LEFT_RIGHT)


def rows_from_specs(frames, cols: int, rows: int, specs):
    """Build rows from source column specs. Negative specs encode mirrored columns as -(index+1)."""
    out = []
    for row in range(rows):
        base = row * cols
        for spec in specs:
            if spec >= 0:
                out.append(frames[base + spec])
            else:
                out.append(mirror_frame(frames[base + (-spec - 1)]))
    return out


def copy_sources():
    for key, source in SOURCES.items():
        if source.exists():
            shutil.copy2(source, SOURCE_OUT / f'{key}.png')


def main():
    # Runtime atlases use one explicit, human-readable column order:
    # N, NW, W, SW, S, SE, E, NE. The engine maps its mathematical
    # E, SE, S, SW, W, NW, N, NE direction indices to these columns.

    # The AI-generated chassis sheet does not contain eight reliable unique views.
    # Preserve its strongest five directions and synthesize the right-side views
    # by mirroring the corresponding left-side frames. This removes duplicate and
    # mislabeled directions while keeping the vehicle identity consistent.
    chassis_raw = split_grid(SOURCES['tank_chassis'], 8, 3, 26)
    # Source observations: S=0, SW=1, W=3, N=5. The source's two upper
    # diagonal presentations were visually assigned to the opposite side. Build
    # NW from the mirrored NE-like source and keep the original for NE.
    # Negative entries mean a horizontally mirrored source column.
    chassis = rows_from_specs(chassis_raw, 8, 3, [5, -5, 3, 1, 0, -2, -4, 4])
    chassis = [clean_detached_fragments(frame, False) for frame in chassis]
    chassis = normalize_frames_anchored(chassis, (224, 192), _tank_ring_anchor, (112, 96), 10)
    save_atlas(chassis, 8, 3, (224, 192), OUT_UNITS / 'tank_chassis.png')

    # Source 7 is a reliable NW view. Keep it for NW and synthesize NE by
    # horizontal mirroring so the independent turret follows the corrected hull.
    turret_raw = split_grid(SOURCES['tank_turret'], 8, 2, 52)
    turret = rows_from_specs(turret_raw, 8, 2, [0, 7, 6, 5, 4, 3, 2, -8])
    turret = [clean_detached_fragments(frame, index >= 8) for index, frame in enumerate(turret)]
    turret = normalize_frames_anchored(turret, (224, 192), _turret_mount_anchor, (112, 96), 10)
    save_atlas(turret, 8, 2, (224, 192), OUT_UNITS / 'tank_turret.png')

    # Rifle source is S,SW,W,NW,N,NE,E,SE. Reorder to north-first.
    rifle_raw = split_grid(SOURCES['rifle'], 8, 5)
    rifle = rows_from_specs(rifle_raw, 8, 5, [4, 3, 2, 1, 0, 7, 6, 5])
    rifle = normalize_frames_anchored(rifle, (128, 128), lambda image: _bottom_anchor(image, 0.0), (64, 123), 4)
    save_atlas(rifle, 8, 5, (128, 128), OUT_UNITS / 'rifle.png')

    tank_death_raw = split_grid(SOURCES['tank_death'], 8, 5)
    death_row = tank_death_raw[4 * 8:5 * 8]
    # The full-tank source follows the same S,SW,W,NW,N,NE,E,SE order.
    tank_death = [death_row[i] for i in [4, 3, 2, 1, 0, 7, 6, 5]]
    save_atlas(normalize_frames(tank_death, (224, 192), 10), 8, 1, (224, 192), OUT_UNITS / 'tank_death.png')

    for key, source, cols, rows in [
        ('power', SOURCES['power'], 3, 3),
        ('barracks', SOURCES['barracks'], 3, 3),
        ('refinery', SOURCES['refinery'], 4, 3),
        ('turret_base', SOURCES['turret_base'], 3, 3),
        ('bunker_base', SOURCES['bunker_base'], 3, 3),
    ]:
        frames = normalize_frames_anchored(
            split_grid(source, cols, rows), (256, 224),
            lambda image: _bottom_anchor(image, 0.12), (128, 184), 7
        )
        save_atlas(frames, cols, rows, (256, 224), OUT_BUILDINGS / f'{key}.png')

    # Autocannon head source is an irregular 5x4 presentation. Output north-first.
    raw_head = split_grid(SOURCES['turret_head'], 5, 4)
    idle_indices = [7, 5, 0, 1, 2, 3, 4, 9]   # N,NW,W,SW,S,SE,E,NE
    firing_indices = [11, 10, 10, 11, 12, 13, 13, 12]
    head_frames = [raw_head[i] for i in idle_indices + firing_indices]
    head_frames = [clean_detached_fragments(frame, index >= 8) for index, frame in enumerate(head_frames)]
    head_frames = normalize_frames_anchored(head_frames, (192, 160), _turret_mount_anchor, (96, 80), 5)
    save_atlas(head_frames, 8, 2, (192, 160), OUT_BUILDINGS / 'turret_head.png')

    # Machine-gun bunker top source first two rows are idle compass views and
    # last two rows are firing. Output north-first for the same runtime mapping.
    raw_bunker_head = split_grid(SOURCES['bunker_head'], 4, 4)
    north_first_source = [1, 0, 7, 6, 5, 4, 3, 2]
    bunker_idle = [raw_bunker_head[i] for i in north_first_source]
    bunker_fire = [raw_bunker_head[8 + i] for i in north_first_source]
    bunker_source_frames = [clean_detached_fragments(frame, index >= 8) for index, frame in enumerate(bunker_idle + bunker_fire)]
    bunker_frames = normalize_frames_anchored(bunker_source_frames, (160, 144), _turret_mount_anchor, (80, 72), 4)
    save_atlas(bunker_frames, 8, 2, (160, 144), OUT_BUILDINGS / 'bunker_head.png')

    print('AI-generated RTS assets processed into transparent, normalized north-first atlases.')


if __name__ == '__main__':
    main()

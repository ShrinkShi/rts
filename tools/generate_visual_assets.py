#!/usr/bin/env python3
"""Generate all placeholder 2.5D sprite sheets used by Iron Meridian RTS.

The project deliberately keeps the first art pass reproducible and free of third-party
assets. Run this script whenever the visual grammar changes.
"""
from __future__ import annotations

import math
import random
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
OUT_UNITS = ROOT / "assets" / "generated" / "units"
OUT_BUILDINGS = ROOT / "assets" / "generated" / "buildings"
OUT_UNITS.mkdir(parents=True, exist_ok=True)
OUT_BUILDINGS.mkdir(parents=True, exist_ok=True)

SCALE = 3
UNIT_FRAME = 96
UNIT_ROWS = {
    "idle": (0, 2),
    "move": (2, 4),
    "attack": (6, 3),
    "death": (9, 6),
}
DIRS = 8


def sc(v: float) -> int:
    return int(round(v * SCALE))


def pts(values: Iterable[tuple[float, float]]) -> list[tuple[int, int]]:
    return [(sc(x), sc(y)) for x, y in values]


def ellipse(draw: ImageDraw.ImageDraw, box, fill, outline=None, width=1):
    draw.ellipse(tuple(sc(v) for v in box), fill=fill, outline=outline, width=sc(width))


def rect(draw: ImageDraw.ImageDraw, box, fill, outline=None, width=1, radius=0):
    b = tuple(sc(v) for v in box)
    if radius:
        draw.rounded_rectangle(b, radius=sc(radius), fill=fill, outline=outline, width=sc(width))
    else:
        draw.rectangle(b, fill=fill, outline=outline, width=sc(width))


def line(draw: ImageDraw.ImageDraw, xy, fill, width=1):
    draw.line(pts(xy), fill=fill, width=sc(width), joint="curve")


def polygon(draw: ImageDraw.ImageDraw, values, fill, outline=None):
    p = pts(values)
    draw.polygon(p, fill=fill)
    if outline:
        draw.line(p + [p[0]], fill=outline, width=sc(1), joint="curve")


def unit_direction(index: int) -> tuple[float, float]:
    # Screen-space direction: east, south-east, south, south-west, west, north-west, north, north-east.
    angle = index * math.tau / DIRS
    return math.cos(angle), math.sin(angle)


def shade(color: tuple[int, int, int, int], factor: float) -> tuple[int, int, int, int]:
    return tuple(max(0, min(255, int(c * factor))) for c in color[:3]) + (color[3],)


STEEL = (182, 198, 204, 255)
DARK = (40, 48, 54, 255)
MID = (105, 121, 128, 255)
LIGHT = (226, 237, 240, 255)
SKIN = (220, 184, 133, 255)
YELLOW = (211, 175, 63, 255)
BLACK = (18, 22, 24, 255)


def base_frame() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("RGBA", (UNIT_FRAME * SCALE, UNIT_FRAME * SCALE), (0, 0, 0, 0))
    return image, ImageDraw.Draw(image, "RGBA")


def draw_shadow(draw, strength=105, size=(42, 16), center=(48, 72)):
    ellipse(draw, (center[0] - size[0] / 2, center[1] - size[1] / 2,
                   center[0] + size[0] / 2, center[1] + size[1] / 2), (0, 0, 0, strength))


def draw_infantry(unit_id: str, direction: int, state: str, frame: int) -> Image.Image:
    image, draw = base_frame()
    dx, dy = unit_direction(direction)
    perp = (-dy, dx)
    cx, cy = 48.0, 60.0
    bob = 0.0
    stride = 0.0
    recoil = 0.0
    if state == "idle":
        bob = -0.7 if frame % 2 else 0.0
    elif state == "move":
        phase = frame * math.pi / 2
        bob = -abs(math.sin(phase)) * 1.5
        stride = math.sin(phase) * 5.0
    elif state == "attack":
        recoil = [0.0, -3.2, -1.0][frame]
        bob = -1.2 if frame == 1 else 0.0
    elif state == "death":
        progress = frame / 5.0
        draw_shadow(draw, 75 + int(25 * progress), (38 + 14 * progress, 14), (48, 74))
        body_x = cx + dx * (8 * progress)
        body_y = cy + 10 * progress
        angle = math.atan2(dy, dx) + math.pi * 0.5 * progress
        ax, ay = math.cos(angle), math.sin(angle)
        px, py = -ay, ax
        polygon(draw, [
            (body_x - ax * 13 - px * 5, body_y - ay * 13 - py * 5),
            (body_x + ax * 12 - px * 5, body_y + ay * 12 - py * 5),
            (body_x + ax * 12 + px * 5, body_y + ay * 12 + py * 5),
            (body_x - ax * 13 + px * 5, body_y - ay * 13 + py * 5),
        ], shade(STEEL, 0.7 - 0.15 * progress), BLACK)
        ellipse(draw, (body_x + ax * 11 - 5, body_y + ay * 11 - 5,
                       body_x + ax * 11 + 5, body_y + ay * 11 + 5), shade(SKIN, 0.8))
        if frame < 3:
            line(draw, [(body_x, body_y), (body_x + dx * 20, body_y + dy * 20)], DARK, 3)
        return image.resize((UNIT_FRAME, UNIT_FRAME), Image.Resampling.LANCZOS)

    draw_shadow(draw, 105, (34, 13), (48, 75))
    cy += bob
    # Legs use screen-space perpendicular offsets so all 8 directions read correctly.
    hip = (cx - dx * 2, cy + 6)
    leg_a_end = (hip[0] - dx * 11 + perp[0] * stride * 0.45, hip[1] - dy * 7 + 12 + perp[1] * stride * 0.2)
    leg_b_end = (hip[0] - dx * 11 - perp[0] * stride * 0.45, hip[1] - dy * 7 + 12 - perp[1] * stride * 0.2)
    line(draw, [hip, leg_a_end], shade(STEEL, 0.52), 4)
    line(draw, [hip, leg_b_end], shade(STEEL, 0.68), 4)

    torso_center = (cx, cy - 4)
    polygon(draw, [
        (torso_center[0] - perp[0] * 7 - dx * 8, torso_center[1] - perp[1] * 7 - dy * 5),
        (torso_center[0] + perp[0] * 7 - dx * 8, torso_center[1] + perp[1] * 7 - dy * 5),
        (torso_center[0] + perp[0] * 6 + dx * 8, torso_center[1] + perp[1] * 6 + dy * 5),
        (torso_center[0] - perp[0] * 6 + dx * 8, torso_center[1] - perp[1] * 6 + dy * 5),
    ], STEEL, DARK)
    # Chest highlight and backpack create a stronger pseudo-3D read.
    line(draw, [(torso_center[0] - perp[0] * 4, torso_center[1] - perp[1] * 4),
                (torso_center[0] + dx * 5 - perp[0] * 4, torso_center[1] + dy * 3 - perp[1] * 4)], LIGHT, 2)
    ellipse(draw, (cx + dx * 7 - 5, cy - 22 + dy * 3 - 5,
                   cx + dx * 7 + 5, cy - 22 + dy * 3 + 5), SKIN, DARK, 1)
    # Helmet.
    ellipse(draw, (cx + dx * 7 - 5.5, cy - 24.5 + dy * 3 - 3,
                   cx + dx * 7 + 5.5, cy - 24.5 + dy * 3 + 3), shade(STEEL, 0.75), DARK, 1)

    weapon_start = (cx + dx * 2 + perp[0] * 2, cy - 7 + dy * 2 + perp[1] * 2)
    weapon_len = 27 if unit_id == "rifle" else 24
    weapon_end = (weapon_start[0] + dx * (weapon_len + recoil), weapon_start[1] + dy * (weapon_len + recoil))
    line(draw, [weapon_start, weapon_end], BLACK, 3 if unit_id == "rifle" else 5)
    if unit_id == "rocket":
        line(draw, [(weapon_start[0] - perp[0] * 3, weapon_start[1] - perp[1] * 3),
                    (weapon_end[0] - perp[0] * 3, weapon_end[1] - perp[1] * 3)], MID, 3)
    if state == "attack" and frame == 1:
        flash = (weapon_end[0] + dx * 4, weapon_end[1] + dy * 4)
        polygon(draw, [
            (flash[0] + dx * 8, flash[1] + dy * 8),
            (flash[0] + perp[0] * 4, flash[1] + perp[1] * 4),
            (flash[0] - perp[0] * 4, flash[1] - perp[1] * 4),
        ], (255, 219, 92, 235))
    return image.resize((UNIT_FRAME, UNIT_FRAME), Image.Resampling.LANCZOS)


def vehicle_polygon(cx, cy, dx, dy, length, width, vertical_lift=0.0):
    px, py = -dy, dx
    return [
        (cx + dx * length * 0.55 + px * width * 0.5, cy + dy * length * 0.34 + py * width * 0.28 - vertical_lift),
        (cx + dx * length * 0.55 - px * width * 0.5, cy + dy * length * 0.34 - py * width * 0.28 - vertical_lift),
        (cx - dx * length * 0.55 - px * width * 0.5, cy - dy * length * 0.34 - py * width * 0.28),
        (cx - dx * length * 0.55 + px * width * 0.5, cy - dy * length * 0.34 + py * width * 0.28),
    ]


def draw_vehicle(unit_id: str, direction: int, state: str, frame: int) -> Image.Image:
    image, draw = base_frame()
    dx, dy = unit_direction(direction)
    px, py = -dy, dx
    cx, cy = 48.0, 61.0
    recoil = 0.0
    track_phase = 0
    if state == "move":
        track_phase = frame
        cy += [0, -1, 0, 1][frame]
    elif state == "attack":
        recoil = [0, -4, -1][frame]
    elif state == "death":
        progress = frame / 5.0
        draw_shadow(draw, 115, (54, 18), (48, 74))
        if frame <= 3:
            radius = 8 + frame * 8
            ellipse(draw, (48 - radius, 53 - radius, 48 + radius, 53 + radius), (255, 117 + frame * 20, 24, max(60, 235 - frame * 40)))
            ellipse(draw, (48 - radius * 0.55, 53 - radius * 0.55, 48 + radius * 0.55, 53 + radius * 0.55), (255, 229, 126, 230))
        hull = vehicle_polygon(cx, cy + 4 * progress, dx, dy, 45, 29, 4)
        polygon(draw, hull, shade(MID, 0.52 - 0.12 * progress), BLACK)
        for i in range(3):
            ox = (i - 1) * 10 + (frame * 2 if i % 2 else -frame * 2)
            oy = -8 - frame * 3 + i * 3
            rect(draw, (cx + ox - 3, cy + oy - 2, cx + ox + 3, cy + oy + 2), shade(DARK, 0.8), BLACK, 1)
        return image.resize((UNIT_FRAME, UNIT_FRAME), Image.Resampling.LANCZOS)

    draw_shadow(draw, 120, (54 if unit_id != "scout" else 48, 18), (48, 75))
    length = 46 if unit_id in ["tank", "harvester"] else 40
    width = 30 if unit_id in ["tank", "harvester"] else 25
    hull = vehicle_polygon(cx, cy, dx, dy, length, width, 5)
    # Tracks / wheels.
    left_track = [(x + px * 5, y + py * 3 + 3) for x, y in hull]
    right_track = [(x - px * 5, y - py * 3 + 3) for x, y in hull]
    polygon(draw, left_track, DARK, BLACK)
    polygon(draw, right_track, DARK, BLACK)
    polygon(draw, hull, STEEL if unit_id != "harvester" else shade(YELLOW, 0.88), DARK)
    # Top face makes the body read as a voxel-like block.
    top = vehicle_polygon(cx + dx * 1, cy - 4, dx, dy, length * 0.72, width * 0.68, 7)
    polygon(draw, top, LIGHT if unit_id != "harvester" else YELLOW, DARK)
    line(draw, [(cx - px * width * 0.28, cy - py * width * 0.17 - 7),
                (cx + px * width * 0.28, cy + py * width * 0.17 - 7)], (255, 255, 255, 110), 2)

    if unit_id == "tank":
        turret_cx = cx + dx * (1 + recoil)
        turret_cy = cy - 12 + dy * (1 + recoil)
        ellipse(draw, (turret_cx - 10, turret_cy - 8, turret_cx + 10, turret_cy + 8), MID, DARK, 1)
        barrel_start = (turret_cx + dx * 4, turret_cy + dy * 2)
        barrel_end = (barrel_start[0] + dx * (31 + recoil), barrel_start[1] + dy * (31 + recoil))
        line(draw, [barrel_start, barrel_end], DARK, 5)
        if state == "attack" and frame == 1:
            flash = (barrel_end[0] + dx * 4, barrel_end[1] + dy * 4)
            polygon(draw, [(flash[0] + dx * 10, flash[1] + dy * 10),
                           (flash[0] + px * 6, flash[1] + py * 6),
                           (flash[0] - px * 6, flash[1] - py * 6)], (255, 192, 55, 245))
    elif unit_id == "scout":
        ellipse(draw, (cx - 7, cy - 12, cx + 7, cy + 2), MID, DARK, 1)
        barrel_end = (cx + dx * 22, cy - 6 + dy * 22)
        line(draw, [(cx, cy - 6), barrel_end], DARK, 3)
        if state == "attack" and frame == 1:
            ellipse(draw, (barrel_end[0] - 3, barrel_end[1] - 3, barrel_end[0] + 3, barrel_end[1] + 3), (255, 220, 91, 240))
    elif unit_id == "harvester":
        # Ore hopper and cutting head.
        rect(draw, (cx - 12, cy - 19, cx + 11, cy - 4), shade(YELLOW, 1.05), DARK, 1, 3)
        head = (cx + dx * 29, cy + dy * 22 + 3)
        line(draw, [(cx + dx * 15, cy + dy * 10), head], DARK, 7)
        ellipse(draw, (head[0] - 7, head[1] - 4, head[0] + 7, head[1] + 4), MID, DARK, 1)
    # Track highlights animate during movement.
    if state == "move":
        for i in range(3):
            phase = (i * 9 + track_phase * 4) % 27 - 13
            tx = cx - dx * phase + px * width * 0.43
            ty = cy - dy * phase + py * width * 0.24 + 3
            ellipse(draw, (tx - 2, ty - 2, tx + 2, ty + 2), (205, 217, 220, 150))
    return image.resize((UNIT_FRAME, UNIT_FRAME), Image.Resampling.LANCZOS)


def make_unit_sheet(unit_id: str):
    total_rows = 15
    sheet = Image.new("RGBA", (UNIT_FRAME * DIRS, UNIT_FRAME * total_rows), (0, 0, 0, 0))
    for state, (row_start, count) in UNIT_ROWS.items():
        for frame in range(count):
            for direction in range(DIRS):
                if unit_id in ["rifle", "rocket"]:
                    cell = draw_infantry(unit_id, direction, state, frame)
                else:
                    cell = draw_vehicle(unit_id, direction, state, frame)
                sheet.alpha_composite(cell, (direction * UNIT_FRAME, (row_start + frame) * UNIT_FRAME))
    sheet.save(OUT_UNITS / f"{unit_id}.png", optimize=True)


BUILD_FRAME_W = 192
BUILD_FRAME_H = 160


def building_base(draw, cx, base_y, width, depth, damage):
    # Isometric plinth.
    top = [(cx, base_y - depth), (cx + width / 2, base_y - depth / 2), (cx, base_y), (cx - width / 2, base_y - depth / 2)]
    polygon(draw, top, shade(STEEL, 0.65 - damage * 0.06), DARK)
    polygon(draw, [(cx - width / 2, base_y - depth / 2), (cx, base_y), (cx, base_y + 10), (cx - width / 2, base_y - depth / 2 + 10)], shade(MID, 0.65), DARK)
    polygon(draw, [(cx + width / 2, base_y - depth / 2), (cx, base_y), (cx, base_y + 10), (cx + width / 2, base_y - depth / 2 + 10)], shade(MID, 0.48), DARK)


def iso_box(draw, cx, cy, width, depth, height, top_color, left_color, right_color):
    top = [(cx, cy - height - depth / 2), (cx + width / 2, cy - height), (cx, cy - height + depth / 2), (cx - width / 2, cy - height)]
    left = [(cx - width / 2, cy - height), (cx, cy - height + depth / 2), (cx, cy + depth / 2), (cx - width / 2, cy)]
    right = [(cx + width / 2, cy - height), (cx, cy - height + depth / 2), (cx, cy + depth / 2), (cx + width / 2, cy)]
    polygon(draw, left, left_color, DARK)
    polygon(draw, right, right_color, DARK)
    polygon(draw, top, top_color, DARK)


def draw_building(building_id: str, damage: int) -> Image.Image:
    W, H = BUILD_FRAME_W, BUILD_FRAME_H
    image = Image.new("RGBA", (W * SCALE, H * SCALE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image, "RGBA")
    ellipse(draw, (34, 119, 158, 148), (0, 0, 0, 105))
    cx, base_y = 96, 125
    building_base(draw, cx, base_y, 122, 52, damage)
    top = shade(LIGHT, 1.0 - damage * 0.12)
    left = shade(STEEL, 0.72 - damage * 0.08)
    right = shade(STEEL, 0.56 - damage * 0.08)

    if building_id == "command":
        iso_box(draw, cx, 112, 82, 38, 58, top, left, right)
        iso_box(draw, cx - 28, 116, 28, 22, 29, shade(top, 0.95), shade(left, 0.9), shade(right, 0.9))
        ellipse(draw, (82, 45, 110, 64), shade(MID, 1.05), DARK, 1)
        line(draw, [(96, 53), (126, 24)], DARK, 4)
        ellipse(draw, (122, 18, 133, 29), (160, 207, 222, 255), DARK, 1)
    elif building_id == "power":
        iso_box(draw, cx, 117, 70, 34, 37, top, left, right)
        for offset in (-22, 20):
            rect(draw, (cx + offset - 8, 49, cx + offset + 8, 105), shade(MID, 0.9), DARK, 1, 3)
            ellipse(draw, (cx + offset - 10, 42, cx + offset + 10, 57), (184, 220, 232, 255), DARK, 1)
        polygon(draw, [(88, 86), (102, 86), (95, 102), (106, 102), (88, 120), (93, 105), (84, 105)], (240, 206, 76, 255))
    elif building_id == "barracks":
        iso_box(draw, cx, 119, 94, 42, 43, top, left, right)
        rect(draw, (85, 88, 107, 126), DARK, BLACK, 1)
        rect(draw, (45, 83, 69, 101), shade(MID, 1.1), DARK, 1, 2)
        line(draw, [(55, 79), (132, 54)], (171, 203, 214, 255), 3)
    elif building_id == "refinery":
        iso_box(draw, cx + 17, 121, 75, 36, 43, top, left, right)
        ellipse(draw, (38, 69, 90, 118), shade(YELLOW, 0.94), DARK, 1)
        ellipse(draw, (45, 75, 83, 111), shade(YELLOW, 1.08), DARK, 1)
        line(draw, [(64, 73), (80, 45), (121, 40)], DARK, 6)
        rect(draw, (117, 30, 132, 83), shade(MID, 0.82), DARK, 1, 2)
    elif building_id == "war_factory":
        iso_box(draw, cx, 122, 116, 46, 49, top, left, right)
        polygon(draw, [(62, 88), (96, 104), (96, 137), (62, 120)], BLACK, DARK)
        polygon(draw, [(130, 88), (96, 104), (96, 137), (130, 120)], shade(DARK, 0.8), DARK)
        line(draw, [(55, 65), (137, 65)], (175, 208, 218, 255), 4)
        rect(draw, (128, 43, 143, 86), shade(MID, 0.85), DARK, 1, 2)
    elif building_id == "turret":
        iso_box(draw, cx, 124, 60, 34, 31, top, left, right)
        ellipse(draw, (73, 64, 119, 101), shade(MID, 0.85), DARK, 1)
        line(draw, [(96, 80), (150, 55)], DARK, 8)
        rect(draw, (141, 50, 160, 59), shade(MID, 0.68), DARK, 1, 2)
    elif building_id == "repair_bay":
        iso_box(draw, cx, 121, 112, 44, 42, top, left, right)
        polygon(draw, [(55, 92), (96, 111), (96, 137), (55, 118)], shade(DARK, 0.72), DARK)
        polygon(draw, [(137, 92), (96, 111), (96, 137), (137, 118)], shade(DARK, 0.58), DARK)
        rect(draw, (128, 46, 143, 88), shade(MID, 0.85), DARK, 1, 2)
        line(draw, [(76, 60), (118, 102)], (226, 214, 112, 255), 7)
        draw.arc((94, 38, 128, 72), 205, 520, fill=(226, 214, 112, 255), width=6 * SCALE)

    if damage >= 1:
        # Chipped surfaces and smoke soot.
        line(draw, [(58, 92), (72, 83), (78, 96), (91, 86)], (55, 45, 42, 230), 3)
        line(draw, [(111, 70), (118, 80), (109, 90)], (55, 45, 42, 220), 3)
        ellipse(draw, (122, 35, 151, 66), (32, 36, 38, 70 + damage * 35))
    if damage >= 2:
        line(draw, [(73, 56), (86, 72), (78, 90), (97, 101)], (30, 25, 24, 250), 4)
        rect(draw, (120, 84, 145, 107), (31, 29, 28, 215), DARK, 1, 2)
        for index in range(5):
            ox = 118 + index * 6
            oy = 34 - index * 5
            ellipse(draw, (ox - 8, oy - 7, ox + 8, oy + 7), (42, 46, 48, 95 - index * 10))

    return image.resize((W, H), Image.Resampling.LANCZOS)


def make_building_sheet(building_id: str):
    sheet = Image.new("RGBA", (BUILD_FRAME_W * 3, BUILD_FRAME_H), (0, 0, 0, 0))
    for damage in range(3):
        frame = draw_building(building_id, damage)
        sheet.alpha_composite(frame, (damage * BUILD_FRAME_W, 0))
    sheet.save(OUT_BUILDINGS / f"{building_id}.png", optimize=True)


def main():
    for unit_id in ["rifle", "rocket", "tank", "scout", "harvester"]:
        make_unit_sheet(unit_id)
    for building_id in ["command", "power", "barracks", "refinery", "war_factory", "turret", "repair_bay"]:
        make_building_sheet(building_id)
    print(f"Generated unit sheets in {OUT_UNITS}")
    print(f"Generated building sheets in {OUT_BUILDINGS}")


if __name__ == "__main__":
    main()

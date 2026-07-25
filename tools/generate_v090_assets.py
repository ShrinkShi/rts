#!/usr/bin/env python3
"""Generate the v0.9.0 original industrial assets.

The silhouettes are informed by classic 2.5D base-building RTS readability, but all
geometry, colors and details are drawn from scratch. Generated output is deterministic.
"""
from __future__ import annotations

import math
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
UNIT_OUT = ROOT / "assets/generated/units"
BUILDING_OUT = ROOT / "assets/generated/buildings"
PREVIEW_OUT = ROOT / "docs/V090_ASSET_PREVIEW.png"
UNIT_OUT.mkdir(parents=True, exist_ok=True)
BUILDING_OUT.mkdir(parents=True, exist_ok=True)

S = 4
UNIT = 96
BW, BH = 192, 160
DIRS = 8

INK = (24, 30, 34, 255)
DEEP = (39, 50, 58, 255)
STEEL = (121, 139, 148, 255)
LIGHT = (197, 211, 216, 255)
PANEL = (78, 100, 112, 255)
BLUE = (42, 103, 170, 255)
BLUE_LIGHT = (79, 152, 219, 255)
YELLOW = (229, 186, 55, 255)
YELLOW_LIGHT = (255, 224, 105, 255)
RUST = (129, 71, 43, 255)
BLACK = (10, 13, 15, 255)
SMOKE = (41, 45, 47, 180)


def sc(v: float) -> int:
    return int(round(v * S))


def points(values: Iterable[tuple[float, float]]):
    return [(sc(x), sc(y)) for x, y in values]


def poly(draw, values, fill, outline=INK, width=1):
    p = points(values)
    draw.polygon(p, fill=fill)
    if outline:
        draw.line(p + [p[0]], fill=outline, width=sc(width), joint="curve")


def line(draw, values, fill, width=1):
    draw.line(points(values), fill=fill, width=sc(width), joint="curve")


def ellipse(draw, box, fill, outline=None, width=1):
    draw.ellipse(tuple(sc(v) for v in box), fill=fill, outline=outline, width=sc(width))


def rect(draw, box, fill, outline=None, width=1, radius=0):
    b = tuple(sc(v) for v in box)
    if radius:
        draw.rounded_rectangle(b, radius=sc(radius), fill=fill, outline=outline, width=sc(width))
    else:
        draw.rectangle(b, fill=fill, outline=outline, width=sc(width))


def shade(c, factor):
    return tuple(max(0, min(255, int(v * factor))) for v in c[:3]) + (c[3],)


def iso_platform(draw, cx, cy, width, depth, thickness=8, top=(76, 92, 98, 255)):
    top_poly = [(cx, cy - depth / 2), (cx + width / 2, cy), (cx, cy + depth / 2), (cx - width / 2, cy)]
    left = [(cx - width / 2, cy), (cx, cy + depth / 2), (cx, cy + depth / 2 + thickness), (cx - width / 2, cy + thickness)]
    right = [(cx + width / 2, cy), (cx, cy + depth / 2), (cx, cy + depth / 2 + thickness), (cx + width / 2, cy + thickness)]
    poly(draw, left, shade(top, .62))
    poly(draw, right, shade(top, .48))
    poly(draw, top_poly, top)


def iso_box(draw, cx, base_y, width, depth, height, top=LIGHT, left=STEEL, right=PANEL):
    top_poly = [(cx, base_y - height - depth / 2), (cx + width / 2, base_y - height), (cx, base_y - height + depth / 2), (cx - width / 2, base_y - height)]
    left_poly = [(cx - width / 2, base_y - height), (cx, base_y - height + depth / 2), (cx, base_y + depth / 2), (cx - width / 2, base_y)]
    right_poly = [(cx + width / 2, base_y - height), (cx, base_y - height + depth / 2), (cx, base_y + depth / 2), (cx + width / 2, base_y)]
    poly(draw, left_poly, left)
    poly(draw, right_poly, right)
    poly(draw, top_poly, top)


def draw_cracks(draw, severity):
    if severity <= 0:
        return
    line(draw, [(61, 91), (69, 84), (75, 95), (84, 88)], (48, 37, 33, 240), 2)
    line(draw, [(119, 64), (112, 74), (121, 82), (114, 92)], (48, 37, 33, 240), 2)
    if severity >= 2:
        line(draw, [(84, 55), (93, 69), (87, 84), (101, 95)], BLACK, 3)
        rect(draw, (126, 88, 151, 111), (38, 34, 32, 230), INK, 1, 2)
        for i in range(5):
            ellipse(draw, (124 + i * 6, 39 - i * 5, 143 + i * 7, 53 + i * 4), (42, 46, 48, 100 - i * 12))


def command_frame(stage: int) -> Image.Image:
    im = Image.new("RGBA", (BW * S, BH * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im, "RGBA")
    ellipse(d, (29, 119, 162, 150), (0, 0, 0, 105))
    iso_platform(d, 96, 119, 138, 62, 8, shade(PANEL, .72))
    # Circular deployment pad and segmented hazard ring.
    ellipse(d, (54, 82, 139, 136), shade(DEEP, .75), INK, 2)
    ellipse(d, (62, 88, 131, 130), (30, 35, 38, 255), INK, 1)
    for a in range(0, 360, 30):
        r1, r2 = 38, 44
        x1, y1 = 96 + math.cos(math.radians(a)) * r1, 109 + math.sin(math.radians(a)) * r1 * .62
        x2, y2 = 96 + math.cos(math.radians(a)) * r2, 109 + math.sin(math.radians(a)) * r2 * .62
        line(d, [(x1, y1), (x2, y2)], YELLOW if (a // 30) % 2 == 0 else INK, 3)
    # Curved armored command spine.
    poly(d, [(40, 105), (50, 67), (74, 48), (111, 49), (130, 66), (122, 79), (104, 64), (74, 63), (60, 78), (55, 108)], shade(STEEL, .88), INK)
    poly(d, [(50, 67), (61, 54), (78, 45), (114, 47), (126, 57), (119, 66), (103, 57), (76, 56), (60, 72)], LIGHT, INK)
    # Team panels and utility nodes.
    poly(d, [(43, 93), (53, 78), (60, 81), (55, 101)], BLUE, INK)
    rect(d, (70, 45, 105, 53), shade(YELLOW, .86), INK, 1, 2)
    ellipse(d, (104, 48, 122, 64), shade(RUST, 1.05), INK, 1)
    # Crane arm and service head.
    line(d, [(113, 67), (141, 48), (162, 55)], INK, 6)
    line(d, [(113, 64), (141, 45), (161, 52)], STEEL, 3)
    rect(d, (157, 48, 173, 59), DEEP, INK, 1, 2)
    ellipse(d, (135, 71, 150, 84), BLUE_LIGHT, INK, 1)
    # Grille on pad.
    for i in range(7):
        line(d, [(72 + i * 7, 92), (62 + i * 8, 124)], (74, 83, 87, 190), 1)
    for i in range(5):
        line(d, [(66, 96 + i * 6), (128, 96 + i * 6)], (74, 83, 87, 190), 1)
    # Damage transformations.
    if stage >= 1:
        draw_cracks(d, stage)
        rect(d, (87, 48, 100, 58), (42, 38, 36, 230), INK, 1)
    if stage >= 2:
        line(d, [(119, 66), (142, 46)], RUST, 5)
        ellipse(d, (116, 42, 151, 70), (31, 34, 35, 130))
    if stage == 3:
        # Flattened wreck footprint.
        im = Image.new("RGBA", (BW * S, BH * S), (0, 0, 0, 0))
        d = ImageDraw.Draw(im, "RGBA")
        ellipse(d, (28, 119, 165, 151), (0, 0, 0, 120))
        iso_platform(d, 96, 122, 138, 62, 5, shade(DEEP, .7))
        ellipse(d, (56, 91, 137, 139), (25, 28, 29, 255), INK, 2)
        poly(d, [(47, 108), (66, 76), (94, 84), (111, 112), (87, 130), (58, 126)], shade(STEEL, .42), INK)
        line(d, [(99, 91), (148, 64)], shade(STEEL, .45), 7)
        for x, y in [(66, 102), (85, 81), (120, 112), (142, 78), (101, 126)]:
            rect(d, (x - 5, y - 3, x + 5, y + 3), shade(RUST, .72), INK, 1)
        for i in range(6):
            ellipse(d, (103 + i * 5, 55 - i * 4, 129 + i * 8, 75 + i * 5), (42, 45, 46, 120 - i * 14))
    return im.resize((BW, BH), Image.Resampling.LANCZOS)


def war_factory_frame(stage: int) -> Image.Image:
    im = Image.new("RGBA", (BW * S, BH * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im, "RGBA")
    ellipse(d, (24, 116, 174, 151), (0, 0, 0, 110))
    iso_platform(d, 96, 120, 150, 66, 8, shade(PANEL, .70))
    # Long barrel-vault hangar.
    iso_box(d, 101, 118, 106, 46, 47, LIGHT, shade(STEEL, .83), shade(PANEL, .88))
    # Roof ribs and blue spine.
    for i in range(7):
        x = 64 + i * 13
        line(d, [(x, 69 - abs(i - 3) * 1.5), (x + 20, 79 + abs(i - 3) * 1.5)], shade(STEEL, .72), 2)
    poly(d, [(57, 72), (96, 55), (145, 70), (137, 78), (96, 64), (64, 79)], (188, 198, 218, 255), INK)
    line(d, [(67, 71), (136, 72)], BLUE_LIGHT, 4)
    # Front armored portal and ramp.
    poly(d, [(47, 91), (72, 80), (92, 91), (92, 127), (47, 116)], DEEP, INK)
    poly(d, [(145, 85), (168, 96), (168, 120), (145, 132), (124, 121), (124, 96)], shade(DEEP, .82), INK)
    poly(d, [(126, 105), (154, 119), (133, 141), (96, 128)], shade(STEEL, .68), INK)
    for i in range(5):
        line(d, [(112 + i * 6, 111 + i * 2), (105 + i * 7, 131 + i * 2)], (49, 58, 62, 220), 1)
    # Chimney, vats and team signage.
    rect(d, (42, 50, 55, 91), PANEL, INK, 1, 3)
    ellipse(d, (39, 45, 58, 57), BLUE_LIGHT, INK, 1)
    ellipse(d, (29, 86, 51, 105), STEEL, INK, 1)
    ellipse(d, (31, 80, 49, 93), LIGHT, INK, 1)
    rect(d, (78, 68, 119, 75), BLUE, INK, 1, 2)
    # Flag mast.
    line(d, [(57, 57), (57, 28)], INK, 2)
    poly(d, [(58, 30), (75, 35), (58, 42)], BLUE, INK)
    if stage >= 1:
        draw_cracks(d, stage)
        rect(d, (88, 60, 105, 74), (45, 40, 37, 230), INK, 1)
    if stage >= 2:
        poly(d, [(117, 69), (145, 73), (138, 91), (110, 84)], shade(RUST, .72), INK)
        ellipse(d, (111, 35, 151, 74), (37, 40, 41, 145))
    if stage == 3:
        im = Image.new("RGBA", (BW * S, BH * S), (0, 0, 0, 0))
        d = ImageDraw.Draw(im, "RGBA")
        ellipse(d, (24, 118, 175, 151), (0, 0, 0, 120))
        iso_platform(d, 96, 124, 150, 66, 4, shade(DEEP, .66))
        poly(d, [(43, 105), (77, 82), (113, 96), (145, 79), (163, 111), (137, 134), (86, 130)], shade(STEEL, .40), INK)
        poly(d, [(62, 86), (109, 69), (143, 84), (126, 102), (88, 96)], shade(LIGHT, .34), INK)
        line(d, [(47, 74), (83, 125)], RUST, 7)
        line(d, [(142, 75), (116, 130)], shade(STEEL, .45), 6)
        for i in range(7):
            ellipse(d, (93 + i * 5, 44 - i * 4, 122 + i * 8, 69 + i * 5), (42, 46, 47, 125 - i * 14))
    return im.resize((BW, BH), Image.Resampling.LANCZOS)


def repair_frame(stage: int) -> Image.Image:
    im = Image.new("RGBA", (BW * S, BH * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im, "RGBA")
    ellipse(d, (27, 118, 166, 151), (0, 0, 0, 110))
    iso_platform(d, 96, 121, 142, 62, 8, shade(PANEL, .66))
    # Service deck.
    poly(d, [(48, 105), (95, 82), (145, 105), (96, 135)], (43, 49, 52, 255), INK)
    for i in range(7):
        line(d, [(55 + i * 7, 105 + i * .1), (95 + i * 4, 126 - i * .15)], (79, 89, 92, 220), 1)
    # Rear workshop and curved gantry.
    iso_box(d, 126, 113, 58, 32, 42, LIGHT, STEEL, PANEL)
    rect(d, (116, 78, 145, 108), (55, 63, 66, 255), INK, 1, 2)
    poly(d, [(51, 101), (45, 70), (57, 50), (83, 43), (103, 54), (98, 64), (80, 54), (64, 59), (57, 75), (61, 104)], shade(YELLOW, .82), INK)
    poly(d, [(55, 69), (66, 55), (81, 49), (97, 56), (92, 62), (80, 56), (69, 61), (62, 74)], YELLOW_LIGHT, INK)
    # Repair arm, hose and tool head.
    line(d, [(85, 59), (115, 76), (103, 98)], INK, 6)
    line(d, [(85, 56), (116, 73), (104, 95)], STEEL, 3)
    ellipse(d, (96, 92, 111, 106), BLUE_LIGHT, INK, 1)
    line(d, [(108, 101), (126, 115)], (31, 35, 37, 255), 3)
    # Cylinders and diagnostics.
    ellipse(d, (28, 86, 51, 106), STEEL, INK, 1)
    ellipse(d, (31, 79, 48, 92), BLUE_LIGHT, INK, 1)
    rect(d, (138, 68, 157, 93), PANEL, INK, 1, 3)
    rect(d, (142, 72, 153, 80), BLUE_LIGHT, INK, 1)
    if stage >= 1:
        draw_cracks(d, stage)
        line(d, [(72, 55), (61, 80)], RUST, 4)
    if stage >= 2:
        rect(d, (121, 80, 143, 103), (37, 33, 31, 230), INK, 1)
        ellipse(d, (114, 42, 153, 75), (36, 39, 40, 145))
    if stage == 3:
        im = Image.new("RGBA", (BW * S, BH * S), (0, 0, 0, 0))
        d = ImageDraw.Draw(im, "RGBA")
        ellipse(d, (27, 119, 166, 151), (0, 0, 0, 120))
        iso_platform(d, 96, 124, 142, 62, 4, shade(DEEP, .68))
        poly(d, [(48, 108), (88, 88), (144, 108), (113, 135), (66, 130)], (29, 32, 33, 255), INK)
        line(d, [(52, 78), (91, 113)], shade(YELLOW, .48), 9)
        line(d, [(95, 58), (126, 125)], shade(STEEL, .42), 7)
        rect(d, (121, 96, 151, 117), shade(RUST, .54), INK, 1)
        for i in range(6):
            ellipse(d, (101 + i * 5, 49 - i * 4, 129 + i * 8, 72 + i * 5), (42, 45, 46, 120 - i * 14))
    return im.resize((BW, BH), Image.Resampling.LANCZOS)


def unit_dir(index: int):
    a = index * math.tau / 8
    return math.cos(a), math.sin(a)


def vehicle_poly(cx, cy, dx, dy, length, width):
    px, py = -dy, dx
    return [
        (cx + dx * length * .52 + px * width * .5, cy + dy * length * .32 + py * width * .30),
        (cx + dx * length * .52 - px * width * .5, cy + dy * length * .32 - py * width * .30),
        (cx - dx * length * .52 - px * width * .5, cy - dy * length * .32 - py * width * .30),
        (cx - dx * length * .52 + px * width * .5, cy - dy * length * .32 + py * width * .30),
    ]


def harvester_frame(direction: int, state: str, frame: int) -> Image.Image:
    damaged = state.startswith("damaged_")
    if damaged:
        state = state.removeprefix("damaged_")
    im = Image.new("RGBA", (UNIT * S, UNIT * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im, "RGBA")
    dx, dy = unit_dir(direction)
    px, py = -dy, dx
    cx, cy = 48.0, 61.0
    if state == "move":
        cy += [0, -1, 0, 1][frame]
    if state == "death":
        progress = frame / 5.0
        ellipse(d, (18, 68, 78, 88), (0, 0, 0, 115))
        if frame < 4:
            r = 8 + frame * 8
            ellipse(d, (48-r, 52-r, 48+r, 52+r), (255, 112 + frame*22, 22, 230-frame*38))
            ellipse(d, (48-r*.5, 52-r*.5, 48+r*.5, 52+r*.5), (255, 226, 105, 220))
        wreck = vehicle_poly(cx, cy + progress * 5, dx, dy, 48, 32)
        poly(d, wreck, shade(PANEL, .45 - progress*.12), BLACK)
        # detached collector and ore chunks
        line(d, [(cx + dx*10, cy), (cx + dx*(27+frame*2), cy + dy*(17+frame))], shade(STEEL, .42), 6)
        for i in range(4):
            ox = cx + px * (i-1.5)*7 + (frame-2)*2
            oy = cy - 8 - i*3 - frame*2
            rect(d, (ox-3, oy-2, ox+3, oy+2), shade(YELLOW, .55), BLACK, 1)
        return im.resize((UNIT, UNIT), Image.Resampling.LANCZOS)

    ellipse(d, (17, 68, 79, 88), (0, 0, 0, 115))
    # Heavy tracks.
    hull = vehicle_poly(cx, cy, dx, dy, 50, 33)
    track_l = [(x + px*5, y + py*3 + 3) for x,y in hull]
    track_r = [(x - px*5, y - py*3 + 3) for x,y in hull]
    poly(d, track_l, BLACK, INK)
    poly(d, track_r, BLACK, INK)
    poly(d, hull, shade(STEEL, .72), INK)
    top = vehicle_poly(cx - dx*1, cy-5, dx, dy, 36, 23)
    poly(d, top, LIGHT, INK)
    # Team-colored cabin and windows.
    cabin = vehicle_poly(cx - dx*7, cy-11, dx, dy, 22, 18)
    poly(d, cabin, BLUE, INK)
    win_center = (cx - dx*13, cy-15)
    ellipse(d, (win_center[0]-6, win_center[1]-4, win_center[0]+6, win_center[1]+4), (126, 195, 220, 230), INK, 1)
    # Open ore hopper.
    hopper_center = (cx + dx*5, cy-13)
    hp = vehicle_poly(hopper_center[0], hopper_center[1], dx, dy, 23, 19)
    poly(d, hp, shade(YELLOW, .82), INK)
    inner = vehicle_poly(hopper_center[0]+dx*1, hopper_center[1]+1, dx, dy, 15, 11)
    poly(d, inner, (72, 63, 38, 255), INK)
    # Front collector boom and animated drum.
    boom_start = (cx + dx*15, cy + dy*8)
    boom_end = (cx + dx*32, cy + dy*19 + 3)
    line(d, [boom_start, boom_end], INK, 8)
    line(d, [boom_start, boom_end], shade(STEEL, .82), 4)
    drum_cx, drum_cy = boom_end[0], boom_end[1]
    ellipse(d, (drum_cx-9, drum_cy-6, drum_cx+9, drum_cy+6), DEEP, INK, 1)
    phase = frame if state == "harvest" else (frame if state == "move" else 0)
    for tooth in range(4):
        a = (tooth * math.pi/2) + phase * .7
        tx = drum_cx + math.cos(a)*8
        ty = drum_cy + math.sin(a)*5
        line(d, [(drum_cx, drum_cy), (tx, ty)], YELLOW_LIGHT if state == "harvest" else STEEL, 2)
    if state == "move":
        for i in range(4):
            phase_x = ((i * 9 + frame * 5) % 31) - 15
            tx = cx - dx*phase_x + px*14
            ty = cy - dy*phase_x + py*7 + 4
            ellipse(d, (tx-2,ty-2,tx+2,ty+2), (185, 201, 206, 180))
    if state == "harvest":
        # ore spray and cutter sparks
        for i in range(5):
            a = i * 1.7 + frame * .9
            ox = drum_cx + math.cos(a) * (5+i*1.8)
            oy = drum_cy - 5 - i*2 + math.sin(a)*2
            ellipse(d, (ox-2,oy-2,ox+2,oy+2), YELLOW_LIGHT if i % 2 == 0 else (172, 109, 42, 255))
        if frame % 2:
            line(d, [(drum_cx+px*2, drum_cy-3), (drum_cx+px*9, drum_cy-10)], (255, 234, 115, 240), 2)
    if damaged:
        # Dedicated damaged frame: scorched armor, torn hopper plate and cracked cabin.
        scorch_x = cx - px * 8 - dx * 2
        scorch_y = cy - py * 5 - 8
        ellipse(d, (scorch_x-8, scorch_y-5, scorch_x+8, scorch_y+5), (40, 33, 29, 220), INK, 1)
        line(d, [(scorch_x-5, scorch_y-5), (scorch_x+4, scorch_y+5)], RUST, 2)
        line(d, [(scorch_x+5, scorch_y-5), (scorch_x-1, scorch_y+3)], RUST, 2)
        tear_x = hopper_center[0] + px * 5
        tear_y = hopper_center[1] + py * 3
        poly(d, [(tear_x-5, tear_y-3), (tear_x+4, tear_y-5), (tear_x+7, tear_y+3), (tear_x-2, tear_y+6)], shade(RUST, .62), INK)
        line(d, [(win_center[0]-4, win_center[1]-3), (win_center[0]+4, win_center[1]+3)], (222, 235, 238, 220), 1)
        line(d, [(win_center[0]+2, win_center[1]-3), (win_center[0]-1, win_center[1]+2)], (222, 235, 238, 220), 1)
    return im.resize((UNIT, UNIT), Image.Resampling.LANCZOS)


def save_building(name, maker):
    sheet = Image.new("RGBA", (BW*4, BH), (0,0,0,0))
    for stage in range(4):
        sheet.alpha_composite(maker(stage), (stage*BW, 0))
    sheet.save(BUILDING_OUT / f"{name}.png", optimize=True)


def save_harvester():
    # Standard rows 0..18 plus dedicated low-health variants at rows 19..28.
    sheet = Image.new("RGBA", (UNIT*8, UNIT*29), (0,0,0,0))
    rows = {
        "idle": (0,2), "move": (2,4), "attack": (6,3), "death": (9,6), "harvest": (15,4),
        "damaged_idle": (19,2), "damaged_move": (21,4), "damaged_harvest": (25,4)
    }
    for state, (start,count) in rows.items():
        for f in range(count):
            for direction in range(8):
                actual_state = "idle" if state == "attack" else state
                actual_frame = f % 2 if state == "attack" else f
                sheet.alpha_composite(harvester_frame(direction, actual_state, actual_frame), (direction*UNIT,(start+f)*UNIT))
    sheet.save(UNIT_OUT / "harvester.png", optimize=True)


def make_preview():
    canvas = Image.new("RGBA", (900, 520), (28, 40, 32, 255))
    # lightweight grass checker
    d = ImageDraw.Draw(canvas, "RGBA")
    for y in range(0,520,16):
        for x in range(0,900,16):
            c=(61+(x+y)//16%2*5,86+(x//16)%3*3,49,255)
            d.rectangle((x,y,x+16,y+16),fill=c)
    command = command_frame(0).resize((288,240),Image.Resampling.NEAREST)
    factory = war_factory_frame(0).resize((288,240),Image.Resampling.NEAREST)
    repair = repair_frame(0).resize((288,240),Image.Resampling.NEAREST)
    harv = harvester_frame(1,"harvest",2).resize((192,192),Image.Resampling.NEAREST)
    canvas.alpha_composite(command,(0,10))
    canvas.alpha_composite(factory,(300,10))
    canvas.alpha_composite(repair,(600,10))
    canvas.alpha_composite(harv,(350,290))
    canvas.save(PREVIEW_OUT)


def main():
    save_building("command", command_frame)
    save_building("war_factory", war_factory_frame)
    save_building("repair_bay", repair_frame)
    save_harvester()
    make_preview()
    print("Generated v0.9.0 command, war factory, repair bay and harvester assets")


if __name__ == "__main__":
    main()

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import re
import shutil
import sys
from typing import Any, Iterable

from PIL import Image, ImageChops, ImageDraw, ImageFilter

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from ra2_pipeline.assets import AssetIndex, THEATERS
    from ra2_pipeline.hva import HvaFile
    from ra2_pipeline.palette import Palette
    from ra2_pipeline.render import RenderSettings, VoxelPart, merge_projection_bounds, render_voxel_parts, voxel_projection_bounds
    from ra2_pipeline.shp_ts import ShpTsFile
    from ra2_pipeline.vpl import VplFile
    from ra2_pipeline.vxl import VxlFile
else:
    from .assets import AssetIndex, THEATERS
    from .hva import HvaFile
    from .palette import Palette
    from .render import RenderSettings, VoxelPart, merge_projection_bounds, render_voxel_parts, voxel_projection_bounds
    from .shp_ts import ShpTsFile
    from .vpl import VplFile
    from .vxl import VxlFile

GODOT_TO_RA2_8 = (6, 5, 4, 3, 2, 1, 0, 7)
# Dolphin and giant squid use clockwise SHP facing blocks: N, NE, E, SE, S, SW, W, NW.
GODOT_TO_RA2_MARINE_8 = (2, 3, 4, 5, 6, 7, 0, 1)
MARINE_CLOCKWISE_IDS = {"DLPH", "SQD"}
THEATER_ORDER = ("temperate", "snow", "urban", "desert", "lunar", "newurban")
MAX_COMPONENT_FRAMES = 24
MAX_COMPOSITE_FRAMES = 48
BUILDING_PREVIEW_THEATERS = ("temperate", "snow")
INFANTRY_SEQUENCE_PRIORITY = (
    "Ready", "Guard", "Walk", "FireUp", "Prone", "Crawl", "FireProne",
    "Die1", "Die2", "Deploy", "Deployed", "DeployedFire", "Cheer", "Idle1", "Idle2",
)
FULL_THEATER_BUILDINGS = {
    "GACNST", "NACNST", "YACNST", "GAPOWR", "NAPOWR", "YAPOWR",
    "GAWEAP", "NAWEAP", "YAWEAP",
}
ALWAYS_PREVIEW = {"GACNST", "NACNST", "YACNST", "AMCV", "SMCV", "PCV"}


def safe_slug(value: str) -> str:
    slug = re.sub(r"[^0-9A-Za-z_-]+", "_", value.strip()).strip("_")
    return slug.lower() or "animation"


def remap_mask_from_indices(indices: bytes, width: int, height: int) -> Image.Image:
    """Create a grayscale remap ramp. Tinting it preserves the 16-level team ramp."""
    pixels: list[tuple[int, int, int, int]] = []
    for value in indices:
        if 16 <= value <= 31:
            shade = 72 + int(round((value - 16) / 15.0 * 183.0))
            pixels.append((shade, shade, shade, 255))
        else:
            pixels.append((0, 0, 0, 0))
    image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    image.putdata(pixels)
    return image


def shp_frame_pair(shp: ShpTsFile, frame_index: int, palette: Palette) -> tuple[Image.Image, Image.Image]:
    indices = shp.decode_indices(frame_index)
    image = Image.new("RGBA", (shp.width, shp.height), (0, 0, 0, 0))
    image.putdata([palette.rgba(value) for value in indices])
    return image, remap_mask_from_indices(indices, shp.width, shp.height)


def save_pair(target: Path, prefix: str, image: Image.Image, mask: Image.Image) -> tuple[str, str]:
    frame_name = f"{prefix}.png"
    mask_name = f"{prefix}_remap.png"
    # ``optimize=True`` performs an expensive exhaustive PNG pass and made
    # multi-state buildings take tens of minutes to preview.  ZIP delivery
    # already recompresses the files, so a moderate PNG level is the better
    # development trade-off.
    image.save(target / frame_name, compress_level=4)
    mask.save(target / mask_name, compress_level=4)
    return frame_name, mask_name


def entity_by_id(database: dict[str, Any], entity_id: str) -> dict[str, Any]:
    for entity in database["entities"]:
        if str(entity.get("id", "")).casefold() == entity_id.casefold():
            return entity
    raise KeyError(entity_id)


def record_path(record: dict[str, Any] | None, roots: dict[str, Path]) -> Path | None:
    if not record:
        return None
    pack = str(record.get("pack", ""))
    root = roots.get(pack)
    if root is None:
        return None
    return root / str(record.get("relative_path", ""))


def is_preview_candidate(entity: dict[str, Any]) -> bool:
    visuals = entity.get("visuals", {})
    if visuals.get("kind") in {None, "", "missing"}:
        return False
    entity_id = str(entity.get("id", "")).upper()
    category = str(entity.get("category", ""))
    if entity_id in ALWAYS_PREVIEW:
        return True
    if category in {"vehicle", "aircraft"}:
        # Voxel/SHP vehicles are cheap to preview and useful even for neutral map objects.
        return True
    if category == "infantry":
        # Cover all normally producible combat/support infantry, not hundreds of civilian-only frames.
        return int(entity.get("tech_level", -1)) >= 0 and int(entity.get("cost", 0)) > 0
    if category == "building":
        return int(entity.get("tech_level", -1)) >= 0 and int(entity.get("cost", 0)) > 0
    return False


def _animation_entry(label: str, directional: bool, facing_count: int, rate_ms: int = 120) -> dict[str, Any]:
    return {
        "label": label,
        "directional": directional,
        "facing_count": facing_count,
        "rate_ms": max(20, int(rate_ms)),
        "loop": True,
        "directions": {} if directional else None,
        "frames": [] if not directional else None,
        "remap_masks": [] if not directional else None,
        "source_indices": [] if not directional else None,
    }


def write_infantry(entity: dict[str, Any], roots: dict[str, Path], output: Path, theater: str = "temperate") -> dict[str, Any]:
    target = output / str(entity["id"]).lower()
    target.mkdir(parents=True, exist_ok=True)
    visual = entity["visuals"]
    theater_data = visual.get("theaters", {}).get(theater, {})
    body_path = record_path(theater_data.get("body"), roots)
    palette_path = record_path(theater_data.get("palette"), roots)
    if body_path is None or palette_path is None:
        raise FileNotFoundError(f"Missing SHP or palette for {entity['id']}")
    shp = ShpTsFile(body_path)
    palette = Palette.from_file(palette_path)

    manifest: dict[str, Any] = {
        "schema_version": 2,
        "entity_id": entity["id"],
        "category": entity.get("category", "infantry"),
        "visual_kind": "infantry_shp",
        "source": body_path.name,
        "palette": palette_path.name,
        "canvas": [shp.width, shp.height],
        "available_theaters": list(visual.get("theaters", {}).keys()),
        "theater": theater,
        "default_animation": "Ready",
        "animations": {},
    }
    sequences = visual.get("sequences", {})
    ordered_names = [name for name in INFANTRY_SEQUENCE_PRIORITY if name in sequences]
    if not ordered_names:
        ordered_names = list(sequences.keys())[:8]
    for sequence_name in ordered_names:
        sequence = sequences[sequence_name]
        directional = bool(sequence.get("directional", False))
        facing_count = int(sequence.get("facing_count", 8 if directional else 1)) if directional else 1
        animation = _animation_entry(str(sequence_name), directional, facing_count, 110)
        animation["source_sequence"] = sequence_name
        animation["reverse"] = bool(sequence.get("reverse", False))
        if directional:
            for facing in range(facing_count):
                frame_indices = [int(index) for index in sequence.get("godot_frames", {}).get(str(facing), [])]
                frames: list[str] = []
                masks: list[str] = []
                valid_indices: list[int] = []
                for local_index, source_index in enumerate(frame_indices):
                    if not 0 <= source_index < shp.frame_count:
                        continue
                    image, mask = shp_frame_pair(shp, source_index, palette)
                    prefix = f"{safe_slug(sequence_name)}_{facing}_{local_index:03d}"
                    frame_name, mask_name = save_pair(target, prefix, image, mask)
                    frames.append(frame_name)
                    masks.append(mask_name)
                    valid_indices.append(source_index)
                animation["directions"][str(facing)] = {
                    "frames": frames,
                    "remap_masks": masks,
                    "source_indices": valid_indices,
                }
        else:
            raw_frames: list[int] = []
            godot_frames = sequence.get("godot_frames", {})
            if isinstance(godot_frames, dict):
                raw_frames = [int(index) for index in godot_frames.get("0", [])]
            frames: list[str] = []
            masks: list[str] = []
            valid_indices: list[int] = []
            for local_index, source_index in enumerate(raw_frames):
                if not 0 <= source_index < shp.frame_count:
                    continue
                image, mask = shp_frame_pair(shp, source_index, palette)
                prefix = f"{safe_slug(sequence_name)}_{local_index:03d}"
                frame_name, mask_name = save_pair(target, prefix, image, mask)
                frames.append(frame_name)
                masks.append(mask_name)
                valid_indices.append(source_index)
            animation["frames"] = frames
            animation["remap_masks"] = masks
            animation["source_indices"] = valid_indices
        has_frames = any(item.get("frames") for item in animation.get("directions", {}).values()) if directional else bool(animation.get("frames"))
        if has_frames:
            manifest["animations"][sequence_name] = animation
    if manifest["default_animation"] not in manifest["animations"] and manifest["animations"]:
        manifest["default_animation"] = next(iter(manifest["animations"]))
    (target / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    return manifest


def _shp_vehicle_ranges(entity: dict[str, Any], shp: ShpTsFile) -> list[tuple[str, int, int, int]]:
    art_values = entity.get("art", {}).get("values", {})
    facings = max(1, int(art_values.get("Facings", 8)))
    walk = max(0, int(art_values.get("WalkFrames", 0)))
    firing = max(0, int(art_values.get("FiringFrames", 0)))
    standing = max(0, int(art_values.get("StandingFrames", 0)))
    walk_start = int(art_values.get("StartWalkFrame", 0))
    firing_start = int(art_values.get("StartFiringFrame", walk_start + facings * walk))
    stand_start = int(art_values.get("StartStandFrame", firing_start + facings * firing))
    ranges: list[tuple[str, int, int, int]] = []
    if standing > 0:
        ranges.append(("Stand", stand_start, standing, facings))
    if walk > 0:
        ranges.append(("Walk", walk_start, walk, facings))
    if firing > 0:
        ranges.append(("Fire", firing_start, firing, facings))
    if not ranges:
        frames_per_facing = max(1, shp.frame_count // facings)
        ranges.append(("Stand", 0, frames_per_facing, facings))
    return ranges


def write_shp_vehicle(entity: dict[str, Any], roots: dict[str, Path], output: Path, theater: str = "temperate") -> dict[str, Any]:
    target = output / str(entity["id"]).lower()
    target.mkdir(parents=True, exist_ok=True)
    visual = entity["visuals"]
    theater_data = visual.get("theaters", {}).get(theater, {})
    body_path = record_path(theater_data.get("body"), roots)
    palette_path = record_path(theater_data.get("palette"), roots)
    if body_path is None or palette_path is None:
        raise FileNotFoundError(f"Missing SHP vehicle art for {entity['id']}")
    shp = ShpTsFile(body_path)
    palette = Palette.from_file(palette_path)
    manifest: dict[str, Any] = {
        "schema_version": 2,
        "entity_id": entity["id"],
        "category": entity.get("category", "vehicle"),
        "visual_kind": "vehicle_shp",
        "source": body_path.name,
        "palette": palette_path.name,
        "canvas": [shp.width, shp.height],
        "available_theaters": list(visual.get("theaters", {}).keys()),
        "theater": theater,
        "default_animation": "Stand",
        "animations": {},
    }
    entity_id = str(entity.get("id", "")).upper()
    facing_map = GODOT_TO_RA2_MARINE_8 if entity_id in MARINE_CLOCKWISE_IDS else GODOT_TO_RA2_8
    for animation_name, start, frames_per_facing, facings in _shp_vehicle_ranges(entity, shp):
        animation = _animation_entry(animation_name, True, facings, 110)
        for godot_facing in range(facings):
            source_facing = facing_map[godot_facing] if facings == 8 else godot_facing
            indices = [start + source_facing * frames_per_facing + local for local in range(frames_per_facing)]
            frames: list[str] = []
            masks: list[str] = []
            valid: list[int] = []
            for local, source_index in enumerate(indices):
                if not 0 <= source_index < shp.frame_count:
                    continue
                image, mask = shp_frame_pair(shp, source_index, palette)
                prefix = f"{safe_slug(animation_name)}_{godot_facing}_{local:03d}"
                frame_name, mask_name = save_pair(target, prefix, image, mask)
                frames.append(frame_name)
                masks.append(mask_name)
                valid.append(source_index)
            animation["directions"][str(godot_facing)] = {
                "frames": frames,
                "remap_masks": masks,
                "source_indices": valid,
            }
        if any(item.get("frames") for item in animation["directions"].values()):
            manifest["animations"][animation_name] = animation
    if manifest["default_animation"] not in manifest["animations"] and manifest["animations"]:
        manifest["default_animation"] = next(iter(manifest["animations"]))
    (target / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    return manifest


def write_voxel(entity: dict[str, Any], roots: dict[str, Path], output: Path, index: AssetIndex) -> dict[str, Any]:
    target = output / str(entity["id"]).lower()
    target.mkdir(parents=True, exist_ok=True)
    visual = entity["visuals"]
    part_specs: list[tuple[VxlFile, HvaFile | None, str]] = []
    source_names: list[str] = []
    max_hva_frames = 1
    for model_key, hva_key in (("body", "body_hva"), ("turret", "turret_hva"), ("barrel", "barrel_hva")):
        model_path = record_path(visual.get(model_key), roots)
        if model_path is None or not model_path.exists():
            continue
        hva_path = record_path(visual.get(hva_key), roots)
        model = VxlFile(model_path)
        animation = HvaFile(hva_path) if hva_path is not None and hva_path.exists() else None
        if animation is not None:
            max_hva_frames = max(max_hva_frames, int(animation.frame_count))
        part_specs.append((model, animation, model_key))
        source_names.append(model_path.name)
    if not part_specs:
        raise FileNotFoundError(f"Missing VXL for {entity['id']}")
    vpl_record = index.resolve_filename("voxels.vpl", tuple(reversed(tuple(roots.keys()))))
    vpl = VplFile.from_file(vpl_record.absolute_path) if vpl_record else None
    settings = RenderSettings(canvas_width=224, canvas_height=192, pixel_size=2, anchor_y=0.82)
    facing_count = 8

    manifest: dict[str, Any] = {
        "schema_version": 2,
        "entity_id": entity["id"],
        "category": entity.get("category", "vehicle"),
        "visual_kind": "voxel",
        "sources": source_names,
        "canvas": [settings.canvas_width, settings.canvas_height],
        "available_theaters": [],
        "default_animation": "Stand",
        "animations": {},
        "turret_offset_leptons": visual.get("turret_offset_leptons", 0),
        "primary_fire_flh": visual.get("primary_fire_flh"),
        "secondary_fire_flh": visual.get("secondary_fire_flh"),
        "shadow_index": visual.get("shadow_index", 0),
        "use_turret_shadow": visual.get("use_turret_shadow", False),
        "no_spawn_alt": visual.get("no_spawn_alt", False),
        "render_note": "8-direction development preview using VXL/HVA geometry and VPL ramps.",
    }

    entity_id = str(entity.get("id", "")).upper()
    is_gattling_vehicle = entity_id == "YTNK" and max_hva_frames > 1
    animation_names = ("Stand", "Fire") if is_gattling_vehicle else (("HVA",) if max_hva_frames > 1 else ("Stand",))
    for animation_name in animation_names:
        animation = _animation_entry(animation_name, True, facing_count, 90)
        frame_range = range(max_hva_frames) if animation_name in {"HVA", "Fire"} else range(1)
        for facing in range(facing_count):
            frames: list[str] = []
            masks: list[str] = []
            indices: list[int] = []
            for hva_frame in frame_range:
                parts = [VoxelPart(model, hva, hva_frame) for model, hva, _name in part_specs]
                image = render_voxel_parts(parts, facing, facing_count, settings, vpl=vpl)
                mask = render_voxel_parts(parts, facing, facing_count, settings, vpl=vpl, remap_mask=True)
                prefix = f"{safe_slug(animation_name)}_{facing}_{hva_frame:03d}"
                frame_name, mask_name = save_pair(target, prefix, image, mask)
                frames.append(frame_name)
                masks.append(mask_name)
                indices.append(hva_frame)
            animation["directions"][str(facing)] = {
                "frames": frames,
                "remap_masks": masks,
                "source_indices": indices,
            }
        manifest["animations"][animation_name] = animation
    manifest["default_animation"] = "Stand" if "Stand" in manifest["animations"] else animation_names[0]

    # Runtime vehicle layers.  The browser's combined frames remain available,
    # while the game uses separate chassis and turret sprites so the turret can
    # track targets independently and keep firing during movement.  Each layer
    # is rendered with all other parts kept as transparent geometry, preserving
    # identical fitting/anchoring for every body/turret direction pair.
    has_body = any(name == "body" for _model, _hva, name in part_specs)
    has_turret = any(name in {"turret", "barrel"} for _model, _hva, name in part_specs)
    if has_body and has_turret:
        layered: dict[str, Any] = {
            "direction_count": facing_count,
            "stand": {},
            "fire": {},
            "fire_frame_count": max_hva_frames if is_gattling_vehicle else 1,
            "fire_rate_ms": 90,
        }
        for body_facing in range(facing_count):
            candidate_bounds: list[tuple[float, float, float, float] | None] = []
            for turret_facing in range(facing_count):
                frame_indices = range(max_hva_frames) if is_gattling_vehicle else range(1)
                for hva_frame in frame_indices:
                    all_parts = [
                        VoxelPart(
                            model, hva, hva_frame,
                            facing_index=body_facing if part_name == "body" else turret_facing,
                            visible=True,
                        )
                        for model, hva, part_name in part_specs
                    ]
                    candidate_bounds.append(
                        voxel_projection_bounds(all_parts, 0, facing_count, settings)
                    )
            fixed_bounds = merge_projection_bounds(candidate_bounds)

            body_parts = [
                VoxelPart(
                    model, hva, 0,
                    facing_index=body_facing,
                    visible=part_name == "body",
                )
                for model, hva, part_name in part_specs
            ]
            body_image = render_voxel_parts(
                body_parts, 0, facing_count, settings, vpl=vpl, fixed_bounds=fixed_bounds
            )
            body_mask = render_voxel_parts(
                body_parts, 0, facing_count, settings, vpl=vpl, remap_mask=True, fixed_bounds=fixed_bounds
            )
            body_name, body_mask_name = save_pair(
                target, f"layer_body_{body_facing}", body_image, body_mask
            )

            for turret_facing in range(facing_count):
                key = f"{body_facing}:{turret_facing}"
                turret_parts = [
                    VoxelPart(
                        model, hva, 0,
                        facing_index=body_facing if part_name == "body" else turret_facing,
                        visible=part_name != "body",
                    )
                    for model, hva, part_name in part_specs
                ]
                turret_image = render_voxel_parts(
                    turret_parts, 0, facing_count, settings, vpl=vpl, fixed_bounds=fixed_bounds
                )
                turret_mask = render_voxel_parts(
                    turret_parts, 0, facing_count, settings, vpl=vpl, remap_mask=True, fixed_bounds=fixed_bounds
                )
                turret_name, turret_mask_name = save_pair(
                    target, f"layer_turret_{body_facing}_{turret_facing}", turret_image, turret_mask
                )
                layered["stand"][key] = {
                    "body": body_name,
                    "body_remap": body_mask_name,
                    "turret": [turret_name],
                    "turret_remap": [turret_mask_name],
                }
                if is_gattling_vehicle:
                    fire_frames: list[str] = []
                    fire_masks: list[str] = []
                    for hva_frame in range(max_hva_frames):
                        fire_parts = [
                            VoxelPart(
                                model, hva, hva_frame,
                                facing_index=body_facing if part_name == "body" else turret_facing,
                                visible=part_name != "body",
                            )
                            for model, hva, part_name in part_specs
                        ]
                        fire_image = render_voxel_parts(
                            fire_parts, 0, facing_count, settings, vpl=vpl, fixed_bounds=fixed_bounds
                        )
                        fire_mask = render_voxel_parts(
                            fire_parts, 0, facing_count, settings, vpl=vpl, remap_mask=True, fixed_bounds=fixed_bounds
                        )
                        frame_name, mask_name = save_pair(
                            target,
                            f"layer_turret_fire_{body_facing}_{turret_facing}_{hva_frame:03d}",
                            fire_image,
                            fire_mask,
                        )
                        fire_frames.append(frame_name)
                        fire_masks.append(mask_name)
                    layered["fire"][key] = {
                        "turret": fire_frames,
                        "turret_remap": fire_masks,
                    }
        manifest["layered_vehicle"] = layered

    deploy = visual.get("deploying_animation") or {}
    deploy_path = record_path(deploy.get("asset"), roots)
    if deploy_path is not None and deploy_path.exists():
        try:
            deploy_shp = ShpTsFile(deploy_path)
            deploy_palette_record = index.resolve_filename("unittem.pal", tuple(reversed(tuple(roots.keys()))))
            if deploy_palette_record is not None:
                deploy_palette = Palette.from_file(deploy_palette_record.absolute_path)
                deploy_animation = _animation_entry("Deploy", False, 1, int(deploy.get("rate", 100)))
                visible_count = deploy_shp.frame_count // 2 if deploy.get("shadow") and deploy_shp.frame_count % 2 == 0 else deploy_shp.frame_count
                for source_index in range(min(visible_count, MAX_COMPONENT_FRAMES)):
                    image, mask = shp_frame_pair(deploy_shp, source_index, deploy_palette)
                    frame_name, mask_name = save_pair(target, f"deploy_{source_index:03d}", image, mask)
                    deploy_animation["frames"].append(frame_name)
                    deploy_animation["remap_masks"].append(mask_name)
                    deploy_animation["source_indices"].append(source_index)
                if deploy_animation["frames"]:
                    manifest["animations"]["Deploy"] = deploy_animation
        except Exception:
            pass
    (target / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    return manifest


def _alpha_composite_clipped(canvas: Image.Image, overlay: Image.Image, offset: tuple[int, int]) -> None:
    """Alpha-composite an overlay while keeping the building canvas stable."""
    offset_x, offset_y = int(offset[0]), int(offset[1])
    left = max(0, offset_x)
    top = max(0, offset_y)
    source_left = max(0, -offset_x)
    source_top = max(0, -offset_y)
    width = min(canvas.width - left, overlay.width - source_left)
    height = min(canvas.height - top, overlay.height - source_top)
    if width <= 0 or height <= 0:
        return
    crop = overlay.crop((source_left, source_top, source_left + width, source_top + height))
    canvas.alpha_composite(crop, (left, top))


def _composite_pair(
    base: tuple[Image.Image, Image.Image] | None,
    overlay: tuple[Image.Image, Image.Image],
    offset: tuple[int, int] = (0, 0),
) -> tuple[Image.Image, Image.Image]:
    if base is None:
        full = Image.new("RGBA", overlay[0].size, (0, 0, 0, 0))
        mask = Image.new("RGBA", overlay[1].size, (0, 0, 0, 0))
    else:
        full = base[0].copy()
        mask = base[1].copy()
    _alpha_composite_clipped(full, overlay[0], offset)
    _alpha_composite_clipped(mask, overlay[1], offset)
    return full, mask


def _component_frame_indices(component: dict[str, Any], shp: ShpTsFile, key: str) -> list[int]:
    """Return visible SHP frame indices using Westwood Art.ini semantics.

    ``End`` is inclusive, while ``LoopEnd`` is the first frame *after* the
    loop.  When ``Shadow=yes`` the second half of the SHP is a shadow bank and
    must never be mixed into the visible animation.
    """
    shadow_bank = bool(component.get("Shadow", False))
    visible_count = shp.frame_count
    if shadow_bank and shp.frame_count >= 2 and shp.frame_count % 2 == 0:
        visible_count = shp.frame_count // 2
    visible_count = max(1, visible_count)

    has_explicit_range = any(name in component for name in ("Start", "End", "LoopStart", "LoopEnd"))
    slot = _component_slot(key, component)
    if not has_explicit_range:
        if key.casefold() == "buildup":
            # Buildup SHPs conventionally store visible construction frames in
            # the first half and matching shadow frames in the second, even when
            # the Art section omits an explicit Shadow=yes flag.
            buildup_visible = (
                shp.frame_count // 2
                if shp.frame_count >= 8 and shp.frame_count % 2 == 0
                else visible_count
            )
            indices = list(range(min(buildup_visible, MAX_COMPONENT_FRAMES)))
        elif slot in STRUCTURAL_BELOW_BODY_SLOTS or slot in STRUCTURAL_ABOVE_BODY_SLOTS:
            indices = [0]
        else:
            indices = list(range(min(visible_count, MAX_COMPONENT_FRAMES)))
    elif "End" in component:
        start = int(component.get("Start", 0))
        end = int(component.get("End", start))
        start = max(0, min(visible_count - 1, start))
        end = max(0, min(visible_count - 1, end))
        if end < start:
            start, end = end, start
        indices = list(range(start, end + 1))
    elif "LoopEnd" in component:
        start = int(component.get("LoopStart", component.get("Start", 0)))
        loop_end = int(component.get("LoopEnd", start))
        start = max(0, min(visible_count - 1, start))
        # LoopEnd is exclusive.  A number equal to LoopStart is used by several
        # static door/bib definitions and still denotes one visible frame.
        if loop_end <= start:
            indices = [start]
        else:
            exclusive_end = max(start + 1, min(visible_count, loop_end))
            indices = list(range(start, exclusive_end))
    else:
        start = max(0, min(visible_count - 1, int(component.get("Start", 0))))
        # Start-only definitions normally share one SHP as
        # healthy + damaged + shadow banks.  Select one visible half-bank; the
        # sibling component's Start value then selects the other half.
        bank = max(1, visible_count // 2)
        indices = list(range(start, min(visible_count, start + bank)))

    if bool(component.get("Reverse", False)):
        indices.reverse()
    if len(indices) > MAX_COMPONENT_FRAMES:
        last = len(indices) - 1
        indices = [indices[round(index * last / (MAX_COMPONENT_FRAMES - 1))] for index in range(MAX_COMPONENT_FRAMES)]
    return indices


def _component_slot(key: str, component: dict[str, Any]) -> str:
    explicit = str(component.get("slot", ""))
    if explicit:
        return explicit
    return key[:-7] if key.endswith("Damaged") else key


def _component_offset(component: dict[str, Any]) -> tuple[int, int]:
    return int(component.get("X", 0)), int(component.get("Y", 0))


STRUCTURAL_BELOW_BODY_SLOTS = {"BibShape", "UnderDoorAnim", "UnderRoofDoorAnim"}
STRUCTURAL_ABOVE_BODY_SLOTS = {"DeployingAnim", "RoofDeployingAnim", "DoorAnim"}

def _is_operational_slot(slot: str) -> bool:
    return slot in {
        "ActiveAnim", "ActiveAnimTwo", "ActiveAnimThree", "ActiveAnimFour",
        "IdleAnim", "IdleAnimTwo",
    }

def _is_state_slot(slot: str) -> bool:
    return slot.startswith("SpecialAnim") or slot.startswith("SuperAnim") or slot == "SuperLowPower"


def _opaque_pixel_count(image: Image.Image) -> int:
    histogram = image.getchannel("A").histogram()
    return sum(histogram[1:])


def _dynamic_union_mask(pairs: list[tuple[Image.Image, Image.Image]]) -> Image.Image | None:
    if len(pairs) <= 1:
        return None
    reference = pairs[0][0]
    union = Image.new("L", reference.size, 0)
    for image, _mask in pairs[1:]:
        difference = ImageChops.difference(reference, image)
        channels = difference.split()
        changed = channels[0]
        for channel in channels[1:]:
            changed = ImageChops.lighter(changed, channel)
        union = ImageChops.lighter(union, changed)
    union = union.point(lambda value: 255 if value else 0)
    if union.getbbox() is None:
        return None
    # Include edge pixels around the moving region so anti-aliased outlines do not tear.
    return union.filter(ImageFilter.MaxFilter(3))


def _masked_dynamic_pair(
    pair: tuple[Image.Image, Image.Image], dynamic_mask: Image.Image | None
) -> tuple[Image.Image, Image.Image]:
    if dynamic_mask is None:
        return pair
    image = pair[0].copy()
    remap = pair[1].copy()
    image.putalpha(ImageChops.multiply(image.getchannel("A"), dynamic_mask))
    remap.putalpha(ImageChops.multiply(remap.getchannel("A"), dynamic_mask))
    return image, remap


def _composite_timeline(tracks: list[dict[str, Any]]) -> tuple[int, int]:
    rates = [max(20, int(track.get("rate", 120))) for track in tracks if track.get("pairs")]
    if not rates:
        return 120, 1
    tick = rates[0]
    for rate in rates[1:]:
        tick = math.gcd(tick, rate)
    if tick < 20:
        tick = min(rates)

    periods = [len(track["pairs"]) * max(20, int(track.get("rate", 120))) for track in tracks if track.get("pairs")]
    duration = periods[0]
    for period in periods[1:]:
        duration = math.lcm(duration, period)
        if duration > 12000:
            duration = max(periods)
            break
    duration = max(tick, min(12000, duration))
    frame_count = max(1, math.ceil(duration / tick))
    if frame_count > MAX_COMPOSITE_FRAMES:
        tick = max(tick, math.ceil(duration / MAX_COMPOSITE_FRAMES))
        frame_count = max(1, math.ceil(duration / tick))
    return tick, frame_count


def _write_composite_animation(
    theater_folder: Path,
    animation_key: str,
    label: str,
    base_pair: tuple[Image.Image, Image.Image] | None,
    tracks: list[dict[str, Any]],
) -> dict[str, Any] | None:
    tracks = [track for track in tracks if track.get("pairs")]
    if base_pair is None or not tracks:
        return None
    rate_ms, frame_count = _composite_timeline(tracks)
    animation = _animation_entry(label, False, 1, rate_ms)
    animation["composite"] = True
    animation["components"] = [
        {
            "key": track["key"],
            "slot": track["slot"],
            "source": track["source"],
            "offset": list(track["offset"]),
            "rate_ms": track["rate"],
            "z_adjust": track.get("z_adjust", 0),
            "y_sort": track.get("y_sort", 0),
            "dynamic_region_only": bool(track.get("dynamic_only", False)),
        }
        for track in tracks
    ]
    for frame_index in range(frame_count):
        pair = (base_pair[0].copy(), base_pair[1].copy())
        source_labels: list[str] = []
        elapsed_ms = frame_index * rate_ms
        for track in tracks:
            local_index = int(elapsed_ms / max(20, int(track["rate"]))) % len(track["pairs"])
            overlay_pair = _masked_dynamic_pair(
                track["pairs"][local_index], track.get("dynamic_mask") if track.get("dynamic_only") else None
            )
            pair = _composite_pair(pair, overlay_pair, track["offset"])
            source_labels.append(f"{track['key']}:{track['indices'][local_index]}")
        prefix = f"{safe_slug(animation_key)}_{frame_index:03d}"
        frame_name, mask_name = save_pair(theater_folder, prefix, pair[0], pair[1])
        animation["frames"].append(frame_name)
        animation["remap_masks"].append(mask_name)
        animation["source_indices"].append(" | ".join(source_labels))
    return animation


def _first_component_pair(track: dict[str, Any]) -> tuple[Image.Image, Image.Image] | None:
    pairs = track.get("pairs", [])
    return pairs[0] if pairs else None


def _compose_static_layers(body_pair, below_tracks, above_tracks):
    result = None
    for track in below_tracks:
        pair = _first_component_pair(track)
        if pair is not None:
            result = _composite_pair(result, pair, track["offset"])
    result = _composite_pair(result, body_pair, (0, 0))
    for track in above_tracks:
        pair = _first_component_pair(track)
        if pair is not None:
            result = _composite_pair(result, pair, track["offset"])
    return result


def _pair_with_alpha_mask(
    pair: tuple[Image.Image, Image.Image], alpha_mask: Image.Image
) -> tuple[Image.Image, Image.Image]:
    image = pair[0].copy()
    remap = pair[1].copy()
    image.putalpha(ImageChops.multiply(image.getchannel("A"), alpha_mask))
    remap.putalpha(ImageChops.multiply(remap.getchannel("A"), alpha_mask))
    return image, remap


def _augment_incomplete_building(
    base_pair: tuple[Image.Image, Image.Image] | None,
    body_pair: tuple[Image.Image, Image.Image] | None,
    state_tracks: list[dict[str, Any]],
) -> tuple[Image.Image, Image.Image] | None:
    """Fill buildings whose static body SHP intentionally omits state parts.

    Superweapon buildings and the tank bunker store much or all of their
    visible structure in SpecialAnim/SuperAnim SHPs.  We choose the largest
    healthy state frame as the primary representation only when it clearly
    covers more geometry than the body, then add missing pixels from companion
    state components.  Complete ordinary buildings are left untouched.
    """
    if base_pair is None:
        return None
    candidates: list[tuple[int, int, dict[str, Any], tuple[Image.Image, Image.Image]]] = []
    preferred_order = {
        "SuperAnimTwo": 0, "SuperAnimFour": 1, "SuperAnim": 2, "SuperAnimThree": 3,
        "SpecialAnim": 4, "SpecialAnimTwo": 5, "SpecialAnimThree": 6, "SpecialAnimFour": 7,
        "SuperLowPower": 8,
    }
    for track in state_tracks:
        pair = _first_component_pair(track)
        if pair is None:
            continue
        candidates.append((
            preferred_order.get(track.get("slot", ""), 99),
            _opaque_pixel_count(pair[0]),
            track,
            pair,
        ))
    if not candidates:
        return base_pair
    candidates.sort(key=lambda item: (item[0], -item[1]))
    body_opaque = _opaque_pixel_count(body_pair[0]) if body_pair is not None else 0
    largest_opaque = candidates[0][1]
    if body_opaque >= 128 and largest_opaque <= int(body_opaque * 1.08):
        return base_pair

    result = base_pair
    primary_pair = candidates[0][3]
    # A state SHP that is materially more complete than the body is allowed to
    # replace overlapping body pixels.  This is required for missile silos,
    # Chronospheres, Psychic Dominators and similar all-state buildings.
    if largest_opaque > max(128, int(body_opaque * 1.08)):
        result = _composite_pair(result, primary_pair, candidates[0][2]["offset"])
        # Superweapon component banks are alternative complete states, not
        # simultaneous layers.  Once the preferred bank supplies a complete
        # building, mixing other SuperAnim canvases creates detached fragments.
        if str(candidates[0][2].get("slot", "")).startswith("SuperAnim"):
            return result

    for _preference, candidate_opaque, track, pair in candidates[1:]:
        # Component SHPs are allowed to use a different canvas size than the
        # building body.  Align them on a building-sized temporary canvas before
        # comparing alpha coverage.
        aligned_image = Image.new("RGBA", result[0].size, (0, 0, 0, 0))
        aligned_mask = Image.new("RGBA", result[1].size, (0, 0, 0, 0))
        _alpha_composite_clipped(aligned_image, pair[0], track["offset"])
        _alpha_composite_clipped(aligned_mask, pair[1], track["offset"])
        aligned_pair = (aligned_image, aligned_mask)
        base_alpha = result[0].getchannel("A")
        missing = ImageChops.subtract(aligned_image.getchannel("A"), base_alpha)
        missing = missing.point(lambda value: 255 if value else 0)
        missing_pixels = sum(missing.histogram()[1:])
        # Ignore tiny canvas/alignment differences between alternative
        # full-building state SHPs.  They otherwise appear as detached fragments.
        if missing.getbbox() is None or missing_pixels < max(16, int(candidate_opaque * 0.05)):
            continue
        # Keep one-pixel outlines around newly filled geometry.
        missing = missing.filter(ImageFilter.MaxFilter(3))
        result = _composite_pair(result, _pair_with_alpha_mask(aligned_pair, missing), (0, 0))
    return result


def _render_building_turret_pair(visual, roots, index, canvas_size, body_pair=None):
    turret = visual.get("building_turret") or {}
    if not turret.get("is_voxel"):
        return None
    parts = []
    for model_key, hva_key in (("model", "hva"), ("barrel", "barrel_hva")):
        model_path = record_path(turret.get(model_key), roots)
        if model_path is None or not model_path.exists():
            continue
        hva_path = record_path(turret.get(hva_key), roots)
        parts.append(VoxelPart(VxlFile(model_path), HvaFile(hva_path) if hva_path and hva_path.exists() else None, 0))
    if not parts:
        return None
    vpl_record = index.resolve_filename("voxels.vpl", tuple(reversed(tuple(roots.keys()))))
    vpl = VplFile.from_file(vpl_record.absolute_path) if vpl_record else None
    width, height = canvas_size

    # Render independently, crop transparent margins, then anchor the sprite to
    # the SHP building footprint.  Rendering directly on the full building
    # canvas caused tiny/disconnected or over-sized turrets because the voxel
    # fit operation treated the entire canvas as the turret's own bounds.
    settings = RenderSettings(
        canvas_width=192,
        canvas_height=160,
        pixel_size=1,
        anchor_x=0.50,
        anchor_y=0.78,
        fit_width_ratio=0.72,
        fit_height_ratio=0.62,
    )
    image = render_voxel_parts(parts, 1, 8, settings, vpl=vpl)
    mask = render_voxel_parts(parts, 1, 8, settings, vpl=vpl, remap_mask=True)
    bbox = image.getbbox()
    if bbox is None:
        return None
    image = image.crop(bbox)
    mask = mask.crop(bbox)

    body_bbox = body_pair[0].getbbox() if body_pair is not None else None
    if body_bbox is None:
        body_bbox = (0, 0, width, height)
    body_width = max(1, body_bbox[2] - body_bbox[0])
    body_height = max(1, body_bbox[3] - body_bbox[1])
    turret_id = str(turret.get("id", "")).upper()
    width_ratios = {
        "GTGCANTUR": 1.12,
        "YAGGUN": 1.35,
        "SMINTUR": 0.52,
        "OUTP": 0.62,
        "LASER": 0.82,
        "SAM": 0.88,
        "FLAKTUR": 0.82,
    }
    desired_width = max(12, int(round(body_width * width_ratios.get(turret_id, 0.78))))
    scale = desired_width / max(1, image.width)
    desired_height = max(8, int(round(image.height * scale)))
    if desired_height > int(body_height * 1.55):
        scale = (body_height * 1.55) / max(1, image.height)
        desired_width = max(8, int(round(image.width * scale)))
        desired_height = max(8, int(round(image.height * scale)))
    image = image.resize((desired_width, desired_height), Image.Resampling.NEAREST)
    mask = mask.resize((desired_width, desired_height), Image.Resampling.NEAREST)

    center_x = (body_bbox[0] + body_bbox[2]) * 0.5 + int(turret.get("x", 0))
    anchor_y = body_bbox[1] + body_height * 0.42 + int(turret.get("y", 0))
    offset = (int(round(center_x - desired_width * 0.5)), int(round(anchor_y - desired_height)))
    result = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    result_mask = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    _alpha_composite_clipped(result, image, offset)
    _alpha_composite_clipped(result_mask, mask, offset)
    return result, result_mask


def write_building(entity: dict[str, Any], roots: dict[str, Path], output: Path, index: AssetIndex) -> dict[str, Any]:
    target = output / str(entity["id"]).lower()
    target.mkdir(parents=True, exist_ok=True)
    visual = entity["visuals"]
    all_theaters = [name for name in THEATER_ORDER if name in visual.get("theaters", {})]
    if bool(visual.get("new_theater", False)):
        available_theaters = [name for name in BUILDING_PREVIEW_THEATERS if name in all_theaters]
    else:
        default_name = "temperate" if "temperate" in all_theaters else (all_theaters[0] if all_theaters else "")
        available_theaters = [default_name] if default_name else []
    manifest: dict[str, Any] = {
        "schema_version": 3,
        "entity_id": entity["id"],
        "category": "building",
        "visual_kind": "building_shp",
        "available_theaters": available_theaters,
        "default_theater": "temperate" if "temperate" in available_theaters else (available_theaters[0] if available_theaters else ""),
        "default_animation": "Operational",
        "foundation": visual.get("foundation"),
        "damage_fire_offsets": visual.get("damage_fire_offsets", []),
        "new_theater": bool(visual.get("new_theater", False)),
        "theaters": {},
    }
    for theater in available_theaters:
        theater_data = visual.get("theaters", {}).get(theater, {})
        body_path = record_path(theater_data.get("body"), roots)
        palette_path = record_path(theater_data.get("palette"), roots)
        if body_path is None or palette_path is None or not body_path.exists() or not palette_path.exists():
            continue
        body = ShpTsFile(body_path)
        palette = Palette.from_file(palette_path)
        theater_folder = target / theater
        theater_folder.mkdir(parents=True, exist_ok=True)
        body_pairs: dict[str, tuple[Image.Image, Image.Image]] = {}
        body_animation = _animation_entry("主体状态", False, 1, 500)
        for state_name, source_index in (("normal", 0), ("damaged", 1)):
            if source_index >= body.frame_count:
                continue
            pair = shp_frame_pair(body, source_index, palette)
            body_pairs[state_name] = pair
            frame_name, mask_name = save_pair(theater_folder, f"body_{state_name}", pair[0], pair[1])
            body_animation["frames"].append(frame_name)
            body_animation["remap_masks"].append(mask_name)
            body_animation["source_indices"].append(source_index)
        animations: dict[str, Any] = {"BodyStates": body_animation}
        component_tracks: list[dict[str, Any]] = []

        for key, theater_map in visual.get("components", {}).items():
            component = theater_map.get(theater)
            if not component or not component.get("asset"):
                continue
            path = record_path(component.get("asset"), roots)
            if path is None or not path.exists():
                continue
            try:
                shp = ShpTsFile(path)
            except Exception:
                continue
            indices = _component_frame_indices(component, shp, str(key))
            if not indices:
                continue
            pairs = [shp_frame_pair(shp, source_index, palette) for source_index in indices]
            rate = max(20, int(component.get("Rate", 120)))
            offset = _component_offset(component)
            slot = _component_slot(str(key), component)
            damaged_component = bool(component.get("damaged", str(key).endswith("Damaged")))
            state_base = body_pairs.get("damaged" if damaged_component else "normal")
            body_opaque = _opaque_pixel_count(state_base[0]) if state_base is not None else 0
            component_opaque = max((_opaque_pixel_count(pair[0]) for pair in pairs), default=0)
            full_canvas_component = body_opaque > 0 and component_opaque >= int(body_opaque * 0.45)
            track = {
                "key": str(key),
                "slot": slot,
                "damaged": damaged_component,
                "rate": rate,
                "offset": offset,
                "pairs": pairs,
                "indices": indices,
                "source": path.name,
                "z_adjust": int(component.get("ZAdjust", 0)),
                "y_sort": int(component.get("YSort", 0)),
                "dynamic_only": full_canvas_component and len(pairs) > 1,
                "dynamic_mask": _dynamic_union_mask(pairs) if full_canvas_component else None,
            }
            component_tracks.append(track)

            # Active/idle parts are exported through Operational and DamagedOperational
            # as one merged building animation. Action-specific tracks remain available
            # separately for debugging and later gameplay states.
            if not _is_operational_slot(slot) and not _is_state_slot(slot):
                animation = _animation_entry(str(key), False, 1, rate)
                animation["source"] = path.name
                animation["art_id"] = component.get("art_id", "")
                animation["layer"] = component.get("Layer", "")
                animation["offset"] = list(offset)
                animation["z_adjust"] = track["z_adjust"]
                animation["y_sort"] = track["y_sort"]
                base_pair = body_pairs.get("damaged" if damaged_component else "normal")
                for local, (source_index, overlay) in enumerate(zip(indices, pairs)):
                    if str(key).casefold() == "buildup":
                        pair = overlay
                    elif str(key).casefold() == "bibshape":
                        pair = _composite_pair(overlay, body_pairs.get("normal", overlay))
                    else:
                        pair = _composite_pair(base_pair, overlay, offset)
                    prefix = f"{safe_slug(str(key))}_{local:03d}"
                    frame_name, mask_name = save_pair(theater_folder, prefix, pair[0], pair[1])
                    animation["frames"].append(frame_name)
                    animation["remap_masks"].append(mask_name)
                    animation["source_indices"].append(source_index)
                if animation["frames"]:
                    animations[str(key)] = animation

        tracks_by_slot: dict[str, list[dict[str, Any]]] = {}
        for track in component_tracks:
            tracks_by_slot.setdefault(track["slot"], []).append(track)
        for slot_tracks in tracks_by_slot.values():
            normal_track = next((item for item in slot_tracks if not item["damaged"]), None)
            damaged_track = next((item for item in slot_tracks if item["damaged"]), None)
            if normal_track and damaged_track and normal_track["source"] == damaged_track["source"] and normal_track["indices"] == damaged_track["indices"]:
                source_path = record_path(visual["components"][normal_track["key"]][theater]["asset"], roots)
                if source_path is not None:
                    source_shp = ShpTsFile(source_path)
                    count = len(normal_track["indices"])
                    if count * 2 <= source_shp.frame_count:
                        normal_track["indices"] = list(range(count))
                        damaged_track["indices"] = list(range(count, count * 2))
                        normal_track["pairs"] = [shp_frame_pair(source_shp, i, palette) for i in normal_track["indices"]]
                        damaged_track["pairs"] = [shp_frame_pair(source_shp, i, palette) for i in damaged_track["indices"]]

        normal_below = [t for t in component_tracks if not t["damaged"] and t["slot"] in STRUCTURAL_BELOW_BODY_SLOTS]
        damaged_below = [next((t for t in component_tracks if t["damaged"] and t["slot"] == slot), None) or next((t for t in normal_below if t["slot"] == slot), None) for slot in STRUCTURAL_BELOW_BODY_SLOTS]
        damaged_below = [t for t in damaged_below if t is not None]
        normal_above = [t for t in component_tracks if not t["damaged"] and t["slot"] in STRUCTURAL_ABOVE_BODY_SLOTS]
        damaged_above = [next((t for t in component_tracks if t["damaged"] and t["slot"] == slot), None) or next((t for t in normal_above if t["slot"] == slot), None) for slot in STRUCTURAL_ABOVE_BODY_SLOTS]
        damaged_above = [t for t in damaged_above if t is not None]
        normal_base = _compose_static_layers(body_pairs.get("normal"), normal_below, normal_above)
        damaged_base = _compose_static_layers(body_pairs.get("damaged", body_pairs.get("normal")), damaged_below, damaged_above)

        normal_state_tracks = [
            track for track in component_tracks
            if not track["damaged"] and _is_state_slot(track["slot"])
        ]
        damaged_state_tracks = [
            track for track in component_tracks
            if track["damaged"] and _is_state_slot(track["slot"])
        ]
        normal_base = _augment_incomplete_building(
            normal_base, body_pairs.get("normal"), normal_state_tracks
        )
        damaged_base = _augment_incomplete_building(
            damaged_base,
            body_pairs.get("damaged", body_pairs.get("normal")),
            damaged_state_tracks or normal_state_tracks,
        )

        turret_pair = _render_building_turret_pair(
            visual, roots, index, (body.width, body.height), normal_base
        )
        if turret_pair is not None:
            normal_base = _composite_pair(normal_base, turret_pair)
            damaged_base = _composite_pair(damaged_base, turret_pair)

        if normal_base is not None:
            ready = _animation_entry("完整主体", False, 1, 500)
            frame_name, mask_name = save_pair(
                theater_folder, "ready_normal", normal_base[0], normal_base[1]
            )
            ready["frames"].append(frame_name)
            ready["remap_masks"].append(mask_name)
            ready["source_indices"].append("body + persistent components + turret")
            animations["Ready"] = ready
        if damaged_base is not None:
            damaged_ready = _animation_entry("受损主体", False, 1, 500)
            frame_name, mask_name = save_pair(
                theater_folder, "ready_damaged", damaged_base[0], damaged_base[1]
            )
            damaged_ready["frames"].append(frame_name)
            damaged_ready["remap_masks"].append(mask_name)
            damaged_ready["source_indices"].append("damaged body + persistent components + turret")
            animations["DamagedReady"] = damaged_ready

        normal_by_slot: dict[str, dict[str, Any]] = {}
        damaged_by_slot: dict[str, dict[str, Any]] = {}
        for track in component_tracks:
            if not _is_operational_slot(track["slot"]):
                continue
            if track["damaged"]:
                damaged_by_slot[track["slot"]] = track
            else:
                normal_by_slot[track["slot"]] = track
        operational_slots = (
            "ActiveAnim", "ActiveAnimTwo", "ActiveAnimThree", "ActiveAnimFour",
            "IdleAnim", "IdleAnimTwo",
        )
        normal_tracks = [normal_by_slot[slot] for slot in operational_slots if slot in normal_by_slot]
        damaged_tracks = [
            damaged_by_slot.get(slot, normal_by_slot.get(slot))
            for slot in operational_slots
            if slot in damaged_by_slot or slot in normal_by_slot
        ]
        damaged_tracks = [track for track in damaged_tracks if track is not None]

        operational = _write_composite_animation(
            theater_folder, "Operational", "完整工作动画", normal_base, normal_tracks
        )
        if operational is not None:
            animations["Operational"] = operational
        damaged_operational = _write_composite_animation(
            theater_folder, "DamagedOperational", "受损工作动画",
            damaged_base, damaged_tracks,
        )
        if damaged_operational is not None:
            animations["DamagedOperational"] = damaged_operational

        for slot in sorted({track["slot"] for track in component_tracks if _is_state_slot(track["slot"])}):
            normal_state = next((t for t in component_tracks if t["slot"] == slot and not t["damaged"]), None)
            damaged_state = next((t for t in component_tracks if t["slot"] == slot and t["damaged"]), None)
            if normal_state is not None:
                state_animation = _write_composite_animation(theater_folder, slot, slot, normal_base, [normal_state])
                if state_animation is not None:
                    animations[slot] = state_animation
            if damaged_state is not None:
                key = slot + "Damaged"
                state_animation = _write_composite_animation(theater_folder, key, key, damaged_base, [damaged_state])
                if state_animation is not None:
                    animations[key] = state_animation

        default_animation = "Operational" if "Operational" in animations else ("Ready" if "Ready" in animations else "BodyStates")
        manifest["theaters"][theater] = {
            "body_source": body_path.name,
            "palette": palette_path.name,
            "canvas": [body.width, body.height],
            "default_animation": default_animation,
            "animations": animations,
        }
    if not manifest["theaters"]:
        raise FileNotFoundError(f"No building theater could be generated for {entity['id']}")
    if manifest["default_theater"] not in manifest["theaters"]:
        manifest["default_theater"] = next(iter(manifest["theaters"]))
    selected_default = manifest["theaters"][manifest["default_theater"]].get("default_animation", "BodyStates")
    manifest["default_animation"] = selected_default
    (target / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    return manifest

def _first_frame(manifest: dict[str, Any], output: Path) -> Path | None:
    folder = output / str(manifest["entity_id"]).lower()
    if manifest.get("visual_kind") == "building_shp":
        theater = manifest.get("default_theater", "")
        animations = manifest.get("theaters", {}).get(theater, {}).get("animations", {})
        base = folder / theater
    else:
        animations = manifest.get("animations", {})
        base = folder
    default = manifest.get("default_animation", "")
    animation = animations.get(default) or (next(iter(animations.values())) if animations else {})
    if animation.get("directional"):
        directions = animation.get("directions", {})
        direction = directions.get("0") or (next(iter(directions.values())) if directions else {})
        frames = direction.get("frames", [])
    else:
        frames = animation.get("frames", [])
    return base / frames[0] if frames else None


def gallery(output: Path, manifests: list[dict[str, Any]]) -> None:
    cards: list[tuple[str, Image.Image]] = []
    for manifest in manifests[:120]:
        candidate = _first_frame(manifest, output)
        if candidate is None or not candidate.exists():
            continue
        image = Image.open(candidate).convert("RGBA")
        thumb = Image.new("RGBA", (190, 150), (25, 31, 36, 255))
        scale = min(160 / max(1, image.width), 110 / max(1, image.height), 4)
        resized = image.resize((max(1, int(image.width * scale)), max(1, int(image.height * scale))), Image.Resampling.NEAREST)
        thumb.alpha_composite(resized, ((190 - resized.width) // 2, 28 + (110 - resized.height) // 2))
        draw = ImageDraw.Draw(thumb)
        draw.text((8, 7), str(manifest["entity_id"]), fill=(230, 238, 242, 255))
        cards.append((str(manifest["entity_id"]), thumb))
    if not cards:
        return
    columns = 6
    rows = (len(cards) + columns - 1) // columns
    sheet = Image.new("RGBA", (columns * 198, rows * 158), (14, 18, 22, 255))
    for index, (_name, thumb) in enumerate(cards):
        sheet.alpha_composite(thumb, ((index % columns) * 198 + 4, (index // columns) * 158 + 4))
    sheet.save(output / "RA2_PIPELINE_PREVIEW.png", compress_level=4)


def parse_extra(raw: str) -> tuple[str, Path]:
    if "=" not in raw:
        raise argparse.ArgumentTypeError("--extra must use NAME=PATH")
    name, path = raw.split("=", 1)
    return name.strip(), Path(path).resolve()


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate RA2/YR entity animation previews")
    parser.add_argument("--ra2-root", required=True, type=Path)
    parser.add_argument("--ra2md-root", required=True, type=Path)
    parser.add_argument("--database", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--extra", action="append", default=[], type=parse_extra)
    parser.add_argument("--ids", help="comma-separated entity IDs; defaults to all playable/unit entities")
    args = parser.parse_args()
    database = json.loads(args.database.read_text(encoding="utf-8"))
    roots: dict[str, Path] = {"ra2": args.ra2_root.resolve(), "ra2md": args.ra2md_root.resolve()}
    roots.update({name: path for name, path in args.extra})
    index = AssetIndex()
    index.scan(tuple((name, root) for name, root in roots.items()))
    selected_ids = {item.strip().casefold() for item in args.ids.split(",")} if args.ids else None
    if args.output.exists():
        if selected_ids is None:
            for child in args.output.iterdir():
                if child.name == ".gdignore":
                    continue
                if child.is_dir():
                    shutil.rmtree(child)
                else:
                    child.unlink()
        else:
            for entity_id in selected_ids:
                target = args.output / entity_id
                if target.is_dir():
                    shutil.rmtree(target)
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / ".gdignore").write_text("# Runtime-loaded preview PNG files; skip Godot's import cache.\n", encoding="utf-8")

    candidates = [entity for entity in database.get("entities", []) if is_preview_candidate(entity) or selected_ids is not None and str(entity.get("id", "")).casefold() in selected_ids]
    if selected_ids is not None:
        candidates = [entity for entity in candidates if str(entity.get("id", "")).casefold() in selected_ids]

    manifests: list[dict[str, Any]] = []
    issues: list[dict[str, str]] = []
    total = len(candidates)
    for position, entity in enumerate(candidates, start=1):
        entity_id = str(entity.get("id", ""))
        kind = entity.get("visuals", {}).get("kind")
        try:
            if kind == "voxel":
                manifest = write_voxel(entity, roots, args.output, index)
            elif kind == "building_shp":
                manifest = write_building(entity, roots, args.output, index)
            elif kind == "shp" and entity.get("category") == "infantry":
                manifest = write_infantry(entity, roots, args.output)
            elif kind == "shp":
                manifest = write_shp_vehicle(entity, roots, args.output)
            else:
                continue
            manifests.append(manifest)
            print(f"[{position}/{total}] generated {entity_id}")
        except Exception as exc:
            issues.append({"entity_id": entity_id, "error": f"{type(exc).__name__}: {exc}"})
            print(f"[{position}/{total}] skipped {entity_id}: {exc}", file=sys.stderr)
    manifests.sort(key=lambda item: str(item.get("entity_id", "")))
    if selected_ids is not None and (args.output / "manifest.json").is_file():
        try:
            existing = json.loads((args.output / "manifest.json").read_text(encoding="utf-8"))
        except Exception:
            existing = []
        merged = {str(item.get("entity_id", "")).casefold(): item for item in existing if isinstance(item, dict)}
        for item in manifests:
            merged[str(item.get("entity_id", "")).casefold()] = item
        manifests = sorted(merged.values(), key=lambda item: str(item.get("entity_id", "")))
    gallery(args.output, manifests)
    (args.output / "manifest.json").write_text(json.dumps(manifests, ensure_ascii=False, indent=2), encoding="utf-8")
    (args.output / "issues.json").write_text(json.dumps(issues, ensure_ascii=False, indent=2), encoding="utf-8")
    (args.output / "catalog.json").write_text(
        json.dumps(
            [{"entity_id": item["entity_id"], "visual_kind": item.get("visual_kind", ""), "category": item.get("category", "")} for item in manifests],
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    print(json.dumps({"generated": len(manifests), "issues": len(issues)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

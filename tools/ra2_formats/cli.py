from __future__ import annotations

import argparse
from pathlib import Path
import json
import math
import shutil
import sys
from typing import Mapping

from PIL import Image

from .godot_writer import (
    AnimationSpec,
    animations_from_config,
    godot_path,
    write_json,
    write_shp_resource,
    write_sprite_frames,
)
from .hva import HvaFile
from .palette import Palette
from .render import RenderSettings, VoxelPart, pack_atlas, render_voxel_parts
from .shp_ts import ShpTsFile
from .vxl import VxlFile


def _load_config(path: Path | None) -> dict:
    if path is None or not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def _project_root(explicit: str | None, output: Path) -> Path:
    if explicit:
        return Path(explicit).resolve()
    cursor = output.resolve()
    for candidate in (cursor, *cursor.parents):
        if (candidate / "project.godot").exists():
            return candidate
    raise ValueError("Could not locate project.godot; pass --project-root")




def _portable_path(path: Path | None, project_root: Path) -> str | None:
    if path is None:
        return None
    try:
        return godot_path(path, project_root)
    except ValueError:
        return path.name


def _portable_palette_source(source: str, project_root: Path) -> str:
    if source.startswith("embedded:"):
        raw = source.removeprefix("embedded:")
        try:
            return "embedded:" + str(_portable_path(Path(raw), project_root))
        except Exception:
            return source
    try:
        candidate = Path(source)
        if candidate.exists():
            portable = _portable_path(candidate, project_root)
            return str(portable)
    except Exception:
        pass
    return source


def _palette_for_shp(palette_path: Path | None, fallback_vxl: Path | None) -> Palette:
    if palette_path is not None and palette_path.exists():
        return Palette.from_file(palette_path)
    if fallback_vxl is not None and fallback_vxl.exists():
        return VxlFile(fallback_vxl).palette
    return Palette.grayscale()


def import_shp(
    source: Path,
    output: Path,
    project_root: Path,
    palette: Palette,
    animation_config: Mapping[str, object] | None = None,
) -> dict:
    output.mkdir(parents=True, exist_ok=True)
    shp = ShpTsFile(source)
    frames = shp.decode_all(palette)
    columns = max(1, min(32, math.ceil(math.sqrt(max(1, len(frames))))))
    atlas, columns = pack_atlas(frames, columns)
    atlas_path = output / "atlas.png"
    atlas.save(atlas_path)
    metadata_path = output / "metadata.json"
    metadata = {
        "format": "shp_ts",
        "source": _portable_path(source, project_root),
        "palette": _portable_palette_source(palette.source, project_root),
        "frame_size": [shp.width, shp.height],
        "frame_count": shp.frame_count,
        "columns": columns,
        "frames": [
            {
                "x": frame.x,
                "y": frame.y,
                "width": frame.width,
                "height": frame.height,
                "flags": frame.flags,
                "data_offset": frame.data_offset,
            }
            for frame in shp.frames
        ],
    }
    write_json(metadata_path, metadata)
    atlas_res = godot_path(atlas_path, project_root)
    metadata_res = godot_path(metadata_path, project_root)
    animations = animations_from_config(animation_config, shp.frame_count)
    frames_path = output / "sprite_frames.tres"
    write_sprite_frames(
        frames_path,
        atlas_res,
        (shp.width, shp.height),
        shp.frame_count,
        columns,
        animations,
    )
    resource_path = output / "shp_resource.tres"
    write_shp_resource(
        resource_path,
        atlas_res,
        (shp.width, shp.height),
        shp.frame_count,
        columns,
        metadata_res,
    )
    return {
        "type": "shp",
        "source": _portable_path(source, project_root),
        "output": godot_path(output, project_root),
        "atlas": godot_path(atlas_path, project_root),
        "sprite_frames": godot_path(frames_path, project_root),
        "resource": godot_path(resource_path, project_root),
        "frame_count": shp.frame_count,
        "frame_size": [shp.width, shp.height],
    }


def _load_part(vxl_path: Path | None, hva_path: Path | None, frame_index: int = 0) -> VoxelPart | None:
    if vxl_path is None or not vxl_path.exists():
        return None
    animation = HvaFile(hva_path) if hva_path is not None and hva_path.exists() else None
    return VoxelPart(VxlFile(vxl_path), animation, frame_index)


def _render_part_set(
    parts: list[VoxelPart],
    output: Path,
    file_stem: str,
    project_root: Path,
    settings: RenderSettings,
    facing_count: int,
) -> dict:
    animation_frame_count = max(
        [part.animation.frame_count if part.animation is not None else 1 for part in parts],
        default=1,
    )
    frames = []
    # Atlas layout: columns are facings, rows are HVA animation frames.
    for animation_frame in range(animation_frame_count):
        for direction in range(facing_count):
            current_parts = [
                VoxelPart(
                    part.model,
                    part.animation,
                    animation_frame % part.animation.frame_count if part.animation is not None and part.animation.frame_count > 0 else 0,
                    part.offset,
                )
                for part in parts
            ]
            frames.append(render_voxel_parts(current_parts, direction, facing_count, settings))
    atlas, columns = pack_atlas(frames, facing_count)
    atlas_path = output / f"{file_stem}_atlas.png"
    atlas.save(atlas_path)
    animations: list[AnimationSpec] = []
    for direction in range(facing_count):
        first_index = direction
        animated_indices = tuple(frame * facing_count + direction for frame in range(animation_frame_count))
        animations.append(AnimationSpec(f"stand_{direction}", (first_index,), 1.0, True))
        animations.append(AnimationSpec(f"idle_{direction}", animated_indices, 8.0, True))
        animations.append(AnimationSpec(f"move_{direction}", animated_indices, 10.0, True))
        animations.append(AnimationSpec(f"attack_{direction}", animated_indices, 12.0, False))
        animations.append(AnimationSpec(f"death_{direction}", (animated_indices[-1],), 1.0, False))
    frames_path = output / f"{file_stem}_frames.tres"
    write_sprite_frames(
        frames_path,
        godot_path(atlas_path, project_root),
        (settings.canvas_width, settings.canvas_height),
        len(frames),
        columns,
        animations,
    )
    return {
        "atlas": godot_path(atlas_path, project_root),
        "sprite_frames": godot_path(frames_path, project_root),
        "hva_frame_count": animation_frame_count,
    }


def import_vxl_group(
    name: str,
    body_vxl: Path,
    output: Path,
    project_root: Path,
    body_hva: Path | None = None,
    turret_vxl: Path | None = None,
    turret_hva: Path | None = None,
    barrel_vxl: Path | None = None,
    barrel_hva: Path | None = None,
    facing_count: int = 8,
    settings: RenderSettings = RenderSettings(),
) -> dict:
    output.mkdir(parents=True, exist_ok=True)
    body = _load_part(body_vxl, body_hva)
    if body is None:
        raise ValueError(f"Missing body VXL: {body_vxl}")
    turret = _load_part(turret_vxl, turret_hva)
    barrel = _load_part(barrel_vxl, barrel_hva)
    body_output = _render_part_set([body], output, "body", project_root, settings, facing_count)
    upper_parts = [part for part in (turret, barrel) if part is not None]
    upper_output = _render_part_set(upper_parts, output, "turret", project_root, settings, facing_count) if upper_parts else None
    combined_output = _render_part_set([body, *upper_parts], output, "combined", project_root, settings, facing_count)
    metadata_path = output / "metadata.json"
    metadata = {
        "format": "vxl_hva",
        "name": name,
        "facing_count": facing_count,
        "render_settings": settings.__dict__,
        "body": _portable_path(body_vxl, project_root),
        "body_hva": _portable_path(body_hva, project_root),
        "turret": _portable_path(turret_vxl, project_root),
        "turret_hva": _portable_path(turret_hva, project_root),
        "barrel": _portable_path(barrel_vxl, project_root),
        "barrel_hva": _portable_path(barrel_hva, project_root),
        "body_sections": [
            {"name": section.name, "size": list(section.size), "voxel_count": len(section.voxels)}
            for section in body.model.sections
        ],
    }
    write_json(metadata_path, metadata)
    return {
        "type": "vxl",
        "name": name,
        "output": godot_path(output, project_root),
        "body": body_output,
        "turret": upper_output,
        "combined": combined_output,
        "metadata": godot_path(metadata_path, project_root),
    }


def import_wav(source: Path, output: Path, project_root: Path) -> dict:
    output.mkdir(parents=True, exist_ok=True)
    destination = output / source.name
    shutil.copy2(source, destination)
    return {
        "type": "wav",
        "source": _portable_path(source, project_root),
        "output": godot_path(destination, project_root),
        "note": "Godot native WAV import (PCM or IMA ADPCM when supported by the engine)",
    }


def scan_directory(source: Path, output: Path, project_root: Path, config: dict) -> list[dict]:
    output.mkdir(parents=True, exist_ok=True)
    entries: list[dict] = []
    default_palette = config.get("default_palette")
    palette_path = source / default_palette if isinstance(default_palette, str) else None
    fallback_vxl_name = config.get("fallback_palette_vxl")
    fallback_vxl = source / fallback_vxl_name if isinstance(fallback_vxl_name, str) else None
    palette = _palette_for_shp(palette_path, fallback_vxl)

    shp_config = config.get("shp", {}) if isinstance(config.get("shp", {}), Mapping) else {}
    for shp_path in sorted(source.glob("*.shp")):
        item_config = shp_config.get(shp_path.name, {}) if isinstance(shp_config, Mapping) else {}
        if not isinstance(item_config, Mapping):
            item_config = {}
        item_palette = palette
        item_palette_name = item_config.get("palette")
        if isinstance(item_palette_name, str) and (source / item_palette_name).exists():
            item_palette = Palette.from_file(source / item_palette_name)
        entries.append(
            import_shp(
                shp_path,
                output / shp_path.stem.lower(),
                project_root,
                item_palette,
                item_config.get("animations") if isinstance(item_config.get("animations"), Mapping) else None,
            )
        )

    declared_groups = config.get("vxl_groups", {}) if isinstance(config.get("vxl_groups", {}), Mapping) else {}
    consumed: set[Path] = set()
    for group_name, raw in declared_groups.items():
        if not isinstance(raw, Mapping):
            continue
        def source_file(key: str) -> Path | None:
            value = raw.get(key)
            return source / value if isinstance(value, str) and value else None
        body_path = source_file("body")
        if body_path is None or not body_path.exists():
            continue
        settings_raw = raw.get("render", {}) if isinstance(raw.get("render"), Mapping) else {}
        settings = RenderSettings(
            canvas_width=int(settings_raw.get("canvas_width", 160)),
            canvas_height=int(settings_raw.get("canvas_height", 120)),
            pixel_size=int(settings_raw.get("pixel_size", 2)),
            horizontal_scale=float(settings_raw.get("horizontal_scale", 0.90)),
            vertical_scale=float(settings_raw.get("vertical_scale", 0.45)),
            height_scale=float(settings_raw.get("height_scale", 0.90)),
            anchor_x=float(settings_raw.get("anchor_x", 0.50)),
            anchor_y=float(settings_raw.get("anchor_y", 0.64)),
            yaw_offset_degrees=float(settings_raw.get("yaw_offset_degrees", 0.0)),
        )
        paths = [source_file(key) for key in ("body", "body_hva", "turret", "turret_hva", "barrel", "barrel_hva")]
        consumed.update(path.resolve() for path in paths if path is not None and path.exists() and path.suffix.lower() == ".vxl")
        entries.append(
            import_vxl_group(
                str(group_name),
                body_path,
                output / str(group_name).lower(),
                project_root,
                source_file("body_hva"),
                source_file("turret"),
                source_file("turret_hva"),
                source_file("barrel"),
                source_file("barrel_hva"),
                int(raw.get("facings", 8)),
                settings,
            )
        )

    # Undeclared standalone voxels still receive a usable body conversion.
    for vxl_path in sorted(source.glob("*.vxl")):
        if vxl_path.resolve() in consumed:
            continue
        stem = vxl_path.stem.lower()
        hva_path = source / f"{vxl_path.stem}.hva"
        entries.append(
            import_vxl_group(
                stem,
                vxl_path,
                output / stem,
                project_root,
                hva_path if hva_path.exists() else None,
            )
        )

    for wav_path in sorted(source.glob("*.wav")):
        entries.append(import_wav(wav_path, output / "audio", project_root))

    write_json(output / "manifest.json", {"version": 1, "assets": entries})
    return entries


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Convert RA2/YR SHP, VXL/HVA and WAV assets for Godot")
    parser.add_argument("--project-root", help="Godot project root; auto-detected from output when omitted")
    subparsers = parser.add_subparsers(dest="command", required=True)

    scan = subparsers.add_parser("scan", help="Import all supported assets from a source directory")
    scan.add_argument("source")
    scan.add_argument("output")
    scan.add_argument("--config")

    shp = subparsers.add_parser("shp", help="Import one SHP(TS) file")
    shp.add_argument("source")
    shp.add_argument("output")
    shp.add_argument("--palette")
    shp.add_argument("--fallback-vxl")
    shp.add_argument("--animation-config")

    vxl = subparsers.add_parser("vxl", help="Import one VXL body and optional turret/barrel group")
    vxl.add_argument("name")
    vxl.add_argument("body")
    vxl.add_argument("output")
    vxl.add_argument("--body-hva")
    vxl.add_argument("--turret")
    vxl.add_argument("--turret-hva")
    vxl.add_argument("--barrel")
    vxl.add_argument("--barrel-hva")
    vxl.add_argument("--facings", type=int, default=8)
    vxl.add_argument("--canvas-width", type=int, default=160)
    vxl.add_argument("--canvas-height", type=int, default=120)
    vxl.add_argument("--pixel-size", type=int, default=2)

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command == "scan":
            source = Path(args.source).resolve()
            output = Path(args.output).resolve()
            root = _project_root(args.project_root, output)
            config_path = Path(args.config).resolve() if args.config else source / "ra2_import.json"
            entries = scan_directory(source, output, root, _load_config(config_path))
            print(json.dumps({"ok": True, "count": len(entries), "manifest": str(output / "manifest.json")}, ensure_ascii=False))
            return 0
        if args.command == "shp":
            source = Path(args.source).resolve()
            output = Path(args.output).resolve()
            root = _project_root(args.project_root, output)
            animation_config = _load_config(Path(args.animation_config)) if args.animation_config else None
            result = import_shp(
                source,
                output,
                root,
                _palette_for_shp(Path(args.palette) if args.palette else None, Path(args.fallback_vxl) if args.fallback_vxl else None),
                animation_config,
            )
            print(json.dumps({"ok": True, "asset": result}, ensure_ascii=False))
            return 0
        if args.command == "vxl":
            output = Path(args.output).resolve()
            root = _project_root(args.project_root, output)
            result = import_vxl_group(
                args.name,
                Path(args.body).resolve(),
                output,
                root,
                Path(args.body_hva).resolve() if args.body_hva else None,
                Path(args.turret).resolve() if args.turret else None,
                Path(args.turret_hva).resolve() if args.turret_hva else None,
                Path(args.barrel).resolve() if args.barrel else None,
                Path(args.barrel_hva).resolve() if args.barrel_hva else None,
                args.facings,
                RenderSettings(args.canvas_width, args.canvas_height, args.pixel_size),
            )
            print(json.dumps({"ok": True, "asset": result}, ensure_ascii=False))
            return 0
    except Exception as error:
        print(json.dumps({"ok": False, "error": str(error)}, ensure_ascii=False), file=sys.stderr)
        return 1
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

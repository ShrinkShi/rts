#!/usr/bin/env python3
"""Build a Godot runtime bundle from a canonical RA2/YR map and theater files.

The source .map/.mpr/.yrm remains the editable source. This builder emits disposable
runtime caches: exact IsoMapPack5 cell records, a precomposed terrain PNG, overlay
records, and a correctly-paletted TIB/GEM/TIBTRE texture atlas.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import math
import struct
import zlib
from dataclasses import dataclass
from pathlib import Path

from ra2_ini import RA2MapError
from ra2_map_enrichment import enrich_imported_map
from ra2_map_importer import import_map
from ra2_palette import Palette, load_palette
from ra2_shp_ts import ShpTsError, ShpTsFile, indexed_to_rgba
from ra2_theater import ArchiveStack, CaseInsensitiveZip, TheaterCatalog
from ra2_tmp import render_rgba

CELL_STRUCT = struct.Struct("<HHBBB")
RESOURCE_STRUCT = struct.Struct("<HHHBB")
CELL_WIDTH = 60
CELL_HEIGHT = 30
HEIGHT_STEP = 15
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
ORE_ID_FIRST = 105
ORE_ID_LAST = 124
GEM_ID_FIRST = 28
GEM_ID_LAST = 39


@dataclass(frozen=True)
class RenderedTile:
    width: int
    height: int
    origin_x: int
    origin_y: int
    rgba: bytes


@dataclass(frozen=True)
class AtlasAsset:
    asset_id: str
    width: int
    height: int
    rgba: bytes
    palette_name: str
    source_name: str
    frame: int


def _png_chunk(kind: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload))
        + kind
        + payload
        + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
    )


def encode_png_rgba(width: int, height: int, rgba: bytes, *, level: int = 9) -> bytes:
    if width <= 0 or height <= 0:
        raise RA2MapError(f"PNG dimensions must be positive, got {width}x{height}")
    expected = width * height * 4
    if len(rgba) != expected:
        raise RA2MapError(f"RGBA length mismatch: expected {expected}, got {len(rgba)}")
    scanlines = bytearray()
    stride = width * 4
    for row in range(height):
        scanlines.append(0)
        start = row * stride
        scanlines.extend(rgba[start : start + stride])
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (
        PNG_SIGNATURE
        + _png_chunk(b"IHDR", header)
        + _png_chunk(b"IDAT", zlib.compress(bytes(scanlines), level))
        + _png_chunk(b"IEND", b"")
    )


def alpha_blit(
    destination: bytearray,
    destination_width: int,
    destination_height: int,
    source: bytes,
    source_width: int,
    source_height: int,
    left: int,
    top: int,
) -> None:
    if len(source) != source_width * source_height * 4:
        raise RA2MapError("Source RGBA length does not match its dimensions")
    for source_y in range(source_height):
        destination_y = top + source_y
        if destination_y < 0 or destination_y >= destination_height:
            continue
        for source_x in range(source_width):
            destination_x = left + source_x
            if destination_x < 0 or destination_x >= destination_width:
                continue
            source_offset = (source_y * source_width + source_x) * 4
            alpha = source[source_offset + 3]
            if alpha == 0:
                continue
            destination_offset = (
                destination_y * destination_width + destination_x
            ) * 4
            if alpha == 255:
                destination[destination_offset : destination_offset + 4] = source[
                    source_offset : source_offset + 4
                ]
                continue
            inverse = 255 - alpha
            for channel in range(3):
                destination[destination_offset + channel] = (
                    source[source_offset + channel] * alpha
                    + destination[destination_offset + channel] * inverse
                ) // 255
            destination[destination_offset + 3] = min(
                255,
                alpha + destination[destination_offset + 3] * inverse // 255,
            )


def write_base64_chunks(
    payload: bytes,
    output_dir: Path,
    stem: str,
    *,
    chunk_characters: int = 900_000,
) -> int:
    if chunk_characters < 4:
        raise RA2MapError("Base64 chunk size must be at least four characters")
    chunk_characters -= chunk_characters % 4
    encoded = base64.b64encode(payload).decode("ascii")
    count = max(1, math.ceil(len(encoded) / chunk_characters))
    output_dir.mkdir(parents=True, exist_ok=True)
    for stale in output_dir.glob(f"{stem}_*.b64"):
        stale.unlink()
    for index in range(count):
        part = encoded[index * chunk_characters : (index + 1) * chunk_characters]
        (output_dir / f"{stem}_{index:02d}.b64").write_text(
            part + "\n", encoding="ascii"
        )
    return count


def _project_cell(
    rx: int, ry: int, source_width: int, level: int, baseline: int
) -> tuple[int, int]:
    center_x = (rx - ry + source_width - 1) * (CELL_WIDTH // 2) + CELL_WIDTH // 2
    center_y = (
        (rx + ry - source_width - 1) * (CELL_HEIGHT // 2)
        + baseline
        - level * HEIGHT_STEP
        + CELL_HEIGHT // 2
    )
    return center_x, center_y


def _terrain_render_cache(
    imported: dict[str, object],
    palette: Palette,
    catalog: TheaterCatalog,
    archives: ArchiveStack,
) -> dict[tuple[int, int], RenderedTile]:
    cache: dict[tuple[int, int], RenderedTile] = {}
    tmp_cache: dict[int, object] = {}
    for raw_tile in imported.get("tiles", []):
        tile = dict(raw_tile)
        tile_index = int(tile["tile_index"])
        sub_tile = int(tile["sub_tile"])
        key = (tile_index, sub_tile)
        if key in cache:
            continue
        tmp = tmp_cache.get(tile_index)
        if tmp is None:
            tmp = catalog.load_tmp(tile_index, archives)
            tmp_cache[tile_index] = tmp
        width, height, origin_x, origin_y, rgba = render_rgba(
            tmp, sub_tile, palette, include_extra=True
        )
        cache[key] = RenderedTile(width, height, origin_x, origin_y, rgba)
    return cache


def render_terrain(
    imported: dict[str, object],
    palette: Palette,
    catalog: TheaterCatalog,
    archives: ArchiveStack,
) -> tuple[int, int, int, int, bytes]:
    map_definition = dict(imported["map"])
    source_width = int(map_definition["width"])
    baseline = source_width * (CELL_HEIGHT // 2) + 180
    render_cache = _terrain_render_cache(imported, palette, catalog, archives)

    placements: list[tuple[int, int, int, int, RenderedTile]] = []
    minimum_x = 2**31 - 1
    minimum_y = 2**31 - 1
    maximum_x = -(2**31)
    maximum_y = -(2**31)
    for raw_tile in imported.get("tiles", []):
        tile = dict(raw_tile)
        rx = int(tile["rx"])
        ry = int(tile["ry"])
        level = int(tile["level"])
        rendered = render_cache[(int(tile["tile_index"]), int(tile["sub_tile"]))]
        center_x, center_y = _project_cell(rx, ry, source_width, level, baseline)
        left = center_x - CELL_WIDTH // 2 + rendered.origin_x
        top = center_y - CELL_HEIGHT // 2 + rendered.origin_y
        minimum_x = min(minimum_x, left)
        minimum_y = min(minimum_y, top)
        maximum_x = max(maximum_x, left + rendered.width)
        maximum_y = max(maximum_y, top + rendered.height)
        placements.append((center_y, center_x, left, top, rendered))

    if not placements:
        raise RA2MapError("Map contains no renderable IsoMapPack5 cells")
    margin = 4
    minimum_x -= margin
    minimum_y -= margin
    maximum_x += margin
    maximum_y += margin
    width = maximum_x - minimum_x
    height = maximum_y - minimum_y
    if width * height > 120_000_000:
        raise RA2MapError(f"Rendered terrain canvas is unreasonably large: {width}x{height}")

    canvas = bytearray(width * height * 4)
    for _center_y, _center_x, left, top, rendered in sorted(
        placements, key=lambda item: (item[0], item[1])
    ):
        alpha_blit(
            canvas,
            width,
            height,
            rendered.rgba,
            rendered.width,
            rendered.height,
            left - minimum_x,
            top - minimum_y,
        )
    return width, height, minimum_x, minimum_y, bytes(canvas)


def _read_shp_asset(
    archive: ArchiveStack,
    filename: str,
    palette: Palette,
    palette_name: str,
    asset_prefix: str,
    frame_limit: int,
) -> list[AtlasAsset]:
    if not archive.has(filename):
        return []
    try:
        shp = ShpTsFile.from_bytes(archive.read(filename), source_name=filename)
    except ShpTsError as exc:
        raise RA2MapError(str(exc)) from exc
    assets: list[AtlasAsset] = []
    for frame in shp.frames[:frame_limit]:
        assets.append(
            AtlasAsset(
                asset_id=f"{asset_prefix}{frame.index:02d}",
                width=shp.width,
                height=shp.height,
                rgba=indexed_to_rgba(frame.pixels, shp.width, shp.height, palette),
                palette_name=palette_name,
                source_name=filename,
                frame=frame.index,
            )
        )
    return assets


def build_resource_atlas(
    archives: ArchiveStack,
    temperat_palette: Palette,
    unittem_palette: Palette,
) -> tuple[int, int, bytes, dict[str, object]]:
    assets: list[AtlasAsset] = []
    for number in range(1, 21):
        filename = f"tib{number:02d}.tem"
        loaded = _read_shp_asset(
            archives,
            filename,
            temperat_palette,
            "temperat.pal",
            f"tib_{number:02d}_",
            12,
        )
        if not loaded:
            raise RA2MapError(f"Required ore overlay is missing: {filename}")
        assets.extend(loaded)
    for number in range(1, 13):
        filename = f"gem{number:02d}.tem"
        assets.extend(
            _read_shp_asset(
                archives,
                filename,
                temperat_palette,
                "temperat.pal",
                f"gem_{number:02d}_",
                12,
            )
        )
    pillar_assets = _read_shp_asset(
        archives,
        "tibtre01.tem",
        unittem_palette,
        "unittem.pal",
        "tibtre01_",
        11,
    )
    if not pillar_assets:
        raise RA2MapError("Required ore pillar overlay is missing: tibtre01.tem")
    assets.extend(pillar_assets)

    slot_width = max(asset.width for asset in assets) + 2
    slot_height = max(asset.height for asset in assets) + 2
    columns = max(1, min(len(assets), 2048 // slot_width))
    rows = math.ceil(len(assets) / columns)
    width = columns * slot_width
    height = rows * slot_height
    canvas = bytearray(width * height * 4)
    manifest_assets: dict[str, object] = {}
    for index, asset in enumerate(assets):
        column = index % columns
        row = index // columns
        left = column * slot_width + (slot_width - asset.width) // 2
        top = row * slot_height + slot_height - asset.height - 1
        alpha_blit(
            canvas,
            width,
            height,
            asset.rgba,
            asset.width,
            asset.height,
            left,
            top,
        )
        manifest_assets[asset.asset_id] = {
            "region": [left, top, asset.width, asset.height],
            "anchor": [asset.width / 2.0, asset.height - 1.0],
            "palette": asset.palette_name,
            "source": asset.source_name,
            "frame": asset.frame,
        }
    return width, height, bytes(canvas), manifest_assets


def encode_cell_records(imported: dict[str, object]) -> bytes:
    output = bytearray()
    for raw_tile in imported.get("tiles", []):
        tile = dict(raw_tile)
        theater = dict(tile.get("theater", {}))
        output += CELL_STRUCT.pack(
            int(tile["rx"]),
            int(tile["ry"]),
            int(tile["level"]),
            int(theater.get("terrain_type", 0)),
            int(theater.get("ramp_type", 0)),
        )
    return bytes(output)


def overlay_kind(overlay_id: int) -> int:
    if ORE_ID_FIRST <= overlay_id <= ORE_ID_LAST:
        return 1
    if GEM_ID_FIRST <= overlay_id <= GEM_ID_LAST:
        return 2
    return 0


def encode_resource_records(imported: dict[str, object]) -> tuple[bytes, int]:
    output = bytearray()
    count = 0
    for raw_overlay in imported.get("overlays", []):
        overlay = dict(raw_overlay)
        overlay_id = int(overlay["overlay_id"])
        kind = overlay_kind(overlay_id)
        if kind == 0:
            continue
        output += RESOURCE_STRUCT.pack(
            int(overlay["rx"]),
            int(overlay["ry"]),
            overlay_id,
            int(overlay["frame"]),
            kind,
        )
        count += 1
    return bytes(output), count


def _positions(imported: dict[str, object]) -> list[list[int]]:
    result: list[list[int]] = []
    for raw in sorted(imported.get("waypoints", []), key=lambda value: int(value["id"])):
        identifier = int(raw["id"])
        if 0 <= identifier <= 7:
            result.append([int(raw["rx"]), int(raw["ry"])])
    return result


def _terrain_objects(imported: dict[str, object], prefix: str) -> list[dict[str, object]]:
    result: list[dict[str, object]] = []
    for raw in imported.get("terrain", []):
        object_type = str(raw.get("type", ""))
        if object_type.upper().startswith(prefix.upper()):
            result.append(
                {
                    "cell": [int(raw["rx"]), int(raw["ry"])],
                    "type": object_type,
                }
            )
    return result


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _write_json(path: Path, data: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def _res_template(relative_dir: str, stem: str) -> str:
    return f"res://{relative_dir.strip('/')}/{stem}_%02d.b64"


def build_bundle(arguments: argparse.Namespace) -> dict[str, object]:
    source_map: Path = arguments.source_map
    theater_ini: Path = arguments.theater_ini
    theater_paths: list[Path] = [arguments.isotemp]
    if arguments.temperat is not None:
        theater_paths.append(arguments.temperat)

    imported = import_map(source_map)
    catalog = TheaterCatalog.from_path(theater_ini, arguments.theater_extension)
    archives = ArchiveStack(CaseInsensitiveZip(path) for path in theater_paths)
    try:
        imported = enrich_imported_map(imported, catalog, archives)
        isotem_palette = load_palette(arguments.isotem_palette)
        temperat_palette = load_palette(arguments.temperat_palette)
        unittem_palette = load_palette(arguments.unittem_palette)

        terrain_width, terrain_height, crop_x, crop_y, terrain_rgba = render_terrain(
            imported, isotem_palette, catalog, archives
        )
        terrain_png = encode_png_rgba(terrain_width, terrain_height, terrain_rgba)
        resource_width, resource_height, resource_rgba, resource_assets = (
            build_resource_atlas(archives, temperat_palette, unittem_palette)
        )
        resource_png = encode_png_rgba(resource_width, resource_height, resource_rgba)
    finally:
        archives.close()

    project_root: Path = arguments.project_root.resolve()
    map_output_dir: Path = project_root / arguments.map_output_dir
    embedded_output_dir: Path = project_root / arguments.embedded_output_dir
    map_output_dir.mkdir(parents=True, exist_ok=True)
    embedded_output_dir.mkdir(parents=True, exist_ok=True)
    map_stem = arguments.map_stem or source_map.stem.lower()

    cell_payload = encode_cell_records(imported)
    cell_chunk_count = write_base64_chunks(
        cell_payload, map_output_dir, f"{map_stem}_cells"
    )
    terrain_chunk_count = write_base64_chunks(
        terrain_png, map_output_dir, f"{map_stem}_terrain"
    )
    resource_chunk_count = write_base64_chunks(
        resource_png, embedded_output_dir, "temperate_resources_v2"
    )
    resource_payload, resource_count = encode_resource_records(imported)

    source_width = int(imported["map"]["width"])
    source_height = int(imported["map"]["height"])
    levels = [int(tile["level"]) for tile in imported["tiles"]]
    runtime_manifest = {
        "format": "ra2-godot-runtime-v2",
        "source_map": source_map.name,
        "source_name": source_map.name,
        "map_name": str(imported.get("basic", {}).get("Name", source_map.stem)),
        "theater": str(imported["map"]["theater"]),
        "source_size": [source_width, source_height],
        "logical_size": [source_width * 2, source_height * 2],
        "local_size": imported["map"]["local_size"],
        "cell_size": [CELL_WIDTH, CELL_HEIGHT],
        "cell_height": HEIGHT_STEP,
        "max_height": max(levels, default=0),
        "baseline": source_width * (CELL_HEIGHT // 2) + 180,
        "render_crop": [crop_x, crop_y],
        "render_size": [terrain_width, terrain_height],
        "background": {
            "chunk_template": _res_template(
                arguments.map_output_dir, f"{map_stem}_terrain"
            ),
            "chunk_count": terrain_chunk_count,
            "format": "png",
            "sha256": hashlib.sha256(terrain_png).hexdigest(),
        },
        "cells": {
            "chunk_template": _res_template(
                arguments.map_output_dir, f"{map_stem}_cells"
            ),
            "chunk_count": cell_chunk_count,
            "record_format": "<HHBBB",
            "record_size": CELL_STRUCT.size,
            "count": len(imported["tiles"]),
            "sha256": hashlib.sha256(cell_payload).hexdigest(),
        },
        "resources": {
            "encoded": base64.b64encode(resource_payload).decode("ascii"),
            "record_format": "<HHHBB",
            "record_size": RESOURCE_STRUCT.size,
            "count": resource_count,
        },
        "positions": _positions(imported),
        "trees": _terrain_objects(imported, "TREE"),
        "ore_pillars": _terrain_objects(imported, "TIBTRE"),
        "provenance": {
            "canonical_map": {"name": source_map.name, "sha256": _sha256(source_map)},
            "theater_ini": {"name": theater_ini.name, "sha256": _sha256(theater_ini)},
            "theater_archives": [
                {"name": path.name, "sha256": _sha256(path)} for path in theater_paths
            ],
            "palettes": {
                "terrain": {"name": arguments.isotem_palette.name, "sha256": _sha256(arguments.isotem_palette)},
                "resources": {"name": arguments.temperat_palette.name, "sha256": _sha256(arguments.temperat_palette)},
                "pillar": {"name": arguments.unittem_palette.name, "sha256": _sha256(arguments.unittem_palette)},
            },
        },
    }
    runtime_path = map_output_dir / f"{map_stem}_runtime.json"
    _write_json(runtime_path, runtime_manifest)

    resource_manifest = {
        "format": "ra2-resource-atlas-v2",
        "image_format": "png",
        "chunk_template": _res_template(
            arguments.embedded_output_dir, "temperate_resources_v2"
        ),
        "chunk_count": resource_chunk_count,
        "size": [resource_width, resource_height],
        "sha256": hashlib.sha256(resource_png).hexdigest(),
        "assets": resource_assets,
        "palette_rules": {
            "TIB*.TEM": "temperat.pal",
            "GEM*.TEM": "temperat.pal",
            "TIBTRE*.TEM": "unittem.pal",
        },
    }
    _write_json(
        embedded_output_dir / "temperate_resources_v2.json", resource_manifest
    )

    catalog_path = project_root / arguments.map_catalog
    catalog_data: dict[str, object] = {}
    if catalog_path.exists():
        parsed = json.loads(catalog_path.read_text(encoding="utf-8"))
        if not isinstance(parsed, dict):
            raise RA2MapError(f"Map catalog must be a JSON object: {catalog_path}")
        catalog_data = parsed
    relative_runtime = runtime_path.relative_to(project_root).as_posix()
    positions = runtime_manifest["positions"]
    catalog_data[arguments.map_id] = {
        "name": arguments.map_name or runtime_manifest["map_name"],
        "description": "由原始 RA2/YR 地图、IsoMapPack5、Temperat.ini 与 TMP 构建的 60×30 等距运行时地图。",
        "format": "ra2_runtime_v2",
        "runtime_manifest": f"res://{relative_runtime}",
        "canonical_source": source_map.name,
        "size": runtime_manifest["logical_size"],
        "positions": positions,
        "tree_density": 0.0,
        "force_disable_fog": bool(arguments.force_disable_fog),
    }
    _write_json(catalog_path, catalog_data)

    return {
        "runtime_manifest": runtime_path,
        "resource_manifest": embedded_output_dir / "temperate_resources_v2.json",
        "terrain_size": [terrain_width, terrain_height],
        "cell_count": len(imported["tiles"]),
        "resource_count": resource_count,
        "spawn_count": len(positions),
    }


def create_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Build Godot RA2 runtime map and correctly-paletted resource bundles"
    )
    parser.add_argument("source_map", type=Path)
    parser.add_argument("--theater-ini", type=Path, required=True)
    parser.add_argument("--isotemp", type=Path, required=True)
    parser.add_argument("--temperat", type=Path)
    parser.add_argument("--isotem-palette", type=Path, required=True)
    parser.add_argument("--temperat-palette", type=Path, required=True)
    parser.add_argument("--unittem-palette", type=Path, required=True)
    parser.add_argument("--theater-extension", default=".tem")
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    parser.add_argument("--map-output-dir", default="data/ra2_maps")
    parser.add_argument("--embedded-output-dir", default="data/ra2_embedded")
    parser.add_argument("--map-catalog", default="data/maps_ra2.json")
    parser.add_argument("--map-id", default="ra2_mymap1")
    parser.add_argument("--map-name")
    parser.add_argument("--map-stem")
    parser.add_argument("--force-disable-fog", action="store_true")
    return parser


def main() -> int:
    parser = create_parser()
    arguments = parser.parse_args()
    try:
        result = build_bundle(arguments)
    except (OSError, ValueError, json.JSONDecodeError, RA2MapError) as exc:
        parser.error(str(exc))
    print(
        "Built RA2 runtime bundle: "
        f"{result['cell_count']} cells, {result['resource_count']} resource overlays, "
        f"terrain {result['terrain_size'][0]}x{result['terrain_size'][1]}"
    )
    print(f"Runtime manifest: {result['runtime_manifest']}")
    print(f"Resource manifest: {result['resource_manifest']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

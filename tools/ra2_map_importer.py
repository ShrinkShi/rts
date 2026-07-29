#!/usr/bin/env python3
"""Import RA2/YR .map/.mpr/.yrm files into disposable runtime JSON caches.

The original map remains the canonical editable source. This tool does not
rewrite the map and never pretends the JSON cache is Final Alert 2 compatible.
"""
from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path
from typing import Iterable

from ra2_ini import IniDocument, RA2MapError, decode_section, section_dict
from ra2_pack_codecs import (
    ISO_TILE_SIZE,
    ISO_TILE_STRUCT,
    OVERLAY_DIMENSION,
    decode_format5_blocks,
)

SUPPORTED_EXTENSIONS = {".map", ".mpr", ".yrm"}


def parse_quad(value: str, label: str) -> list[int]:
    try:
        result = [int(part.strip()) for part in value.split(",")]
    except ValueError as exc:
        raise RA2MapError(f"Invalid {label}: {value!r}") from exc
    if len(result) != 4:
        raise RA2MapError(f"Invalid {label}: {value!r}")
    return result


def parse_iso_tiles(document: IniDocument, width: int, height: int) -> list[dict[str, int]]:
    encoded = decode_section(document, "IsoMapPack5")
    if not encoded:
        raise RA2MapError("[IsoMapPack5] is missing or empty")
    maximum_records = (2 * width - 1) * height
    maximum_size = maximum_records * ISO_TILE_SIZE + 4
    decoded = decode_format5_blocks(encoded)
    if len(decoded) < 4 or (len(decoded) - 4) % ISO_TILE_SIZE != 0:
        raise RA2MapError(
            f"IsoMapPack5 decoded length is invalid: {len(decoded)} bytes"
        )
    if len(decoded) > maximum_size:
        raise RA2MapError(
            f"IsoMapPack5 contains too many cells: {len(decoded)} > {maximum_size}"
        )
    if decoded[-4:] != b"\x00\x00\x00\x00":
        raise RA2MapError("IsoMapPack5 is missing its four-byte terminator")

    tiles: list[dict[str, int]] = []
    for offset in range(0, len(decoded) - 4, ISO_TILE_SIZE):
        rx, ry, tile_index, sub_tile, level, ice_growth = ISO_TILE_STRUCT.unpack_from(
            decoded, offset
        )
        dx = rx - ry + width - 1
        dy = rx + ry - width - 1
        tiles.append(
            {
                "rx": rx,
                "ry": ry,
                "dx": dx,
                "dy": dy,
                "tile_index": max(0, tile_index),
                "sub_tile": sub_tile,
                "level": level,
                "ice_growth": ice_growth,
            }
        )
    return tiles


def parse_overlays(document: IniDocument, new_ini_format: int) -> list[dict[str, int]]:
    overlay_encoded = decode_section(document, "OverlayPack")
    data_encoded = decode_section(document, "OverlayDataPack")
    if not overlay_encoded and not data_encoded:
        return []
    if not overlay_encoded or not data_encoded:
        raise RA2MapError("OverlayPack and OverlayDataPack must either both exist or both be absent")

    cell_count = OVERLAY_DIMENSION * OVERLAY_DIMENSION
    extended = new_ini_format >= 5
    overlay_bytes = decode_format5_blocks(
        overlay_encoded,
        expected_size=cell_count * (2 if extended else 1),
        compression_format=80,
    )
    frame_bytes = decode_format5_blocks(
        data_encoded,
        expected_size=cell_count,
        compression_format=80,
    )
    empty_id = 0xFFFF if extended else 0xFF
    result: list[dict[str, int]] = []
    for index in range(cell_count):
        overlay_id = (
            struct.unpack_from("<H", overlay_bytes, index * 2)[0]
            if extended
            else overlay_bytes[index]
        )
        if overlay_id == empty_id:
            continue
        result.append(
            {
                "rx": index % OVERLAY_DIMENSION,
                "ry": index // OVERLAY_DIMENSION,
                "overlay_id": overlay_id,
                "frame": frame_bytes[index],
            }
        )
    return result


def parse_numeric_object_section(
    document: IniDocument,
    section: str,
    field_names: Iterable[str],
) -> list[dict[str, object]]:
    names = list(field_names)
    result: list[dict[str, object]] = []
    for entry in document.entries(section):
        values = [part.strip() for part in entry.value.split(",")]
        item: dict[str, object] = {
            "index": entry.key,
            "raw": entry.value,
            "field_count": len(values),
        }
        for field_index, field_name in enumerate(names):
            if field_index < len(values):
                item[field_name] = values[field_index]
        result.append(item)
    return result


def parse_waypoints(document: IniDocument) -> list[dict[str, int]]:
    result: list[dict[str, int]] = []
    for entry in document.entries("Waypoints"):
        try:
            identifier = int(entry.key)
            packed = int(entry.value)
        except ValueError:
            continue
        result.append({"id": identifier, "rx": packed % 1000, "ry": packed // 1000})
    return result


def parse_terrain(document: IniDocument) -> list[dict[str, object]]:
    result: list[dict[str, object]] = []
    for entry in document.entries("Terrain"):
        try:
            packed = int(entry.key)
        except ValueError:
            continue
        result.append({"rx": packed % 1000, "ry": packed // 1000, "type": entry.value})
    return result


def import_map(source_path: Path) -> dict[str, object]:
    if source_path.suffix.lower() not in SUPPORTED_EXTENSIONS:
        raise RA2MapError(
            f"Unsupported map extension {source_path.suffix!r}; expected .map, .mpr or .yrm"
        )
    document = IniDocument.from_path(source_path)
    size_value = document.value("Map", "Size")
    local_size_value = document.value("Map", "LocalSize")
    theater = document.value("Map", "Theater")
    if not size_value or not local_size_value or not theater:
        raise RA2MapError("[Map] must define Size, LocalSize and Theater")
    size = parse_quad(size_value, "[Map] Size")
    local_size = parse_quad(local_size_value, "[Map] LocalSize")
    width, height = size[2], size[3]
    if width <= 0 or height <= 0:
        raise RA2MapError(f"Invalid map dimensions: {width}x{height}")
    try:
        new_ini_format = int(document.value("Basic", "NewINIFormat", "0") or 0)
    except ValueError as exc:
        raise RA2MapError("[Basic] NewINIFormat must be an integer") from exc

    return {
        "format": "ra2yr-map-cache-v1",
        "source": source_path.name,
        "source_extension": source_path.suffix.lower(),
        "source_encoding": document.source_encoding,
        "canonical_source_required": True,
        "map": {
            "size": size,
            "local_size": local_size,
            "width": width,
            "height": height,
            "theater": theater.upper(),
            "new_ini_format": new_ini_format,
        },
        "basic": section_dict(document, "Basic"),
        "tiles": parse_iso_tiles(document, width, height),
        "overlays": parse_overlays(document, new_ini_format),
        "waypoints": parse_waypoints(document),
        "terrain": parse_terrain(document),
        "structures": parse_numeric_object_section(
            document,
            "Structures",
            ["owner", "type", "health", "rx", "ry", "facing", "tag"],
        ),
        "units": parse_numeric_object_section(
            document,
            "Units",
            ["owner", "type", "health", "rx", "ry", "facing", "mission", "tag", "veterancy"],
        ),
        "infantry": parse_numeric_object_section(
            document,
            "Infantry",
            ["owner", "type", "health", "rx", "ry", "sub_cell", "mission", "facing", "tag", "veterancy"],
        ),
        "aircraft": parse_numeric_object_section(
            document,
            "Aircraft",
            ["owner", "type", "health", "rx", "ry", "facing", "mission", "tag", "veterancy"],
        ),
        "smudges": parse_numeric_object_section(
            document, "Smudge", ["type", "rx", "ry", "unknown"]
        ),
        "lighting": section_dict(document, "Lighting"),
        "preserved_sections": [name for name in document.sections if name],
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Import an RA2/YR .map/.mpr/.yrm file into a disposable runtime JSON cache"
    )
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path, nargs="?")
    parser.add_argument("--indent", type=int, default=2)
    arguments = parser.parse_args()
    output_path = arguments.output or arguments.source.with_suffix(
        arguments.source.suffix + ".runtime.json"
    )
    try:
        imported = import_map(arguments.source)
    except (OSError, RA2MapError) as exc:
        parser.error(str(exc))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(imported, ensure_ascii=False, indent=arguments.indent), encoding="utf-8"
    )
    print(
        f"Imported {arguments.source}: {len(imported['tiles'])} tiles, "
        f"{len(imported['overlays'])} overlays -> {output_path}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Convert RA2/YR theater overlay resources into transparent PNG files.

Expected temperate source files:
- TIB01.TEM .. TIB20.TEM (ore)
- GEM01.TEM .. GEM12.TEM (gems)
- ISOTEM.PAL

The .TEM overlay files use the SHP(TS) frame layout. This script reuses the
validated SHP decoder from convert_mouse_shp.py and emits a deterministic
runtime manifest.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from convert_mouse_shp import (
    SHPError,
    decode_frame_indices,
    indices_to_rgba,
    load_palette,
    read_frame_table,
    read_header,
)


def find_case_insensitive(root: Path, filename: str) -> Path | None:
    wanted = filename.lower()
    for path in root.rglob("*"):
        if path.is_file() and path.name.lower() == wanted:
            return path
    return None


def convert_resource(
    source: Path,
    palette: list[tuple[int, int, int, int]],
    output_dir: Path,
) -> dict:
    data = source.read_bytes()
    header = read_header(data)
    frames = read_frame_table(data, header)
    output_dir.mkdir(parents=True, exist_ok=True)

    output_files: list[str] = []
    stem = source.stem.lower()
    for frame in frames:
        indices = decode_frame_indices(data, header, frame)
        image = indices_to_rgba(
            indices,
            header.width,
            header.height,
            palette,
        )
        filename = (
            f"{stem}.png"
            if frame.index == 0
            else f"{stem}_{frame.index:03d}.png"
        )
        image.save(output_dir / filename, optimize=True)
        output_files.append(filename)

    return {
        "source": source.name,
        "id": source.stem.upper(),
        "canvas": [header.width, header.height],
        "frame_count": header.frame_count,
        "files": output_files,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert RA2 temperate ore/gem overlay resources."
    )
    parser.add_argument(
        "source",
        type=Path,
        help="Extracted RA2/YR source directory containing TIB*.TEM/GEM*.TEM.",
    )
    parser.add_argument(
        "--palette",
        type=Path,
        required=True,
        help="Path to ISOTEM.PAL.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("assets/ra2_overlays/temperate"),
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Fail when any expected overlay file is missing.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    expected = [
        *(f"TIB{index:02d}.TEM" for index in range(1, 21)),
        *(f"GEM{index:02d}.TEM" for index in range(1, 13)),
    ]

    try:
        palette = load_palette(args.palette, grayscale=False)
    except (OSError, SHPError) as exc:
        print(f"ERROR: {exc}")
        return 1

    manifest: dict = {
        "theater": "temperate",
        "palette": args.palette.name,
        "resources": {},
        "missing": [],
    }

    for filename in expected:
        source = find_case_insensitive(args.source, filename)
        if source is None:
            manifest["missing"].append(filename)
            continue
        try:
            record = convert_resource(source, palette, args.output)
        except (OSError, SHPError) as exc:
            print(f"ERROR: {filename}: {exc}")
            return 1
        manifest["resources"][record["id"]] = record

    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    print(
        f"Converted {len(manifest['resources'])} overlays; "
        f"missing {len(manifest['missing'])}."
    )
    if args.strict and manifest["missing"]:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

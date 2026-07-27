from __future__ import annotations

import argparse
import json
import struct
import zipfile
from dataclasses import dataclass
from pathlib import Path

from PIL import Image

from .palette import Palette


@dataclass(frozen=True)
class TmpTile:
    width: int
    height: int
    rows: tuple[bytes, ...]
    source: str

    def to_square(self, palette: Palette, size: int = 32) -> Image.Image:
        """Unwrap the Westwood isometric diamond into the engine's square grid.

        Iron Meridian still uses a rectangular logical grid.  Each TMP scanline is
        therefore resampled across the full square width.  This keeps authentic RA2
        terrain pixels without leaving transparent diamond gaps between cells.
        """
        source = Image.new("RGBA", (self.width, self.height), (0, 0, 0, 255))
        pixels = source.load()
        for y, row in enumerate(self.rows):
            if not row:
                continue
            row_image = Image.new("RGBA", (len(row), 1))
            row_image.putdata([palette.rgba(index)[:3] + (255,) for index in row])
            stretched = row_image.resize((self.width, 1), Image.Resampling.BILINEAR)
            stretched_pixels = stretched.load()
            for x in range(self.width):
                pixels[x, y] = stretched_pixels[x, 0]
        return source.resize((size, size), Image.Resampling.LANCZOS)


def _row_widths(width: int, height: int) -> list[int]:
    current = 4
    result: list[int] = []
    for y in range(height):
        result.append(current)
        current += 4 if y < height // 2 - 1 else -4
    expected = width * height // 2
    if sum(result) != expected:
        raise ValueError(f"Unsupported TMP diamond {width}x{height}: {sum(result)} != {expected}")
    return result


def parse_tmp(data: bytes, source: str = "memory") -> TmpTile:
    if len(data) < 20:
        raise ValueError(f"TMP file is too small: {source}")
    template_width, template_height, tile_width, tile_height = struct.unpack_from("<IIii", data, 0)
    if template_width <= 0 or template_height <= 0 or tile_width <= 0 or tile_height <= 0:
        raise ValueError(f"Invalid TMP header in {source}")
    count = template_width * template_height
    table_end = 16 + count * 4
    if table_end > len(data):
        raise ValueError(f"Truncated TMP offset table in {source}")
    offsets = struct.unpack_from(f"<{count}I", data, 16)
    offset = next((value for value in offsets if value != 0), 0)
    if offset <= 0 or offset + 52 > len(data):
        raise ValueError(f"TMP has no usable tile frame: {source}")

    cursor = offset + 52
    widths = _row_widths(tile_width, tile_height)
    packed_size = sum(widths)
    if cursor + packed_size > len(data):
        raise ValueError(f"Truncated TMP color data in {source}")
    rows: list[bytes] = []
    for row_width in widths:
        rows.append(data[cursor : cursor + row_width])
        cursor += row_width
    return TmpTile(tile_width, tile_height, tuple(rows), source)


def build_atlas(ra2_zip: Path, output_dir: Path, tile_size: int = 32) -> dict:
    output_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(ra2_zip) as archive:
        palette = Palette.from_bytes(archive.read("cache/isotem.pal"), "cache/isotem.pal")
        groups: list[tuple[str, list[str]]] = [
            ("grass", ["isotemp/clear01.tem"] + [f"isotemp/clear01{letter}.tem" for letter in "abcdefg"]),
            ("dirt", [f"isotemp/droadc{index:02d}.tem" for index in range(1, 9)]),
            ("water", [f"isotemp/water{index:02d}.tem" for index in range(1, 9)]),
            ("ore", ["isotemp/clear01.tem"] + [f"isotemp/clear01{letter}.tem" for letter in "abcdefg"]),
            ("rock", [f"isotemp/rough{index:02d}.tem" for index in range(1, 9)]),
        ]
        atlas = Image.new("RGBA", (tile_size * 40, tile_size), (0, 0, 0, 255))
        manifest_groups: dict[str, dict] = {}
        atlas_index = 0
        for terrain_name, names in groups:
            start = atlas_index
            sources: list[str] = []
            for name in names:
                payload = archive.read(name)
                tile = parse_tmp(payload, name)
                square = tile.to_square(palette, tile_size)
                if terrain_name == "ore":
                    # The game stores ore as a separate overlay rather than in the
                    # isometric ground template.  Add an ore field over authentic
                    # RA2 clear-ground pixels while preserving the existing engine's
                    # ore-cell semantics.
                    ore_pixels = square.load()
                    for py in range(3, tile_size - 3):
                        for px in range(3, tile_size - 3):
                            seed = (px * 17 + py * 31 + atlas_index * 13) % 97
                            if seed < 13 and ((px + py) % 3 != 0):
                                base = ore_pixels[px, py]
                                strength = 0.45 + float(seed) / 40.0
                                ore_pixels[px, py] = (
                                    min(255, int(base[0] * 0.35 + 224 * strength)),
                                    min(255, int(base[1] * 0.32 + 176 * strength)),
                                    min(255, int(base[2] * 0.20 + 44 * strength)),
                                    255,
                                )
                atlas.alpha_composite(square, (atlas_index * tile_size, 0))
                sources.append(name)
                atlas_index += 1
            manifest_groups[terrain_name] = {
                "start": start,
                "count": len(names),
                "sources": sources,
            }

    atlas_path = output_dir / "temperate_atlas.png"
    atlas.save(atlas_path, optimize=True)
    manifest = {
        "format": "ra2_tmp_square_atlas_v1",
        "tile_size": tile_size,
        "columns": atlas_index,
        "theater": "temperate",
        "palette": "cache/isotem.pal",
        "groups": manifest_groups,
        "note": "RA2 TMP scanlines unwrapped to the engine's current rectangular 32px grid.",
    }
    (output_dir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description="Build an RA2 temperate TMP terrain atlas for Godot")
    parser.add_argument("--ra2", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--tile-size", type=int, default=32)
    args = parser.parse_args()
    manifest = build_atlas(args.ra2, args.output, args.tile_size)
    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

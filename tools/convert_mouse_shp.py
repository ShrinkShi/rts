#!/usr/bin/env python3
"""Convert Westwood SHP(TS) mouse cursor frames to transparent PNG files.

Supported:
- SHP(TS) 8-byte file header.
- 24-byte frame information table.
- Uncompressed frames.
- Westwood RLE-Zero frames.
- 768-byte PAL files with either 6-bit or 8-bit RGB components.

The RA2/YR mouse cursor must use the matching mousepal.pal. A grayscale
fallback exists only for inspecting frame geometry and must not be shipped.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from dataclasses import asdict, dataclass
from pathlib import Path

try:
    from PIL import Image
except ImportError as exc:
    raise SystemExit(
        "Pillow is required. Install it with: python -m pip install Pillow"
    ) from exc


class SHPError(RuntimeError):
    """Raised when an SHP file is malformed or unsupported."""


@dataclass(frozen=True)
class FrameInfo:
    index: int
    x: int
    y: int
    width: int
    height: int
    flags: int
    minimap_rgba: tuple[int, int, int, int]
    reserved: int
    data_offset: int

    @property
    def has_transparency(self) -> bool:
        return bool(self.flags & 0x01)

    @property
    def uses_rle(self) -> bool:
        return bool(self.flags & 0x02)


@dataclass(frozen=True)
class SHPHeader:
    reserved: int
    width: int
    height: int
    frame_count: int


def read_header(data: bytes) -> SHPHeader:
    if len(data) < 8:
        raise SHPError("File is shorter than the 8-byte SHP(TS) header.")
    reserved, width, height, frame_count = struct.unpack_from("<4H", data, 0)
    if reserved != 0:
        raise SHPError(
            f"Not an SHP(TS) file: reserved header word is {reserved}, expected 0."
        )
    if width <= 0 or height <= 0:
        raise SHPError(f"Invalid canvas size: {width}x{height}.")
    if frame_count <= 0:
        raise SHPError("The file contains no frames.")
    table_end = 8 + frame_count * 24
    if table_end > len(data):
        raise SHPError(
            f"Frame table exceeds file size: needs {table_end} bytes, "
            f"file has {len(data)} bytes."
        )
    return SHPHeader(reserved, width, height, frame_count)


def read_frame_table(data: bytes, header: SHPHeader) -> list[FrameInfo]:
    frames: list[FrameInfo] = []
    for index in range(header.frame_count):
        offset = 8 + index * 24
        x, y, width, height = struct.unpack_from("<4H", data, offset)
        flags = struct.unpack_from("<I", data, offset + 8)[0]
        minimap_rgba = tuple(data[offset + 12 : offset + 16])
        reserved, data_offset = struct.unpack_from("<II", data, offset + 16)

        if x + width > header.width or y + height > header.height:
            raise SHPError(
                f"Frame {index} rectangle ({x},{y},{width},{height}) exceeds "
                f"the {header.width}x{header.height} canvas."
            )
        if data_offset and data_offset >= len(data):
            raise SHPError(
                f"Frame {index} data offset {data_offset} exceeds file size."
            )

        frames.append(
            FrameInfo(
                index=index,
                x=x,
                y=y,
                width=width,
                height=height,
                flags=flags,
                minimap_rgba=minimap_rgba,  # type: ignore[arg-type]
                reserved=reserved,
                data_offset=data_offset,
            )
        )
    return frames


def decode_rle_zero_line(encoded: bytes, expected_width: int, frame_index: int) -> bytes:
    output = bytearray()
    cursor = 0

    while cursor < len(encoded) and len(output) < expected_width:
        value = encoded[cursor]
        cursor += 1

        if value != 0:
            output.append(value)
            continue

        if cursor >= len(encoded):
            raise SHPError(
                f"Frame {frame_index}: RLE line ends with an incomplete zero run."
            )

        zero_count = encoded[cursor]
        cursor += 1
        output.extend(b"\x00" * zero_count)

    if len(output) != expected_width:
        raise SHPError(
            f"Frame {frame_index}: decoded RLE line width is {len(output)}, "
            f"expected {expected_width}."
        )

    return bytes(output)


def decode_frame_indices(
    data: bytes, header: SHPHeader, frame: FrameInfo
) -> bytes:
    canvas = bytearray(header.width * header.height)

    if (
        frame.data_offset == 0
        or frame.width == 0
        or frame.height == 0
    ):
        return bytes(canvas)

    if frame.uses_rle:
        cursor = frame.data_offset
        cropped = bytearray()

        for _row in range(frame.height):
            if cursor + 2 > len(data):
                raise SHPError(
                    f"Frame {frame.index}: truncated RLE scanline header."
                )
            line_size = struct.unpack_from("<H", data, cursor)[0]
            if line_size < 2:
                raise SHPError(
                    f"Frame {frame.index}: invalid RLE scanline size {line_size}."
                )
            line_end = cursor + line_size
            if line_end > len(data):
                raise SHPError(
                    f"Frame {frame.index}: RLE scanline exceeds file size."
                )
            encoded_line = data[cursor + 2 : line_end]
            cropped.extend(
                decode_rle_zero_line(
                    encoded_line, frame.width, frame.index
                )
            )
            cursor = line_end
    else:
        expected = frame.width * frame.height
        end = frame.data_offset + expected
        if end > len(data):
            raise SHPError(
                f"Frame {frame.index}: uncompressed frame exceeds file size."
            )
        cropped = bytearray(data[frame.data_offset:end])

    for row in range(frame.height):
        src_start = row * frame.width
        src_end = src_start + frame.width
        dst_start = (frame.y + row) * header.width + frame.x
        dst_end = dst_start + frame.width
        canvas[dst_start:dst_end] = cropped[src_start:src_end]

    return bytes(canvas)


def load_palette(path: Path | None, grayscale: bool) -> list[tuple[int, int, int, int]]:
    if grayscale:
        return [
            (0, 0, 0, 0) if index == 0 else (index, index, index, 255)
            for index in range(256)
        ]

    if path is None:
        raise SHPError(
            "A matching palette is required. For RA2/YR mouse cursors, "
            "provide mousepal.pal. Use --grayscale only for inspection."
        )

    raw = path.read_bytes()
    if len(raw) != 768:
        raise SHPError(
            f"Palette must be exactly 768 bytes, got {len(raw)} bytes."
        )

    components = list(raw)
    is_six_bit = max(components) <= 63
    scale = (255.0 / 63.0) if is_six_bit else 1.0

    palette: list[tuple[int, int, int, int]] = []
    for index in range(256):
        red, green, blue = components[index * 3 : index * 3 + 3]
        rgba = (
            round(red * scale),
            round(green * scale),
            round(blue * scale),
            0 if index == 0 else 255,
        )
        palette.append(rgba)
    return palette


def indices_to_rgba(
    indices: bytes,
    width: int,
    height: int,
    palette: list[tuple[int, int, int, int]],
) -> Image.Image:
    rgba = bytearray(width * height * 4)
    for pixel_index, palette_index in enumerate(indices):
        red, green, blue, alpha = palette[palette_index]
        start = pixel_index * 4
        rgba[start : start + 4] = bytes((red, green, blue, alpha))
    return Image.frombytes("RGBA", (width, height), bytes(rgba))


def write_frames(
    source: Path,
    output_dir: Path,
    palette_path: Path | None,
    grayscale: bool,
) -> dict:
    data = source.read_bytes()
    header = read_header(data)
    frames = read_frame_table(data, header)
    palette = load_palette(palette_path, grayscale)

    output_dir.mkdir(parents=True, exist_ok=True)
    frame_records: list[dict] = []

    for frame in frames:
        indices = decode_frame_indices(data, header, frame)
        image = indices_to_rgba(
            indices, header.width, header.height, palette
        )
        filename = f"frame_{frame.index:03d}.png"
        image.save(output_dir / filename, optimize=True)

        record = asdict(frame)
        record["has_transparency"] = frame.has_transparency
        record["uses_rle"] = frame.uses_rle
        record["file"] = filename
        frame_records.append(record)

    metadata = {
        "source": source.name,
        "palette": palette_path.name if palette_path else "grayscale-inspection",
        "canvas_width": header.width,
        "canvas_height": header.height,
        "frame_count": header.frame_count,
        "frames": frame_records,
    }
    (output_dir / "frames.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return metadata


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Convert SHP(TS) mouse cursor frames to transparent PNG."
    )
    parser.add_argument("shp", type=Path, help="Path to mouse.shp or mouse.sha.")
    parser.add_argument(
        "--palette",
        type=Path,
        help="Path to the matching 768-byte mousepal.pal.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("mouse_cursor_frames"),
        help="Output directory.",
    )
    parser.add_argument(
        "--grayscale",
        action="store_true",
        help="Inspection-only fallback. Do not use for final game assets.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        metadata = write_frames(
            args.shp, args.output, args.palette, args.grayscale
        )
    except (OSError, SHPError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print(
        "Converted "
        f"{metadata['frame_count']} frames at "
        f"{metadata['canvas_width']}x{metadata['canvas_height']} "
        f"to {args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

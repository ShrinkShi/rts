from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import struct


class ShpTsError(ValueError):
    """Raised when a Westwood SHP(TS) file is malformed or unsupported."""


FILE_HEADER = struct.Struct("<4H")
FRAME_HEADER = struct.Struct("<4H4BI8x")
FLAG_HAS_TRANSPARENCY = 0x02
FLAG_USES_RLE = 0x04


@dataclass(frozen=True)
class ShpFrame:
    index: int
    x: int
    y: int
    width: int
    height: int
    flags: int
    frame_color: int
    data_offset: int
    pixels: bytes


@dataclass(frozen=True)
class ShpTsFile:
    width: int
    height: int
    frames: tuple[ShpFrame, ...]
    source_name: str = ""

    @classmethod
    def from_path(cls, path: Path) -> "ShpTsFile":
        return cls.from_bytes(path.read_bytes(), source_name=path.name)

    @classmethod
    def from_bytes(cls, payload: bytes, source_name: str = "") -> "ShpTsFile":
        if len(payload) < FILE_HEADER.size:
            raise ShpTsError(f"SHP header is truncated: {source_name}")
        zero, canvas_width, canvas_height, frame_count = FILE_HEADER.unpack_from(payload, 0)
        if zero != 0:
            raise ShpTsError(f"Invalid SHP signature word {zero}: {source_name}")
        if canvas_width <= 0 or canvas_height <= 0:
            raise ShpTsError(
                f"Invalid SHP canvas {canvas_width}x{canvas_height}: {source_name}"
            )
        if frame_count <= 0:
            raise ShpTsError(f"SHP has no frames: {source_name}")

        table_end = FILE_HEADER.size + frame_count * FRAME_HEADER.size
        if table_end > len(payload):
            raise ShpTsError(f"SHP frame table is truncated: {source_name}")

        headers: list[tuple[int, int, int, int, int, int, int]] = []
        for index in range(frame_count):
            offset = FILE_HEADER.size + index * FRAME_HEADER.size
            x, y, width, height, flags, _unknown, frame_color, _unknown2, data_offset = (
                FRAME_HEADER.unpack_from(payload, offset)
            )
            if width == 0 or height == 0:
                headers.append((x, y, width, height, flags, frame_color, data_offset))
                continue
            if x + width > canvas_width or y + height > canvas_height:
                raise ShpTsError(
                    f"SHP frame {index} bounds {x},{y},{width},{height} exceed "
                    f"{canvas_width}x{canvas_height}: {source_name}"
                )
            if data_offset < table_end or data_offset >= len(payload):
                raise ShpTsError(
                    f"SHP frame {index} data offset is invalid: {data_offset}: {source_name}"
                )
            headers.append((x, y, width, height, flags, frame_color, data_offset))

        frames: list[ShpFrame] = []
        sorted_offsets = sorted(
            {data_offset for *_rest, data_offset in headers if data_offset >= table_end}
        )
        next_offset_for: dict[int, int] = {}
        for position, data_offset in enumerate(sorted_offsets):
            next_offset_for[data_offset] = (
                sorted_offsets[position + 1]
                if position + 1 < len(sorted_offsets)
                else len(payload)
            )

        for index, (x, y, width, height, flags, frame_color, data_offset) in enumerate(headers):
            if width == 0 or height == 0:
                pixels = bytes(canvas_width * canvas_height)
            else:
                end = next_offset_for.get(data_offset, len(payload))
                frame_payload = payload[data_offset:end]
                if flags & FLAG_USES_RLE:
                    local_pixels = _decode_scanline_rle(
                        frame_payload, width, height, source_name, index
                    )
                else:
                    expected = width * height
                    if len(frame_payload) < expected:
                        raise ShpTsError(
                            f"SHP frame {index} uncompressed payload is truncated: "
                            f"expected {expected}, got {len(frame_payload)}: {source_name}"
                        )
                    local_pixels = frame_payload[:expected]
                canvas = bytearray(canvas_width * canvas_height)
                for row in range(height):
                    source_start = row * width
                    destination_start = (y + row) * canvas_width + x
                    canvas[destination_start : destination_start + width] = local_pixels[
                        source_start : source_start + width
                    ]
                pixels = bytes(canvas)
            frames.append(
                ShpFrame(
                    index=index,
                    x=x,
                    y=y,
                    width=width,
                    height=height,
                    flags=flags,
                    frame_color=frame_color,
                    data_offset=data_offset,
                    pixels=pixels,
                )
            )
        return cls(canvas_width, canvas_height, tuple(frames), source_name)


def _decode_scanline_rle(
    payload: bytes,
    width: int,
    height: int,
    source_name: str,
    frame_index: int,
) -> bytes:
    output = bytearray(width * height)
    cursor = 0
    for row in range(height):
        if cursor + 2 > len(payload):
            raise ShpTsError(
                f"SHP frame {frame_index} RLE line {row} header is truncated: {source_name}"
            )
        line_size = struct.unpack_from("<H", payload, cursor)[0]
        line_start = cursor
        cursor += 2
        # Westwood writers count the two-byte line-size field in the stored size.
        line_end = line_start + line_size
        if line_size < 2 or line_end > len(payload):
            raise ShpTsError(
                f"SHP frame {frame_index} RLE line {row} size is invalid: "
                f"{line_size}: {source_name}"
            )
        x = 0
        while cursor < line_end and x < width:
            value = payload[cursor]
            cursor += 1
            if value != 0:
                output[row * width + x] = value
                x += 1
                continue
            if cursor >= line_end:
                raise ShpTsError(
                    f"SHP frame {frame_index} RLE line {row} ends after a skip marker: "
                    f"{source_name}"
                )
            skip = payload[cursor]
            cursor += 1
            if skip == 0:
                # A zero-length transparent run is accepted by the original reader
                # as an end-of-line marker.
                break
            x += skip
            if x > width:
                raise ShpTsError(
                    f"SHP frame {frame_index} RLE line {row} overruns width: {source_name}"
                )
        if x > width:
            raise ShpTsError(
                f"SHP frame {frame_index} RLE line {row} decoded too wide: {source_name}"
            )
        cursor = line_end
    return bytes(output)


def indexed_to_rgba(
    indices: bytes,
    width: int,
    height: int,
    palette: tuple[tuple[int, int, int, int], ...],
) -> bytes:
    if len(indices) != width * height:
        raise ShpTsError(
            f"Indexed image length mismatch: expected {width * height}, got {len(indices)}"
        )
    if len(palette) != 256:
        raise ShpTsError(f"Palette must contain 256 colors, got {len(palette)}")
    rgba = bytearray(width * height * 4)
    for index, palette_index in enumerate(indices):
        rgba[index * 4 : index * 4 + 4] = bytes(palette[palette_index])
    return bytes(rgba)

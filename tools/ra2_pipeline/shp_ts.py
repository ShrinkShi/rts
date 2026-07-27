from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import struct

from PIL import Image

from .palette import Palette


@dataclass(frozen=True)
class ShpFrameHeader:
    x: int
    y: int
    width: int
    height: int
    flags: int
    minimap_color: int
    reserved: int
    data_offset: int

    @property
    def uses_rle(self) -> bool:
        return bool(self.flags & 0x02)


class ShpTsFile:
    """Reader for the SHP(TS) format used by Tiberian Sun and Red Alert 2."""

    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.data = self.path.read_bytes()
        if len(self.data) < 8:
            raise ValueError(f"SHP file is too small: {self.path}")
        reserved, self.width, self.height, self.frame_count = struct.unpack_from("<4H", self.data, 0)
        if reserved != 0:
            raise ValueError(f"Not a SHP(TS) file (reserved word is {reserved}): {self.path}")
        if self.width <= 0 or self.height <= 0:
            raise ValueError(f"Invalid SHP dimensions {self.width}x{self.height}: {self.path}")
        table_end = 8 + self.frame_count * 24
        if table_end > len(self.data):
            raise ValueError(f"SHP frame table exceeds file size: {self.path}")
        self.frames: list[ShpFrameHeader] = []
        for index in range(self.frame_count):
            offset = 8 + index * 24
            x, y, width, height, flags, color, reserved2, data_offset = struct.unpack_from(
                "<4H4I", self.data, offset
            )
            self.frames.append(
                ShpFrameHeader(x, y, width, height, flags, color, reserved2, data_offset)
            )

    def decode_indices(self, frame_index: int) -> bytes:
        frame = self.frames[frame_index]
        canvas = bytearray(self.width * self.height)
        if frame.data_offset == 0 or frame.width == 0 or frame.height == 0:
            return bytes(canvas)
        if frame.data_offset >= len(self.data):
            raise ValueError(f"Frame {frame_index} points outside file: {self.path}")

        if frame.uses_rle:
            self._decode_rle(frame, canvas)
        else:
            self._decode_raw(frame, canvas)
        return bytes(canvas)

    def _decode_raw(self, frame: ShpFrameHeader, canvas: bytearray) -> None:
        cursor = frame.data_offset
        required = frame.width * frame.height
        if cursor + required > len(self.data):
            raise ValueError(f"Uncompressed SHP frame exceeds file size: {self.path}")
        for row in range(frame.height):
            target_y = frame.y + row
            if not 0 <= target_y < self.height:
                cursor += frame.width
                continue
            for column in range(frame.width):
                value = self.data[cursor]
                cursor += 1
                target_x = frame.x + column
                if 0 <= target_x < self.width:
                    canvas[target_y * self.width + target_x] = value

    def _decode_rle(self, frame: ShpFrameHeader, canvas: bytearray) -> None:
        cursor = frame.data_offset
        for row in range(frame.height):
            if cursor + 2 > len(self.data):
                raise ValueError(f"Truncated SHP scanline header in {self.path}")
            line_size = struct.unpack_from("<H", self.data, cursor)[0]
            if line_size < 2 or cursor + line_size > len(self.data):
                raise ValueError(f"Invalid SHP scanline size {line_size} in {self.path}")
            payload = self.data[cursor + 2 : cursor + line_size]
            cursor += line_size
            source_cursor = 0
            column = 0
            target_y = frame.y + row
            while source_cursor < len(payload) and column < frame.width:
                value = payload[source_cursor]
                source_cursor += 1
                if value == 0:
                    if source_cursor >= len(payload):
                        break
                    column += payload[source_cursor]
                    source_cursor += 1
                    continue
                target_x = frame.x + column
                if 0 <= target_x < self.width and 0 <= target_y < self.height:
                    canvas[target_y * self.width + target_x] = value
                column += 1

    def decode_image(self, frame_index: int, palette: Palette) -> Image.Image:
        indices = self.decode_indices(frame_index)
        image = Image.new("RGBA", (self.width, self.height), (0, 0, 0, 0))
        image.putdata([palette.rgba(value) for value in indices])
        return image

    def decode_all(self, palette: Palette) -> list[Image.Image]:
        return [self.decode_image(index, palette) for index in range(self.frame_count)]

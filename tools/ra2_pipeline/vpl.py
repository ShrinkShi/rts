from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import struct

from .palette import Palette


@dataclass(frozen=True)
class VplFile:
    remap_start: int
    remap_end: int
    level_count: int
    palette: Palette
    tables: tuple[bytes, ...]

    @classmethod
    def from_file(cls, path: str | Path) -> "VplFile":
        path = Path(path)
        data = path.read_bytes()
        if len(data) < 16 + 768:
            raise ValueError(f"VPL file is too small: {path}")
        remap_start, remap_end, level_count, _unknown = struct.unpack_from("<4I", data, 0)
        palette = Palette.from_bytes(data[16:16 + 768], str(path))
        table_data = data[16 + 768:]
        expected = level_count * 256
        if len(table_data) < expected:
            raise ValueError(f"VPL lookup tables are truncated: {path}")
        tables = tuple(table_data[index * 256:(index + 1) * 256] for index in range(level_count))
        return cls(remap_start, remap_end, level_count, palette, tables)

    def color_index(self, source_index: int, light_level: int) -> int:
        if not self.tables:
            return source_index & 0xFF
        level = max(0, min(len(self.tables) - 1, int(light_level)))
        return self.tables[level][source_index & 0xFF]

    def rgba(self, source_index: int, light_level: int) -> tuple[int, int, int, int]:
        return self.palette.rgba(self.color_index(source_index, light_level))

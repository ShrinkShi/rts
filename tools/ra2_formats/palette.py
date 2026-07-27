from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


@dataclass(frozen=True)
class Palette:
    colors: tuple[tuple[int, int, int, int], ...]
    source: str = "generated"

    @classmethod
    def grayscale(cls) -> "Palette":
        values = tuple((i, i, i, 0 if i == 0 else 255) for i in range(256))
        return cls(values, "grayscale")

    @classmethod
    def from_bytes(cls, data: bytes, source: str = "memory") -> "Palette":
        if len(data) < 768:
            raise ValueError(f"Palette needs at least 768 bytes, got {len(data)}")
        payload = data[:768]
        # Westwood PAL files are normally 6-bit RGB. VXL embedded palettes may
        # already use 8-bit values. Detect conservatively instead of forcing x4.
        component_scale = 4 if max(payload) <= 63 else 1
        colors: list[tuple[int, int, int, int]] = []
        for index in range(256):
            r, g, b = payload[index * 3 : index * 3 + 3]
            colors.append(
                (
                    min(255, int(r) * component_scale),
                    min(255, int(g) * component_scale),
                    min(255, int(b) * component_scale),
                    0 if index == 0 else 255,
                )
            )
        return cls(tuple(colors), source)

    @classmethod
    def from_file(cls, path: str | Path) -> "Palette":
        palette_path = Path(path)
        return cls.from_bytes(palette_path.read_bytes(), str(palette_path))

    def with_transparent_indices(self, indices: Iterable[int]) -> "Palette":
        transparent = {int(value) & 0xFF for value in indices}
        values = []
        for index, color in enumerate(self.colors):
            values.append((color[0], color[1], color[2], 0 if index in transparent else color[3]))
        return Palette(tuple(values), self.source)

    def rgba(self, index: int) -> tuple[int, int, int, int]:
        return self.colors[int(index) & 0xFF]

from __future__ import annotations

from pathlib import Path

from ra2_ini import RA2MapError

Palette = tuple[tuple[int, int, int, int], ...]


def load_palette(path: Path, *, transparent_index: int | None = 0) -> Palette:
    """Read a 256-entry Westwood PAL file.

    RA2/YR stores palette channels as 6-bit VGA values. Expansion with bit
    replication maps 0..63 exactly onto 0..255 instead of stopping at 252.
    """
    payload = path.read_bytes()
    if len(payload) != 256 * 3:
        raise RA2MapError(
            f"Westwood palette must be 768 bytes, got {len(payload)}: {path}"
        )

    colors: list[tuple[int, int, int, int]] = []
    for index in range(256):
        red, green, blue = payload[index * 3 : index * 3 + 3]
        alpha = 0 if transparent_index == index else 255
        colors.append(
            (
                _expand_six_bit(red),
                _expand_six_bit(green),
                _expand_six_bit(blue),
                alpha,
            )
        )
    return tuple(colors)


def _expand_six_bit(value: int) -> int:
    if value > 63:
        # Mod palettes occasionally contain already-expanded channels. Do not
        # wrap them through the 6-bit conversion.
        return value
    return (value << 2) | (value >> 4)

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import struct

from ra2_ini import RA2MapError
from ra2_palette import Palette

FILE_HEADER = struct.Struct("<4I")
CELL_HEADER = struct.Struct("<iiIIIiiIIB3xBBB6B3x")
CELL_HEADER_SIZE = CELL_HEADER.size
SENTINEL_OFFSET = 0xCDCDCDCD


@dataclass(frozen=True)
class TmpCell:
    index: int
    grid_x: int
    grid_y: int
    offset: int
    x: int
    y: int
    extra_data_offset: int
    z_data_offset: int
    extra_z_data_offset: int
    extra_x: int
    extra_y: int
    extra_width: int
    extra_height: int
    flags: int
    height: int
    terrain_type: int
    ramp_type: int
    radar_left: tuple[int, int, int]
    radar_right: tuple[int, int, int]
    pixels: bytes
    z_data: bytes
    extra_pixels: bytes
    extra_z_data: bytes

    @property
    def has_extra_data(self) -> bool:
        return bool(self.flags & 0x01)

    @property
    def has_z_data(self) -> bool:
        return bool(self.flags & 0x02)

    @property
    def has_damaged_data(self) -> bool:
        return bool(self.flags & 0x04)


@dataclass(frozen=True)
class TmpFile:
    block_width: int
    block_height: int
    block_image_width: int
    block_image_height: int
    cells: tuple[TmpCell | None, ...]
    source_name: str = ""

    @classmethod
    def from_path(cls, path: Path) -> "TmpFile":
        return cls.from_bytes(path.read_bytes(), source_name=path.name)

    @classmethod
    def from_bytes(cls, payload: bytes, source_name: str = "") -> "TmpFile":
        if len(payload) < FILE_HEADER.size:
            raise RA2MapError(f"TMP header is truncated: {source_name}")

        block_width, block_height, image_width, image_height = FILE_HEADER.unpack_from(
            payload, 0
        )
        if not (1 <= block_width <= 10 and 1 <= block_height <= 10):
            raise RA2MapError(
                f"Invalid TMP block dimensions {block_width}x{block_height}: {source_name}"
            )
        if image_width <= 0 or image_height <= 0 or image_width % 2 or image_height % 2:
            raise RA2MapError(
                f"Invalid TMP image dimensions {image_width}x{image_height}: {source_name}"
            )

        cell_count = block_width * block_height
        pointer_table_end = FILE_HEADER.size + cell_count * 4
        if pointer_table_end > len(payload):
            raise RA2MapError(f"TMP pointer table is truncated: {source_name}")
        pointers = struct.unpack_from(
            "<" + "I" * cell_count, payload, FILE_HEADER.size
        )

        packed_diamond_size = image_width * image_height // 2
        cells: list[TmpCell | None] = []
        for index, pointer in enumerate(pointers):
            if pointer == 0:
                cells.append(None)
                continue
            if pointer + CELL_HEADER_SIZE > len(payload):
                raise RA2MapError(
                    f"TMP cell {index} header is outside the file: {source_name}"
                )

            values = CELL_HEADER.unpack_from(payload, pointer)
            (
                x,
                y,
                extra_offset,
                z_offset,
                extra_z_offset,
                extra_x,
                extra_y,
                extra_width,
                extra_height,
                flags,
                height,
                terrain_type,
                ramp_type,
                *radar,
            ) = values

            # Westwood offsets in the cell header are relative to the start of
            # that cell header, not to the beginning of the TMP file.
            pixels = _relative_slice(
                payload,
                pointer,
                CELL_HEADER_SIZE,
                packed_diamond_size,
                "main pixels",
                source_name,
                index,
            )
            z_data = b""
            if flags & 0x02:
                z_data = _relative_slice(
                    payload,
                    pointer,
                    z_offset,
                    packed_diamond_size,
                    "Z data",
                    source_name,
                    index,
                )

            extra_pixels = b""
            extra_z_data = b""
            if flags & 0x01:
                if extra_width <= 0 or extra_height <= 0:
                    raise RA2MapError(
                        f"TMP cell {index} has ExtraData but invalid dimensions "
                        f"{extra_width}x{extra_height}: {source_name}"
                    )
                extra_size = extra_width * extra_height
                extra_pixels = _relative_slice(
                    payload,
                    pointer,
                    extra_offset,
                    extra_size,
                    "extra pixels",
                    source_name,
                    index,
                )
                if extra_z_offset not in (0, SENTINEL_OFFSET):
                    extra_z_data = _relative_slice(
                        payload,
                        pointer,
                        extra_z_offset,
                        extra_size,
                        "extra Z data",
                        source_name,
                        index,
                    )

            cells.append(
                TmpCell(
                    index=index,
                    grid_x=index % block_width,
                    grid_y=index // block_width,
                    offset=pointer,
                    x=x,
                    y=y,
                    extra_data_offset=extra_offset,
                    z_data_offset=z_offset,
                    extra_z_data_offset=extra_z_offset,
                    extra_x=extra_x,
                    extra_y=extra_y,
                    extra_width=extra_width,
                    extra_height=extra_height,
                    flags=flags,
                    height=height,
                    terrain_type=terrain_type,
                    ramp_type=ramp_type,
                    radar_left=(radar[0], radar[1], radar[2]),
                    radar_right=(radar[3], radar[4], radar[5]),
                    pixels=pixels,
                    z_data=z_data,
                    extra_pixels=extra_pixels,
                    extra_z_data=extra_z_data,
                )
            )

        return cls(
            block_width=block_width,
            block_height=block_height,
            block_image_width=image_width,
            block_image_height=image_height,
            cells=tuple(cells),
            source_name=source_name,
        )

    def cell(self, index: int) -> TmpCell:
        if not 0 <= index < len(self.cells):
            raise RA2MapError(
                f"SubTileIndex {index} outside 0..{len(self.cells) - 1}: {self.source_name}"
            )
        cell = self.cells[index]
        if cell is None:
            raise RA2MapError(f"SubTileIndex {index} is empty: {self.source_name}")
        return cell


def _relative_slice(
    payload: bytes,
    cell_base: int,
    relative_offset: int,
    size: int,
    label: str,
    source_name: str,
    cell_index: int,
) -> bytes:
    start = cell_base + relative_offset
    end = start + size
    if relative_offset == SENTINEL_OFFSET or start < 0 or end > len(payload):
        raise RA2MapError(
            f"TMP cell {cell_index} {label} outside file "
            f"({relative_offset}+{size}): {source_name}"
        )
    return payload[start:end]


def unpack_diamond(
    packed: bytes,
    width: int,
    height: int,
    *,
    transparent_index: int = 0,
) -> bytes:
    """Expand RA2's packed 60x30 diamond into a rectangular indexed canvas."""
    expected_size = width * height // 2
    if len(packed) != expected_size:
        raise RA2MapError(
            f"Diamond data must contain {expected_size} bytes, got {len(packed)}"
        )
    canvas = bytearray((transparent_index,)) * (width * height)
    cursor = 0
    half_height = height // 2
    for row in range(height):
        # RA2's 60x30 cell stores rows 2,6,10,...58,58,...10,6,2.
        run_length = (
            2 + 4 * row
            if row < half_height
            else 2 + 4 * (height - 1 - row)
        )
        left = (width - run_length) // 2
        destination = row * width + left
        canvas[destination : destination + run_length] = packed[
            cursor : cursor + run_length
        ]
        cursor += run_length
    if cursor != len(packed):
        raise RA2MapError(
            f"Diamond unpack consumed {cursor} bytes instead of {len(packed)}"
        )
    return bytes(canvas)


def render_rgba(
    tmp: TmpFile,
    sub_tile: int,
    palette: Palette,
    *,
    include_extra: bool = True,
) -> tuple[int, int, int, int, bytes]:
    """Composite one TMP cell into RGBA for tooling previews.

    Returns width, height, origin_x, origin_y and RGBA bytes. Z data is parsed and
    preserved by TmpFile but is not flattened into this diagnostic preview.
    """
    cell = tmp.cell(sub_tile)
    width = tmp.block_image_width
    height = tmp.block_image_height
    base = unpack_diamond(cell.pixels, width, height)

    minimum_x = 0
    minimum_y = 0
    maximum_x = width
    maximum_y = height
    if include_extra and cell.has_extra_data:
        minimum_x = min(minimum_x, cell.extra_x)
        minimum_y = min(minimum_y, cell.extra_y)
        maximum_x = max(maximum_x, cell.extra_x + cell.extra_width)
        maximum_y = max(maximum_y, cell.extra_y + cell.extra_height)

    output_width = maximum_x - minimum_x
    output_height = maximum_y - minimum_y
    rgba = bytearray(output_width * output_height * 4)

    def blit(indices: bytes, source_width: int, source_height: int, x: int, y: int) -> None:
        for source_y in range(source_height):
            for source_x in range(source_width):
                palette_index = indices[source_y * source_width + source_x]
                if palette_index == 0:
                    continue
                destination_index = (
                    (y + source_y - minimum_y) * output_width
                    + (x + source_x - minimum_x)
                ) * 4
                rgba[destination_index : destination_index + 4] = bytes(
                    palette[palette_index]
                )

    blit(base, width, height, 0, 0)
    if include_extra and cell.has_extra_data:
        blit(
            cell.extra_pixels,
            cell.extra_width,
            cell.extra_height,
            cell.extra_x,
            cell.extra_y,
        )
    return output_width, output_height, minimum_x, minimum_y, bytes(rgba)

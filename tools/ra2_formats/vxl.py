from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import struct

from .palette import Palette


@dataclass(frozen=True)
class Voxel:
    x: int
    y: int
    z: int
    color_index: int
    normal_index: int


@dataclass
class VxlSection:
    name: str
    size: tuple[int, int, int]
    normals_mode: int
    scale: float
    transform: tuple[float, ...]
    bounds: tuple[float, ...]
    voxels: list[Voxel]


class VxlFile:
    """Reader for Westwood VXL voxel files used by TS/RA2."""

    SIGNATURE = b"Voxel Animation"

    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.data = self.path.read_bytes()
        if len(self.data) < 802 or self.data[:16].rstrip(b"\0") != self.SIGNATURE:
            raise ValueError(f"Not a supported VXL file: {self.path}")
        (
            self.palette_count,
            self.header_count,
            self.tailer_count,
            self.body_size,
        ) = struct.unpack_from("<4I", self.data, 16)
        if self.header_count <= 0 or self.tailer_count <= 0:
            raise ValueError(f"VXL contains no sections: {self.path}")
        self.palette = Palette.from_bytes(self.data[32:800], f"embedded:{self.path}")
        # Westwood files include a 0xFFFF marker after the embedded palette.
        limb_headers_offset = 802
        body_offset = limb_headers_offset + self.header_count * 28
        tailers_offset = body_offset + self.body_size
        expected_end = tailers_offset + self.tailer_count * 92
        if expected_end > len(self.data):
            raise ValueError(f"VXL tailer table exceeds file size: {self.path}")

        names: list[str] = []
        for index in range(self.header_count):
            cursor = limb_headers_offset + index * 28
            raw_name = self.data[cursor : cursor + 16]
            names.append(raw_name.split(b"\0", 1)[0].decode("ascii", "replace"))

        self.sections: list[VxlSection] = []
        for section_index in range(self.tailer_count):
            cursor = tailers_offset + section_index * 92
            span_start_offset, span_end_offset, span_data_offset = struct.unpack_from(
                "<3I", self.data, cursor
            )
            scale = struct.unpack_from("<f", self.data, cursor + 12)[0]
            transform = struct.unpack_from("<12f", self.data, cursor + 16)
            bounds = struct.unpack_from("<6f", self.data, cursor + 64)
            size_x, size_y, size_z, normals_mode = self.data[cursor + 88 : cursor + 92]
            column_count = size_x * size_y
            if column_count <= 0:
                self.sections.append(
                    VxlSection(
                        names[section_index] if section_index < len(names) else f"section_{section_index}",
                        (size_x, size_y, size_z),
                        normals_mode,
                        scale,
                        transform,
                        bounds,
                        [],
                    )
                )
                continue
            starts_offset = body_offset + span_start_offset
            ends_offset = body_offset + span_end_offset
            if ends_offset + column_count * 4 > tailers_offset:
                raise ValueError(f"VXL span tables exceed body bounds: {self.path}")
            span_starts = struct.unpack_from(f"<{column_count}i", self.data, starts_offset)
            span_ends = struct.unpack_from(f"<{column_count}i", self.data, ends_offset)
            voxels = self._decode_voxels(
                body_offset,
                span_data_offset,
                span_starts,
                span_ends,
                size_x,
                size_y,
                size_z,
                tailers_offset,
            )
            self.sections.append(
                VxlSection(
                    names[section_index] if section_index < len(names) else f"section_{section_index}",
                    (size_x, size_y, size_z),
                    normals_mode,
                    scale,
                    transform,
                    bounds,
                    voxels,
                )
            )

    def _decode_voxels(
        self,
        body_offset: int,
        span_data_offset: int,
        span_starts: tuple[int, ...],
        span_ends: tuple[int, ...],
        size_x: int,
        size_y: int,
        size_z: int,
        body_end: int,
    ) -> list[Voxel]:
        voxels: list[Voxel] = []
        data_base = body_offset + span_data_offset
        for column_index, relative_start in enumerate(span_starts):
            if relative_start < 0:
                continue
            relative_end = span_ends[column_index]
            cursor = data_base + relative_start
            hard_end = min(body_end, data_base + relative_end + 1) if relative_end >= relative_start else body_end
            x = column_index % size_x
            y = column_index // size_x
            z = 0
            guard = 0
            while z < size_z and cursor + 2 <= hard_end and guard < 1024:
                guard += 1
                skip_count = self.data[cursor]
                voxel_count = self.data[cursor + 1]
                cursor += 2
                z += skip_count
                for _ in range(voxel_count):
                    if cursor + 2 > hard_end:
                        break
                    color_index = self.data[cursor]
                    normal_index = self.data[cursor + 1]
                    cursor += 2
                    if z < size_z:
                        voxels.append(Voxel(x, y, z, color_index, normal_index))
                    z += 1
                if cursor >= hard_end:
                    break
                repeated_count = self.data[cursor]
                cursor += 1
                # Corrupt third-party voxels occasionally contain mismatched tail
                # counts. The span table is authoritative, so tolerate mismatch.
                if skip_count == 0 and voxel_count == 0:
                    break
                if repeated_count != voxel_count and cursor >= hard_end:
                    break
        return voxels

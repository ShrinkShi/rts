from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import struct


@dataclass(frozen=True)
class HvaSection:
    name: str


class HvaFile:
    """Reader for Hierarchical Voxel Animation (.hva) files."""

    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.data = self.path.read_bytes()
        if len(self.data) < 24:
            raise ValueError(f"HVA file is too small: {self.path}")
        self.file_name = self.data[:16].split(b"\0", 1)[0].decode("ascii", "replace")
        self.frame_count, self.section_count = struct.unpack_from("<2I", self.data, 16)
        names_end = 24 + self.section_count * 16
        matrix_bytes = self.frame_count * self.section_count * 48
        if names_end + matrix_bytes > len(self.data):
            raise ValueError(f"HVA matrix table exceeds file size: {self.path}")
        self.sections = []
        for index in range(self.section_count):
            raw = self.data[24 + index * 16 : 24 + (index + 1) * 16]
            self.sections.append(HvaSection(raw.split(b"\0", 1)[0].decode("ascii", "replace")))
        self.matrices: list[list[tuple[float, ...]]] = []
        cursor = names_end
        for _frame_index in range(self.frame_count):
            frame_matrices = []
            for _section_index in range(self.section_count):
                frame_matrices.append(struct.unpack_from("<12f", self.data, cursor))
                cursor += 48
            self.matrices.append(frame_matrices)

    @staticmethod
    def identity_matrix() -> tuple[float, ...]:
        return (
            1.0,
            0.0,
            0.0,
            0.0,
            0.0,
            1.0,
            0.0,
            0.0,
            0.0,
            0.0,
            1.0,
            0.0,
        )

    def matrix(self, frame_index: int, section_index: int) -> tuple[float, ...]:
        if not self.matrices:
            return self.identity_matrix()
        safe_frame = frame_index % len(self.matrices)
        if not 0 <= section_index < len(self.matrices[safe_frame]):
            return self.identity_matrix()
        return self.matrices[safe_frame][section_index]

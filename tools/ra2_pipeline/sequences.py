from __future__ import annotations

from dataclasses import dataclass
from typing import Any

# Westwood infantry/SHP-vehicle facing order used by RA2/YR frame blocks.
# Raw SHP order is N, NW, W, SW, S, SE, E, NE (counter-clockwise on screen).
RA2_FACING_NAMES = ("N", "NW", "W", "SW", "S", "SE", "E", "NE")
# Iron Meridian's direction index starts at screen-right and rotates clockwise:
# E, SE, S, SW, W, NW, N, NE.
GODOT_TO_RA2_FACING = (6, 5, 4, 3, 2, 1, 0, 7)
RA2_TO_GODOT_FACING = tuple(GODOT_TO_RA2_FACING.index(index) for index in range(8))


@dataclass(frozen=True)
class SequenceEntry:
    name: str
    start: int
    frames: int
    facing_stride: int
    facing_override: str = ""
    reverse: bool = False
    raw_extra: tuple[str, ...] = ()

    @property
    def directional(self) -> bool:
        return self.facing_stride > 0

    @property
    def facing_count(self) -> int:
        return 8 if self.directional else 1

    def frame_indices_for_ra2_facing(self, facing: int) -> list[int]:
        if self.frames <= 0:
            return []
        facing = max(0, min(7, int(facing)))
        base = self.start + (facing * self.facing_stride if self.directional else 0)
        result = [base + index for index in range(self.frames)]
        if self.reverse:
            result.reverse()
        return result

    def frame_indices_for_godot_facing(self, facing: int) -> list[int]:
        ra2_facing = GODOT_TO_RA2_FACING[int(facing) % 8]
        return self.frame_indices_for_ra2_facing(ra2_facing)

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "start": self.start,
            "frames": self.frames,
            "facing_stride": self.facing_stride,
            "directional": self.directional,
            "facing_count": self.facing_count,
            "facing_override": self.facing_override,
            "reverse": self.reverse,
            "extra": list(self.raw_extra),
            "ra2_facing_order": list(RA2_FACING_NAMES),
            "godot_to_ra2": list(GODOT_TO_RA2_FACING),
            "godot_frames": {
                str(facing): self.frame_indices_for_godot_facing(facing)
                for facing in range(8 if self.directional else 1)
            },
        }


def parse_sequence_entry(name: str, raw: str) -> SequenceEntry | None:
    fields = [item.strip() for item in raw.split(",")]
    if len(fields) < 3:
        return None
    try:
        start = int(fields[0])
        frames = int(fields[1])
        stride = int(fields[2])
    except ValueError:
        return None

    extras = tuple(item for item in fields[3:] if item)
    facing_override = ""
    reverse = False
    for item in extras:
        upper = item.upper()
        if upper in RA2_FACING_NAMES:
            facing_override = upper
        elif upper in {"R", "REVERSE"}:
            reverse = True
    return SequenceEntry(
        name=name,
        start=max(0, start),
        frames=max(0, frames),
        facing_stride=max(0, stride),
        facing_override=facing_override,
        reverse=reverse,
        raw_extra=extras,
    )

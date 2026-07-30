from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Protocol
import zipfile

from ra2_ini import IniDocument, RA2MapError
from ra2_tmp import TmpFile


@dataclass(frozen=True)
class TileSetDefinition:
    index: int
    name: str
    file_name: str
    tiles_in_set: int
    first_tile_index: int
    marble_madness: int | None
    non_marble_madness: int | None
    morphable: bool
    shadow_caster: bool
    allow_to_place: bool
    allow_burrowing: bool
    allow_tiberium: bool

    @property
    def last_tile_index(self) -> int:
        return self.first_tile_index + self.tiles_in_set - 1


@dataclass(frozen=True)
class ResolvedTile:
    tile_index: int
    tile_set: int
    ordinal: int
    filename: str
    definition: TileSetDefinition


class ArchiveReader(Protocol):
    def has(self, name: str) -> bool: ...
    def read(self, name: str) -> bytes: ...
    def source_for(self, name: str) -> str: ...


class CaseInsensitiveZip:
    def __init__(self, path: Path) -> None:
        self.path = path
        self._zip = zipfile.ZipFile(path)
        self._names = {
            name.casefold(): name
            for name in self._zip.namelist()
            if not name.endswith("/")
        }

    def read(self, name: str) -> bytes:
        actual = self._names.get(name.casefold())
        if actual is None:
            raise RA2MapError(f"{name} not found in {self.path.name}")
        return self._zip.read(actual)

    def has(self, name: str) -> bool:
        return name.casefold() in self._names

    def source_for(self, name: str) -> str:
        if not self.has(name):
            raise RA2MapError(f"{name} not found in {self.path.name}")
        return self.path.name

    def close(self) -> None:
        self._zip.close()


class ArchiveStack:
    """Case-insensitive lookup across IsoTemp and optional Temperat archives.

    The first archive wins. WAE uses IsoTemp.mix as the main TMP source and
    Temperat.mix as optional content, so callers should pass archives in that order.
    """

    def __init__(self, archives: Iterable[ArchiveReader]) -> None:
        self.archives = tuple(archives)
        if not self.archives:
            raise RA2MapError("At least one theater archive is required")

    def has(self, name: str) -> bool:
        return any(archive.has(name) for archive in self.archives)

    def read(self, name: str) -> bytes:
        for archive in self.archives:
            if archive.has(name):
                return archive.read(name)
        sources = ", ".join(
            getattr(archive, "path", Path("archive")).name
            for archive in self.archives
        )
        raise RA2MapError(f"{name} not found in theater archives: {sources}")

    def source_for(self, name: str) -> str:
        for archive in self.archives:
            if archive.has(name):
                return archive.source_for(name)
        raise RA2MapError(f"{name} not found in theater archive stack")

    def close(self) -> None:
        for archive in self.archives:
            close = getattr(archive, "close", None)
            if callable(close):
                close()


class TheaterCatalog:
    def __init__(self, document: IniDocument, extension: str = ".tem") -> None:
        self.document = document
        self.extension = extension if extension.startswith(".") else f".{extension}"
        self.general = {entry.key: entry.value for entry in document.entries("General")}
        self.tile_sets: list[TileSetDefinition] = []
        self._ranges: list[tuple[int, int, TileSetDefinition]] = []
        first_tile_index = 0
        section_index = 0
        while True:
            section = f"TileSet{section_index:04d}"
            if not document.has_section(section):
                break

            def value(key: str, default: str = "") -> str:
                return document.value(section, key, default)

            count = _integer(value("TilesInSet", "0"), section, "TilesInSet")
            if count < 0:
                raise RA2MapError(f"[{section}] TilesInSet cannot be negative")
            definition = TileSetDefinition(
                index=section_index,
                name=value("SetName", section),
                file_name=value("FileName", "blank"),
                tiles_in_set=count,
                first_tile_index=first_tile_index,
                marble_madness=_optional_integer(value("MarbleMadness", "")),
                non_marble_madness=_optional_integer(value("NonMarbleMadness", "")),
                morphable=_boolean(value("Morphable", "no")),
                shadow_caster=_boolean(value("ShadowCaster", "no")),
                allow_to_place=_boolean(value("AllowToPlace", "yes")),
                allow_burrowing=_boolean(value("AllowBurrowing", "yes")),
                allow_tiberium=_boolean(value("AllowTiberium", "no")),
            )
            self.tile_sets.append(definition)
            if count > 0:
                self._ranges.append(
                    (first_tile_index, first_tile_index + count, definition)
                )
                first_tile_index += count
            section_index += 1
        self.tile_count = first_tile_index

    @classmethod
    def from_path(cls, path: Path, extension: str = ".tem") -> "TheaterCatalog":
        return cls(IniDocument.from_path(path), extension)

    def resolve(self, tile_index: int) -> ResolvedTile:
        if tile_index < 0:
            raise RA2MapError(f"Negative TileIndex: {tile_index}")
        for start, end, definition in self._ranges:
            if start <= tile_index < end:
                ordinal = tile_index - start + 1
                return ResolvedTile(
                    tile_index=tile_index,
                    tile_set=definition.index,
                    ordinal=ordinal,
                    filename=f"{definition.file_name}{ordinal:02d}{self.extension}".lower(),
                    definition=definition,
                )
        raise RA2MapError(
            f"TileIndex {tile_index} outside theater catalog 0..{self.tile_count - 1}"
        )

    def validate_archive(self, archive: ArchiveReader) -> list[str]:
        missing: list[str] = []
        for tile_index in range(self.tile_count):
            resolved = self.resolve(tile_index)
            if not archive.has(resolved.filename):
                missing.append(resolved.filename)
        return missing

    def load_tmp(self, tile_index: int, archive: ArchiveReader) -> TmpFile:
        resolved = self.resolve(tile_index)
        return TmpFile.from_bytes(
            archive.read(resolved.filename), source_name=resolved.filename
        )


def _boolean(value: str) -> bool:
    return value.strip().casefold() not in ("", "0", "false", "no", "none")


def _optional_integer(value: str) -> int | None:
    value = value.strip()
    return None if not value else int(value)


def _integer(value: str, section: str, key: str) -> int:
    try:
        return int(value.strip())
    except ValueError as exc:
        raise RA2MapError(f"[{section}] {key} must be an integer: {value!r}") from exc

from __future__ import annotations

from dataclasses import dataclass
import hashlib
from pathlib import Path
from typing import Iterable

THEATERS = {
    "temperate": {"letter": "T", "art_dir": ("temperat", "generic"), "iso_dir": ("isotemp", "isogen"), "unit_palette": "unittem.pal", "iso_palette": "isotem.pal"},
    "snow": {"letter": "A", "art_dir": ("snow", "generic"), "iso_dir": ("isosnow", "isogen"), "unit_palette": "unitsno.pal", "iso_palette": "isosno.pal"},
    "urban": {"letter": "U", "art_dir": ("urban", "generic"), "iso_dir": ("isourb", "isogen"), "unit_palette": "uniturb.pal", "iso_palette": "isourb.pal"},
    "desert": {"letter": "D", "art_dir": ("desert", "genermd", "generic"), "iso_dir": ("isodes", "isogenmd", "isogen"), "unit_palette": "unitdes.pal", "iso_palette": "isodes.pal"},
    "lunar": {"letter": "L", "art_dir": ("lunar", "genermd", "generic"), "iso_dir": ("isolun", "isogenmd", "isogen"), "unit_palette": "unitlun.pal", "iso_palette": "isolun.pal"},
    "newurban": {"letter": "N", "art_dir": ("urbann", "genermd", "generic"), "iso_dir": ("isoubn", "isogenmd", "isogen"), "unit_palette": "unitubn.pal", "iso_palette": "isoubn.pal"},
}

SUPPORTED_EXTENSIONS = {
    ".shp", ".sha", ".vxl", ".hva", ".pal", ".vpl", ".aud", ".wav",
    ".pcx", ".fnt", ".tem", ".sno", ".urb", ".des", ".lun", ".ubn",
    ".ini", ".map", ".mpr", ".pkt", ".mrf",
}


@dataclass(frozen=True)
class AssetRecord:
    asset_id: int
    pack: str
    root: str
    relative_path: str
    folder: str
    filename: str
    stem: str
    extension: str
    size: int
    sha1: str

    @property
    def absolute_path(self) -> Path:
        return Path(self.root) / self.relative_path

    def to_dict(self) -> dict[str, object]:
        return {
            "asset_id": self.asset_id,
            "pack": self.pack,
            "relative_path": self.relative_path,
            "folder": self.folder,
            "filename": self.filename,
            "stem": self.stem,
            "extension": self.extension,
            "size": self.size,
            "sha1": self.sha1,
        }


class AssetIndex:
    def __init__(self) -> None:
        self.records: list[AssetRecord] = []
        self.by_filename: dict[str, list[AssetRecord]] = {}
        self.by_stem: dict[str, list[AssetRecord]] = {}
        self.pack_priority: dict[str, int] = {}

    def scan(self, roots: Iterable[tuple[str, str | Path]]) -> None:
        for priority, (pack, root_value) in enumerate(roots):
            self.pack_priority[pack.casefold()] = priority
            root = Path(root_value).resolve()
            for path in sorted(root.rglob("*")):
                if not path.is_file():
                    continue
                extension = path.suffix.lower()
                if extension not in SUPPORTED_EXTENSIONS:
                    continue
                relative = path.relative_to(root).as_posix()
                folder = relative.split("/", 1)[0].casefold() if "/" in relative else ""
                digest = hashlib.sha1(path.read_bytes()).hexdigest()
                record = AssetRecord(
                    asset_id=len(self.records),
                    pack=pack,
                    root=str(root),
                    relative_path=relative,
                    folder=folder,
                    filename=path.name.casefold(),
                    stem=path.stem.casefold(),
                    extension=extension,
                    size=path.stat().st_size,
                    sha1=digest,
                )
                self.records.append(record)
                self.by_filename.setdefault(record.filename, []).append(record)
                self.by_stem.setdefault(record.stem, []).append(record)

    def _score(self, record: AssetRecord, preferred_folders: tuple[str, ...]) -> tuple[int, int, str]:
        pack_score = self.pack_priority.get(record.pack.casefold(), 0) * 100
        try:
            folder_score = (len(preferred_folders) - preferred_folders.index(record.folder)) * 10
        except ValueError:
            folder_score = 0
        return pack_score + folder_score, -len(record.relative_path), record.relative_path

    def candidates(self, stem: str, extensions: Iterable[str] | None = None) -> list[AssetRecord]:
        result = list(self.by_stem.get(stem.casefold(), []))
        if extensions is not None:
            allowed = {item.casefold() for item in extensions}
            result = [record for record in result if record.extension in allowed]
        return result

    def resolve(self, stem: str, extensions: Iterable[str], preferred_folders: Iterable[str] = ()) -> AssetRecord | None:
        preferred = tuple(item.casefold() for item in preferred_folders)
        candidates = self.candidates(stem, extensions)
        if not candidates:
            return None
        return max(candidates, key=lambda item: self._score(item, preferred))

    def resolve_filename(self, filename: str, preferred_folders: Iterable[str] = ()) -> AssetRecord | None:
        preferred = tuple(item.casefold() for item in preferred_folders)
        candidates = list(self.by_filename.get(filename.casefold(), []))
        if not candidates:
            return None
        return max(candidates, key=lambda item: self._score(item, preferred))

    @staticmethod
    def theater_stem(stem: str, theater: str, new_theater: bool) -> str:
        if not new_theater or len(stem) < 2:
            return stem
        info = THEATERS.get(theater, THEATERS["temperate"])
        return stem[0] + str(info["letter"]) + stem[2:]

    def resolve_shp(self, stem: str, *, theater: str = "temperate", new_theater: bool = False, role: str = "body") -> AssetRecord | None:
        info = THEATERS.get(theater, THEATERS["temperate"])
        art_dirs = tuple(info["iso_dir"] if role in {"buildup", "bib", "overlay"} else info["art_dir"])
        common = ("conqmd", "conquer", "localmd", "local", "ntrlmd", "neutral", "genermd", "generic", "cachemd", "cache")
        preferred = art_dirs + common
        exact = self.theater_stem(stem.casefold(), theater, new_theater)
        generic = stem[0] + "g" + stem[2:] if new_theater and len(stem) >= 2 else stem
        for candidate in dict.fromkeys((exact, generic, stem.casefold())):
            result = self.resolve(candidate, (".shp", ".sha"), preferred)
            if result is not None:
                return result
        return None

    def resolve_voxel_part(self, stem: str, extension: str) -> AssetRecord | None:
        return self.resolve(stem, (extension,), ("localmd", "local", "conqmd", "conquer"))

    def resolve_palette(self, palette_name: str) -> AssetRecord | None:
        return self.resolve_filename(palette_name, ("cachemd", "cache", "localmd", "local", "loadmd", "load"))

    def summary(self) -> dict[str, object]:
        extension_counts: dict[str, int] = {}
        pack_counts: dict[str, int] = {}
        for record in self.records:
            extension_counts[record.extension] = extension_counts.get(record.extension, 0) + 1
            pack_counts[record.pack] = pack_counts.get(record.pack, 0) + 1
        return {
            "asset_count": len(self.records),
            "extension_counts": dict(sorted(extension_counts.items())),
            "pack_counts": dict(sorted(pack_counts.items())),
        }

from __future__ import annotations

import base64
from collections import OrderedDict
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


class RA2MapError(ValueError):
    """Raised when a Westwood INI/map container is malformed."""


@dataclass(frozen=True)
class IniEntry:
    key: str
    value: str
    line_number: int


class IniDocument:
    """Small order-preserving INI reader for RA2/YR map files.

    Standard configparser is unsuitable here because map files may contain
    duplicate keys, comments, unknown sections and values that must remain
    byte-for-byte meaningful for later round-trip support.
    """

    def __init__(self) -> None:
        self.sections: "OrderedDict[str, list[IniEntry]]" = OrderedDict()
        self.source_encoding: str = "utf-8"

    @classmethod
    def from_path(cls, path: Path) -> "IniDocument":
        return cls.from_bytes(path.read_bytes())

    @classmethod
    def from_bytes(cls, payload: bytes) -> "IniDocument":
        text, encoding = _decode_text(payload)
        document = cls()
        document.source_encoding = encoding
        document._parse(text)
        return document

    def _parse(self, text: str) -> None:
        current_section = ""
        self.sections.setdefault(current_section, [])
        for line_number, raw_line in enumerate(text.splitlines(), start=1):
            stripped = raw_line.strip()
            if not stripped or stripped.startswith(";") or stripped.startswith("#"):
                continue
            if stripped.startswith("[") and stripped.endswith("]"):
                current_section = stripped[1:-1].strip()
                if not current_section:
                    raise RA2MapError(f"Empty section name at line {line_number}")
                self.sections.setdefault(current_section, [])
                continue
            if "=" not in raw_line:
                # RA2 files occasionally contain editor noise. Preserve the
                # parser's tolerance but never reinterpret it as a key/value.
                continue
            key, value = raw_line.split("=", 1)
            key = key.strip()
            if not key:
                raise RA2MapError(f"Empty key at line {line_number}")
            self.sections.setdefault(current_section, []).append(
                IniEntry(key=key, value=value.strip(), line_number=line_number)
            )

    def entries(self, section: str) -> tuple[IniEntry, ...]:
        return tuple(self.sections.get(section, ()))

    def has_section(self, section: str) -> bool:
        return section in self.sections

    def value(self, section: str, key: str, default: str = "") -> str:
        for entry in reversed(self.sections.get(section, ())):
            if entry.key.casefold() == key.casefold():
                return entry.value
        return default

    def values(self, section: str, key: str) -> list[str]:
        return [
            entry.value
            for entry in self.sections.get(section, ())
            if entry.key.casefold() == key.casefold()
        ]


def _decode_text(payload: bytes) -> tuple[str, str]:
    for encoding in ("utf-8-sig", "gb18030", "cp1252"):
        try:
            return payload.decode(encoding), encoding
        except UnicodeDecodeError:
            pass
    # cp1252 should decode every byte, but keep a deterministic fallback.
    return payload.decode("latin-1"), "latin-1"


def _section_sort_key(entry: IniEntry) -> tuple[int, int | str, int]:
    try:
        return (0, int(entry.key), entry.line_number)
    except ValueError:
        return (1, entry.key.casefold(), entry.line_number)


def concatenated_section_value(document: IniDocument, section: str) -> str:
    entries = sorted(document.entries(section), key=_section_sort_key)
    return "".join(entry.value.strip() for entry in entries)


def decode_section(document: IniDocument, section: str) -> bytes:
    encoded = concatenated_section_value(document, section)
    if not encoded:
        return b""
    try:
        return base64.b64decode(encoded, validate=True)
    except ValueError as exc:
        raise RA2MapError(f"[{section}] contains invalid Base64 data") from exc


def section_dict(document: IniDocument, section: str) -> dict[str, str]:
    return {entry.key: entry.value for entry in document.entries(section)}


def write_section_lines(name: str, values: Iterable[tuple[str, str]]) -> list[str]:
    lines = [f"[{name}]"]
    lines.extend(f"{key}={value}" for key, value in values)
    lines.append("")
    return lines

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, Iterator


_ENCODINGS = ("utf-8-sig", "gb18030", "cp1252", "latin1")


def decode_text(raw: bytes) -> tuple[str, str]:
    for encoding in _ENCODINGS:
        try:
            return raw.decode(encoding), encoding
        except UnicodeDecodeError:
            continue
    return raw.decode("latin1", errors="replace"), "latin1-replace"


def strip_comment(line: str) -> str:
    # Westwood's shipped INIs do not use quoted semicolons. Keeping this
    # deliberately strict avoids accidentally interpreting documentation text.
    return line.split(";", 1)[0].strip()


@dataclass(frozen=True)
class Origin:
    layer: str
    file: str
    line: int
    section: str
    key: str
    value: str

    def to_dict(self) -> dict[str, object]:
        return {
            "layer": self.layer,
            "file": self.file,
            "line": self.line,
            "section": self.section,
            "key": self.key,
            "value": self.value,
        }


@dataclass
class MergedValue:
    key: str
    value: str
    origin: Origin
    history: list[Origin] = field(default_factory=list)

    def to_dict(self) -> dict[str, object]:
        return {
            "value": self.value,
            "origin": self.origin.to_dict(),
            "history": [item.to_dict() for item in self.history],
        }


@dataclass
class ParsedSection:
    name: str
    keys: dict[str, MergedValue] = field(default_factory=dict)
    key_order: list[str] = field(default_factory=list)

    def get(self, key: str, default: str | None = None) -> str | None:
        entry = self.keys.get(key.casefold())
        return entry.value if entry is not None else default

    def entry(self, key: str) -> MergedValue | None:
        return self.keys.get(key.casefold())

    def items(self) -> Iterator[tuple[str, str]]:
        for folded in self.key_order:
            item = self.keys[folded]
            yield item.key, item.value

    def values_dict(self) -> dict[str, str]:
        return {key: value for key, value in self.items()}

    def provenance_dict(self) -> dict[str, dict[str, object]]:
        return {self.keys[key].key: self.keys[key].to_dict() for key in self.key_order}


@dataclass
class ParsedIni:
    sections: dict[str, ParsedSection] = field(default_factory=dict)
    section_order: list[str] = field(default_factory=list)
    encodings: dict[str, str] = field(default_factory=dict)
    parse_warnings: list[dict[str, object]] = field(default_factory=list)

    def get_section(self, name: str) -> ParsedSection | None:
        return self.sections.get(name.casefold())

    def require_section(self, name: str) -> ParsedSection:
        section = self.get_section(name)
        if section is None:
            return ParsedSection(name)
        return section

    def section_names(self) -> list[str]:
        return [self.sections[key].name for key in self.section_order]

    def merge_layer(self, other: "ParsedIni") -> None:
        self.encodings.update(other.encodings)
        self.parse_warnings.extend(other.parse_warnings)
        for folded_section in other.section_order:
            incoming = other.sections[folded_section]
            target = self.sections.get(folded_section)
            if target is None:
                target = ParsedSection(incoming.name)
                self.sections[folded_section] = target
                self.section_order.append(folded_section)
            for folded_key in incoming.key_order:
                new_value = incoming.keys[folded_key]
                old_value = target.keys.get(folded_key)
                history: list[Origin] = []
                if old_value is not None:
                    history.extend(old_value.history)
                    history.append(old_value.origin)
                history.extend(new_value.history)
                target.keys[folded_key] = MergedValue(
                    key=new_value.key,
                    value=new_value.value,
                    origin=new_value.origin,
                    history=history,
                )
                if folded_key not in target.key_order:
                    target.key_order.append(folded_key)


def parse_ini_bytes(raw: bytes, *, file_name: str, layer: str) -> ParsedIni:
    text, encoding = decode_text(raw)
    result = ParsedIni(encodings={file_name: encoding})
    current: ParsedSection | None = None

    for line_number, raw_line in enumerate(text.splitlines(), start=1):
        stripped = raw_line.strip()
        if not stripped or stripped.startswith(";"):
            continue
        clean = strip_comment(raw_line)
        if not clean:
            continue
        if clean.startswith("[") and "]" in clean:
            name = clean[1 : clean.index("]")].strip()
            if not name:
                result.parse_warnings.append({
                    "type": "empty_section",
                    "file": file_name,
                    "line": line_number,
                })
                current = None
                continue
            folded = name.casefold()
            current = result.sections.get(folded)
            if current is None:
                current = ParsedSection(name)
                result.sections[folded] = current
                result.section_order.append(folded)
            continue
        if current is None:
            result.parse_warnings.append({
                "type": "key_outside_section",
                "file": file_name,
                "line": line_number,
                "text": clean,
            })
            continue
        if "=" not in clean:
            result.parse_warnings.append({
                "type": "malformed_line",
                "file": file_name,
                "line": line_number,
                "section": current.name,
                "text": clean,
            })
            continue
        key, value = clean.split("=", 1)
        key = key.strip()
        value = value.strip()
        if not key:
            continue
        folded_key = key.casefold()
        origin = Origin(layer, file_name, line_number, current.name, key, value)
        old = current.keys.get(folded_key)
        history = [] if old is None else [*old.history, old.origin]
        current.keys[folded_key] = MergedValue(key, value, origin, history)
        if folded_key not in current.key_order:
            current.key_order.append(folded_key)
    return result


def parse_ini_file(path: str | Path, *, layer: str) -> ParsedIni:
    path = Path(path)
    return parse_ini_bytes(path.read_bytes(), file_name=path.name, layer=layer)


def merge_ini_layers(layers: Iterable[ParsedIni]) -> ParsedIni:
    merged = ParsedIni()
    for layer in layers:
        merged.merge_layer(layer)
    return merged


def ordered_values(section: ParsedSection | None) -> list[str]:
    if section is None:
        return []
    sortable: list[tuple[int, int, str]] = []
    for index, (key, value) in enumerate(section.items()):
        try:
            numeric = int(key)
        except ValueError:
            numeric = 1_000_000_000
        sortable.append((numeric, index, value))
    return [value for _, _, value in sorted(sortable)]

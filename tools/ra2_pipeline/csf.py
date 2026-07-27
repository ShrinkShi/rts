from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import struct
from typing import Any, Iterable

FILE_MAGIC = b" FSC"
LABEL_MAGIC = b" LBL"
VALUE_MAGIC = b" RTS"
EXTRA_VALUE_MAGIC = b"WRTS"


@dataclass(frozen=True)
class CsfValue:
    text: str
    extra: str | None = None

    def to_dict(self) -> dict[str, Any]:
        result: dict[str, Any] = {"text": self.text}
        if self.extra is not None:
            result["extra"] = self.extra
        return result


@dataclass(frozen=True)
class CsfEntry:
    label: str
    values: tuple[CsfValue, ...]
    source: str
    layer: str
    index: int

    def to_dict(self) -> dict[str, Any]:
        return {
            "label": self.label,
            "values": [value.to_dict() for value in self.values],
            "source": self.source,
            "layer": self.layer,
            "index": self.index,
        }


@dataclass(frozen=True)
class CsfFile:
    path: Path
    version: int
    language_id: int
    entries: tuple[CsfEntry, ...]

    @classmethod
    def parse(cls, path: str | Path, *, layer: str) -> "CsfFile":
        source_path = Path(path)
        data = source_path.read_bytes()
        if len(data) < 24 or data[:4] != FILE_MAGIC:
            raise ValueError(f"Invalid CSF header: {source_path}")
        version, label_count, value_count, _reserved, language_id = struct.unpack_from("<IIIII", data, 4)
        offset = 24
        entries: list[CsfEntry] = []
        parsed_values = 0
        for entry_index in range(label_count):
            if data[offset:offset + 4] != LABEL_MAGIC:
                raise ValueError(f"Invalid CSF label marker at {offset}: {source_path}")
            offset += 4
            item_count, label_length = struct.unpack_from("<II", data, offset)
            offset += 8
            label_bytes = data[offset:offset + label_length]
            offset += label_length
            label = label_bytes.decode("ascii", errors="replace")
            values: list[CsfValue] = []
            for _ in range(item_count):
                marker = data[offset:offset + 4]
                offset += 4
                if marker not in (VALUE_MAGIC, EXTRA_VALUE_MAGIC):
                    raise ValueError(f"Invalid CSF value marker {marker!r} at {offset - 4}: {source_path}")
                text_length = struct.unpack_from("<I", data, offset)[0]
                offset += 4
                encoded = data[offset:offset + text_length * 2]
                offset += text_length * 2
                decoded = bytes((~value) & 0xFF for value in encoded).decode("utf-16le", errors="replace")
                extra: str | None = None
                if marker == EXTRA_VALUE_MAGIC:
                    extra_length = struct.unpack_from("<I", data, offset)[0]
                    offset += 4
                    extra = data[offset:offset + extra_length].decode("latin1", errors="replace")
                    offset += extra_length
                values.append(CsfValue(decoded, extra))
                parsed_values += 1
            entries.append(CsfEntry(label, tuple(values), source_path.name, layer, entry_index))
        if parsed_values != value_count:
            raise ValueError(f"CSF value count mismatch in {source_path}: header={value_count}, parsed={parsed_values}")
        if offset != len(data):
            raise ValueError(f"CSF trailing bytes in {source_path}: consumed={offset}, size={len(data)}")
        return cls(source_path, version, language_id, tuple(entries))


def merge_csf_layers(files: Iterable[CsfFile]) -> dict[str, Any]:
    merged: dict[str, dict[str, Any]] = {}
    file_summaries: list[dict[str, Any]] = []
    for csf_file in files:
        file_summaries.append({
            "source": csf_file.path.name,
            "version": csf_file.version,
            "language_id": csf_file.language_id,
            "entry_count": len(csf_file.entries),
        })
        for entry in csf_file.entries:
            key = entry.label.casefold()
            payload = entry.to_dict()
            if key in merged:
                payload["history"] = [
                    *merged[key].get("history", []),
                    {key_name: value for key_name, value in merged[key].items() if key_name != "history"},
                ]
            merged[key] = payload
    entries = sorted(merged.values(), key=lambda item: str(item["label"]).casefold())
    return {
        "schema_version": 1,
        "files": file_summaries,
        "entry_count": len(entries),
        "entries": entries,
        "lookup": {
            str(entry["label"]): (entry.get("values") or [{"text": ""}])[0].get("text", "")
            for entry in entries
        },
    }

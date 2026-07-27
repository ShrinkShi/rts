from __future__ import annotations

from pathlib import Path
import shutil
from typing import Any, Iterable

from .westwood_ini import parse_ini_file


def _integer(value: str | None, default: int = 0) -> int:
    try:
        return int(str(value or default).strip())
    except ValueError:
        return default


def _parse_rect(value: str | None) -> tuple[int, int, int, int]:
    parts = [part.strip() for part in str(value or "").split(",")]
    if len(parts) != 4:
        return (0, 0, 0, 0)
    try:
        return tuple(int(part) for part in parts)  # type: ignore[return-value]
    except ValueError:
        return (0, 0, 0, 0)


def _map_record(path: Path, source: str, resource_path: str) -> dict[str, Any]:
    parsed = parse_ini_file(path, layer=source)
    basic = parsed.get_section("Basic")
    map_section = parsed.get_section("Map")
    waypoints = parsed.get_section("Waypoints")
    raw_size = map_section.get("Size", "") if map_section else ""
    raw_local_size = map_section.get("LocalSize", "") if map_section else ""
    size_x, size_y, size_width, size_height = _parse_rect(raw_size)
    local_x, local_y, local_width, local_height = _parse_rect(raw_local_size)
    explicit_width = _integer(map_section.get("Width") if map_section else None)
    explicit_height = _integer(map_section.get("Height") if map_section else None)
    record: dict[str, Any] = {
        "id": path.stem,
        "filename": path.name,
        "source": source,
        "resource_path": resource_path,
        "name": basic.get("Name", path.stem) if basic else path.stem,
        "author": basic.get("Author", "") if basic else "",
        "game_mode": basic.get("GameMode", "") if basic else "",
        "multiplayer_only": str(basic.get("MultiplayerOnly", "no") if basic else "no").casefold() in {"yes", "true", "1"},
        "official": str(basic.get("Official", "no") if basic else "no").casefold() in {"yes", "true", "1"},
        "theater": map_section.get("Theater", "") if map_section else "",
        "width": explicit_width or size_width,
        "height": explicit_height or size_height,
        "origin_x": size_x,
        "origin_y": size_y,
        "local_x": local_x,
        "local_y": local_y,
        "local_width": local_width,
        "local_height": local_height,
        "local_size": raw_local_size,
        "size": raw_size,
        "waypoint_count": len(waypoints.keys) if waypoints else 0,
        "section_count": len(parsed.sections),
        "trigger_count": len(parsed.get_section("Triggers").keys) if parsed.get_section("Triggers") else 0,
        "team_type_count": len(parsed.get_section("TeamTypes").keys) if parsed.get_section("TeamTypes") else 0,
        "script_type_count": len(parsed.get_section("ScriptTypes").keys) if parsed.get_section("ScriptTypes") else 0,
        "task_force_count": len(parsed.get_section("TaskForces").keys) if parsed.get_section("TaskForces") else 0,
    }
    return record


def build_map_index(sources: Iterable[tuple[str, Path]], output_dir: Path, *, resource_prefix: str) -> list[dict[str, Any]]:
    output_dir.mkdir(parents=True, exist_ok=True)
    records: list[dict[str, Any]] = []
    used_names: set[str] = set()
    for source_name, source_root in sources:
        for path in sorted(source_root.rglob("*")):
            if not path.is_file() or path.suffix.casefold() not in {".map", ".mpr"}:
                continue
            filename = path.name.casefold()
            if filename in used_names:
                filename = f"{source_name}_{filename}"
            used_names.add(filename)
            shutil.copy2(path, output_dir / filename)
            records.append(_map_record(path, source_name, f"{resource_prefix.rstrip('/')}/{filename}"))
    return sorted(records, key=lambda item: (str(item["name"]).casefold(), str(item["id"]).casefold()))

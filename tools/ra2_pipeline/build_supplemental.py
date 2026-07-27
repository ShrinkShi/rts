#!/usr/bin/env python3
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import shutil
import sys
from typing import Any

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from ra2_pipeline.audio_bag import AudioBag, copy_standalone_wavs
    from ra2_pipeline.csf import CsfFile, merge_csf_layers
    from ra2_pipeline.map_index import build_map_index
else:
    from .audio_bag import AudioBag, copy_standalone_wavs
    from .csf import CsfFile, merge_csf_layers
    from .map_index import build_map_index


def read_json(path: Path, default: Any) -> Any:
    if not path.is_file():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")


def parse_extra(value: str) -> tuple[str, Path]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("extra source must be NAME=PATH")
    name, path = value.split("=", 1)
    source = Path(path).resolve()
    if not source.is_dir():
        raise argparse.ArgumentTypeError(f"extra source is not a directory: {source}")
    return name.strip(), source


def localized_text(lookup: dict[str, str], token: str, fallback: str) -> str:
    if not token:
        return fallback
    return lookup.get(token.casefold(), fallback)


def clean_sound_token(token: str) -> str:
    return token.strip().strip(",").lstrip("$").casefold()


def source_manifest(extra_sources: list[tuple[str, Path]]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for source_name, root in extra_sources:
        files: list[dict[str, Any]] = []
        for path in sorted(root.rglob("*")):
            if not path.is_file():
                continue
            data = path.read_bytes()
            files.append({
                "path": path.relative_to(root).as_posix(),
                "size": len(data),
                "sha256": hashlib.sha256(data).hexdigest(),
            })
        result.append({"source": source_name, "file_count": len(files), "files": files})
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Add CSF localization, BAG/IDX audio and official maps to the RA2/YR database")
    parser.add_argument("--project", required=True, type=Path)
    parser.add_argument("--ra2-csf", required=True, type=Path)
    parser.add_argument("--ra2md-csf", required=True, type=Path)
    parser.add_argument("--audio-root", required=True, type=Path, help="RA2 audio.idx/audio.bag and standalone WAV root")
    parser.add_argument("--audio-md-root", type=Path, help="YR audiomd audio.idx/audio.bag and standalone WAV root")
    parser.add_argument("--extra", action="append", default=[], type=parse_extra)
    arguments = parser.parse_args()

    project = arguments.project.resolve()
    data_root = project / "data" / "ra2"
    assets_root = project / "assets"
    extra_sources: list[tuple[str, Path]] = list(arguments.extra)

    # Localization: YR is the higher-priority layer, while retaining the RA2 history.
    localization = merge_csf_layers((
        CsfFile.parse(arguments.ra2_csf, layer="ra2"),
        CsfFile.parse(arguments.ra2md_csf, layer="ra2md"),
    ))
    lookup = {str(key).casefold(): str(value) for key, value in localization["lookup"].items()}
    write_json(data_root / "localization.json", localization)
    write_json(data_root / "localization_catalog.json", [
        {
            "label": entry["label"],
            "text": (entry.get("values") or [{"text": ""}])[0].get("text", ""),
            "source": entry.get("source", ""),
            "layer": entry.get("layer", ""),
            "history_count": len(entry.get("history", [])),
        }
        for entry in localization["entries"]
    ])

    catalog = read_json(data_root / "catalog.json", [])
    entity_by_id: dict[str, dict[str, Any]] = {}
    localized_entity_count = 0
    resolved_entity_sound_count = 0

    # Audio archive extraction. RA2 and YR use separate banks; later banks override
    # duplicate sample names while both physical assets and provenance are retained.
    audio_target = assets_root / "ra2_audio"
    if audio_target.exists():
        shutil.rmtree(audio_target)
    bank_inputs: list[tuple[str, Path]] = [("ra2", arguments.audio_root.resolve())]
    if arguments.audio_md_root is not None:
        bank_inputs.append(("ra2md", arguments.audio_md_root.resolve()))

    all_bag_manifest: list[dict[str, Any]] = []
    all_standalone_manifest: list[dict[str, Any]] = []
    bank_manifest: list[dict[str, Any]] = []
    sample_lookup: dict[str, dict[str, Any]] = {}
    shadowed_samples: dict[str, list[dict[str, Any]]] = {}

    for priority, (bank_id, bank_root) in enumerate(bank_inputs):
        idx_path = bank_root / "audio.idx"
        bag_path = bank_root / "audio.bag"
        if not idx_path.is_file() or not bag_path.is_file():
            raise FileNotFoundError(f"Audio bank {bank_id} is missing audio.idx/audio.bag: {bank_root}")
        bag_archive = AudioBag(idx_path, bag_path)
        bag_items = bag_archive.extract(
            audio_target / bank_id / "bag",
            resource_prefix=f"res://assets/ra2_audio/{bank_id}/bag",
            source_bank=bank_id, source_priority=priority,
        )
        standalone_items = copy_standalone_wavs(
            bank_root, audio_target / bank_id / "standalone",
            resource_prefix=f"res://assets/ra2_audio/{bank_id}/standalone",
            source_bank=bank_id, source_priority=priority,
        )
        all_bag_manifest.extend(bag_items)
        all_standalone_manifest.extend(standalone_items)
        format_counts = {
            str(code): sum(1 for entry in bag_items if int(entry["format_code"]) == code)
            for code in sorted({int(entry["format_code"]) for entry in bag_items})
        }
        bank_manifest.append({
            "id": bank_id,
            "priority": priority,
            "bag_entry_count": len(bag_items),
            "standalone_wav_count": len(standalone_items),
            "format_counts": format_counts,
        })

        # BAG first, standalone WAV second within the same bank. The next bank then
        # overrides both, matching RA2 < YR source priority.
        for item in [*bag_items, *standalone_items]:
            key = str(item["name"]).casefold()
            previous = sample_lookup.get(key)
            if previous is not None:
                shadowed_samples.setdefault(key, []).append(previous)
            sample_lookup[key] = item

    bag_manifest = all_bag_manifest
    standalone_manifest = all_standalone_manifest

    raw_sound_events = read_json(data_root / "sounds.json", [])
    sound_events: list[dict[str, Any]] = []
    sound_event_lookup: dict[str, dict[str, Any]] = {}
    referenced_samples = 0
    resolved_samples = 0
    for event in raw_sound_events:
        values = event.get("raw_values", event.get("values", {}))
        tokens = [clean_sound_token(token) for token in re.split(r"\s+", str(values.get("Sounds", ""))) if clean_sound_token(token)]
        samples: list[dict[str, Any]] = []
        missing: list[str] = []
        for token in tokens:
            referenced_samples += 1
            sample = sample_lookup.get(token)
            if sample is None:
                missing.append(token)
            else:
                resolved_samples += 1
                samples.append(sample)
        enriched = {
            **event,
            "sample_tokens": tokens,
            "samples": samples,
            "missing_samples": missing,
            "resolved_sample_count": len(samples),
        }
        sound_events.append(enriched)
        sound_event_lookup[str(event.get("id", "")).casefold()] = enriched
    write_json(data_root / "sound_events.json", sound_events)
    write_json(data_root / "audio_manifest.json", {
        "schema_version": 2,
        "bank_count": len(bank_manifest),
        "banks": bank_manifest,
        "bag_entry_count": len(bag_manifest),
        "standalone_wav_count": len(standalone_manifest),
        "unique_sample_count": len(sample_lookup),
        "shadowed_sample_count": len(shadowed_samples),
        "resolution_priority": [item["id"] for item in bank_manifest],
        "format_counts": {
            str(code): sum(1 for entry in bag_manifest if int(entry["format_code"]) == code)
            for code in sorted({int(entry["format_code"]) for entry in bag_manifest})
        },
        "bag_entries": bag_manifest,
        "standalone_wavs": standalone_manifest,
        "shadowed_samples": shadowed_samples,
    })

    for catalog_entry in catalog:
        entity_path = data_root / str(catalog_entry.get("file", ""))
        entity = read_json(entity_path, {})
        if not entity:
            continue
        token = str(entity.get("name_token", entity.get("id", "")))
        display_name = localized_text(lookup, token, str(entity.get("id", "")))
        entity["display_name"] = display_name
        entity["localization"] = {
            "token": token,
            "resolved": display_name != str(entity.get("id", "")),
            "text": display_name,
        }
        if entity["localization"]["resolved"]:
            localized_entity_count += 1
        resolved_sounds: dict[str, Any] = {}
        for role, event_ids in (entity.get("sounds", {}) or {}).items():
            events: list[dict[str, Any]] = []
            for event_id in event_ids:
                event = sound_event_lookup.get(str(event_id).casefold())
                if event is None:
                    continue
                events.append({
                    "id": event.get("id", event_id),
                    "samples": event.get("samples", []),
                    "missing_samples": event.get("missing_samples", []),
                    "control": event.get("raw_values", {}).get("Control", ""),
                    "volume": event.get("raw_values", {}).get("Volume", ""),
                })
            if events:
                resolved_sounds[role] = events
                resolved_entity_sound_count += 1
        entity["resolved_sounds"] = resolved_sounds
        write_json(entity_path, entity)
        entity_by_id[str(entity.get("id", "")).casefold()] = entity
        catalog_entry["display_name"] = display_name
        catalog_entry["search_text"] = " ".join((
            str(entity.get("id", "")), display_name, token,
            str(entity.get("art_id", "")), " ".join(str(x) for x in entity.get("owners", [])),
        ))
    write_json(data_root / "catalog.json", catalog)

    # Localize countries/sides without destroying the original CSF token.
    countries_path = data_root / "countries.json"
    countries = read_json(countries_path, [])
    if isinstance(countries, list):
        for record in countries:
            if not isinstance(record, dict):
                continue
            values = record.get("values", {})
            token = str(values.get("UIName", values.get("Name", record.get("id", ""))))
            record["display_name"] = localized_text(lookup, token, str(record.get("id", token)))
            record["name_token"] = token
        write_json(countries_path, countries)

    sides_path = data_root / "sides.json"
    sides = read_json(sides_path, {})
    if isinstance(sides, dict):
        side_names = {
            "GDI": localized_text(lookup, "LoadBrief:Allied", "盟军"),
            "Nod": localized_text(lookup, "LoadBrief:Soviet", "苏军"),
            "ThirdSide": localized_text(lookup, "Name:YuriCountry", "尤里"),
            "Civilian": "平民",
            "Mutant": "特殊",
        }
        sides["display_names"] = side_names
        write_json(sides_path, sides)

    # Maps from official expansion archives.
    map_target = assets_root / "ra2_maps"
    if map_target.exists():
        shutil.rmtree(map_target)
    maps = build_map_index(extra_sources, map_target, resource_prefix="res://assets/ra2_maps")
    for record in maps:
        name = str(record.get("name", ""))
        record["display_name"] = localized_text(lookup, name, name)
    write_json(data_root / "maps_official.json", maps)
    write_json(data_root / "supplemental_sources.json", source_manifest(extra_sources))

    # Summary and full database are kept consistent with the split files.
    summary_path = data_root / "summary.json"
    summary = read_json(summary_path, {})
    summary.update({
        "localization_count": localization["entry_count"],
        "localized_entity_count": localized_entity_count,
        "audio_bank_count": len(bank_manifest),
        "audio_bag_entry_count": len(bag_manifest),
        "standalone_wav_count": len(standalone_manifest),
        "audio_unique_sample_count": len(sample_lookup),
        "audio_shadowed_sample_count": len(shadowed_samples),
        "sound_event_count": len(sound_events),
        "sound_sample_reference_count": referenced_samples,
        "sound_sample_resolved_count": resolved_samples,
        "sound_sample_resolution_ratio": round(resolved_samples / referenced_samples, 6) if referenced_samples else 1.0,
        "resolved_entity_sound_roles": resolved_entity_sound_count,
        "official_map_count": len(maps),
        "supplemental_source_count": len(extra_sources),
    })
    write_json(summary_path, summary)

    database_path = data_root / "database.json"
    database = read_json(database_path, {})
    if database:
        database["schema_version"] = 3
        database["summary"] = summary
        database["entities"] = [entity_by_id[str(item.get("id", "")).casefold()] for item in catalog if str(item.get("id", "")).casefold() in entity_by_id]
        database["sounds"] = sound_events
        database["localization"] = {
            "entry_count": localization["entry_count"],
            "path": "localization.json",
        }
        database["official_maps"] = maps
        write_json(database_path, database)
        with gzip.open(data_root / "database.json.gz", "wt", encoding="utf-8", compresslevel=9) as stream:
            json.dump(database, stream, ensure_ascii=False, separators=(",", ":"))

    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

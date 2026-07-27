#!/usr/bin/env python3
from __future__ import annotations

import json
import struct
import sys
from collections import Counter
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
PREVIEW_ROOT = PROJECT / "assets" / "ra2_preview"
AUDIO_ROOT = PROJECT / "assets" / "ra2_audio"


def load_json(path: Path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def resolve_preview_path(manifest_dir: Path, manifest: dict, theater: str | None, relative: str) -> Path:
    base = manifest_dir / theater if theater else manifest_dir
    return base / relative


def validate_preview_manifest(path: Path, errors: list[str], stats: Counter[str]) -> None:
    manifest = load_json(path)
    entity_id = str(manifest.get("entity_id", path.parent.name))
    stats[f"category:{manifest.get('category', 'unknown')}"] += 1
    stats[f"kind:{manifest.get('visual_kind', 'unknown')}"] += 1

    theater_blocks: list[tuple[str | None, dict]] = []
    if isinstance(manifest.get("theaters"), dict):
        for theater_name, theater_data in manifest["theaters"].items():
            if isinstance(theater_data, dict):
                theater_blocks.append((str(theater_name), theater_data))
    else:
        theater_blocks.append((None, manifest))

    found_animation = False
    for theater_name, block in theater_blocks:
        animations = block.get("animations", {})
        if not isinstance(animations, dict):
            errors.append(f"{entity_id}: animations is not a dictionary")
            continue
        for animation_name, animation in animations.items():
            if not isinstance(animation, dict):
                errors.append(f"{entity_id}/{animation_name}: invalid animation object")
                continue
            found_animation = True
            stats["animations"] += 1
            frame_sets: list[dict] = []
            if animation.get("directional"):
                directions = animation.get("directions", {})
                if not isinstance(directions, dict) or not directions:
                    errors.append(f"{entity_id}/{animation_name}: directional animation has no directions")
                    continue
                frame_sets.extend(v for v in directions.values() if isinstance(v, dict))
            else:
                frame_sets.append(animation)
            for frame_set in frame_sets:
                frames = frame_set.get("frames", [])
                masks = frame_set.get("remap_masks", [])
                if not isinstance(frames, list) or not frames:
                    errors.append(f"{entity_id}/{animation_name}: no frames")
                    continue
                stats["frames"] += len(frames)
                if masks and len(masks) != len(frames):
                    errors.append(f"{entity_id}/{animation_name}: mask/frame count mismatch")
                for relative in frames + (masks if isinstance(masks, list) else []):
                    target = resolve_preview_path(path.parent, manifest, theater_name, str(relative))
                    if not target.is_file():
                        errors.append(f"{entity_id}: missing preview asset {target.relative_to(PROJECT)}")
    if not found_animation:
        errors.append(f"{entity_id}: manifest has no animations")


def wav_format(path: Path) -> tuple[int, int, int]:
    data = path.read_bytes()[:256]
    if len(data) < 12 or data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise ValueError("not RIFF/WAVE")
    offset = 12
    while offset + 8 <= len(data):
        chunk_id = data[offset:offset + 4]
        chunk_size = struct.unpack_from("<I", data, offset + 4)[0]
        if chunk_id == b"fmt " and offset + 8 + chunk_size <= len(data):
            fmt, channels, rate = struct.unpack_from("<HHI", data, offset + 8)
            return fmt, channels, rate
        offset += 8 + chunk_size + (chunk_size & 1)
    raise ValueError("missing fmt chunk")


def main() -> int:
    errors: list[str] = []
    stats: Counter[str] = Counter()

    catalog_path = PREVIEW_ROOT / "catalog.json"
    if not catalog_path.is_file():
        errors.append("missing assets/ra2_preview/catalog.json")
    else:
        catalog = load_json(catalog_path)
        if not isinstance(catalog, list):
            errors.append("preview catalog is not an array")
        else:
            stats["preview_catalog_entries"] = len(catalog)
            catalog_ids = {str(item.get("entity_id", "")).lower() for item in catalog if isinstance(item, dict)}
            manifest_paths = sorted(PREVIEW_ROOT.glob("*/manifest.json"))
            stats["preview_manifests"] = len(manifest_paths)
            manifest_ids = {path.parent.name.lower() for path in manifest_paths}
            if catalog_ids != manifest_ids:
                errors.append(f"preview catalog/manifests differ: catalog-only={sorted(catalog_ids-manifest_ids)[:8]}, manifest-only={sorted(manifest_ids-catalog_ids)[:8]}")
            for manifest_path in manifest_paths:
                validate_preview_manifest(manifest_path, errors, stats)

    sound_events_path = PROJECT / "data" / "ra2" / "sound_events.json"
    sound_events = load_json(sound_events_path)
    audio_paths: set[Path] = set()
    if isinstance(sound_events, list):
        stats["sound_events"] = len(sound_events)
        for event in sound_events:
            if not isinstance(event, dict):
                continue
            for sample in event.get("samples", []):
                if not isinstance(sample, dict):
                    continue
                resource_path = str(sample.get("resource_path", ""))
                if not resource_path.startswith("res://"):
                    errors.append(f"{event.get('id')}: invalid resource path {resource_path}")
                    continue
                audio_paths.add(PROJECT / resource_path.removeprefix("res://"))
    stats["referenced_audio_files"] = len(audio_paths)
    formats: Counter[int] = Counter()
    for audio_path in sorted(audio_paths):
        if not audio_path.is_file():
            errors.append(f"missing audio file {audio_path.relative_to(PROJECT)}")
            continue
        try:
            fmt, channels, rate = wav_format(audio_path)
        except Exception as exc:
            errors.append(f"invalid WAV {audio_path.relative_to(PROJECT)}: {exc}")
            continue
        formats[fmt] += 1
        if channels not in (1, 2) or rate <= 0:
            errors.append(f"invalid WAV metadata {audio_path.relative_to(PROJECT)}")
    for fmt, count in formats.items():
        stats[f"wav_format:{fmt}"] = count

    browser_text = (PROJECT / "scripts" / "ui" / "ra2_database_browser.gd").read_text(encoding="utf-8")
    for token in [
        "SystemFont.new()",
        "ScrollContainer.new()",
        "_populate_animation_options",
        "_play_current_audio_sample",
        "RA2AudioService.play_event",
        "Image.load_from_file",
    ]:
        if token not in browser_text:
            errors.append(f"resource browser missing required implementation token: {token}")

    if errors:
        print("v0.13 browser validation failed:")
        for error in errors[:100]:
            print(" -", error)
        if len(errors) > 100:
            print(f" - ... {len(errors)-100} more")
        return 1

    print("v0.13 browser validation passed")
    for key in sorted(stats):
        print(f"{key}: {stats[key]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

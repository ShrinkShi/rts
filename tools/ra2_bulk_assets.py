#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import shutil
import tempfile
import traceback
import zipfile
from pathlib import Path
from typing import Any

PROJECT_ROOT = Path(__file__).resolve().parent.parent
import sys
if str(PROJECT_ROOT / "tools") not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT / "tools"))

from ra2_formats.cli import import_shp, import_vxl_group
from ra2_formats.palette import Palette
from ra2_formats.render import RenderSettings

ENGINE_DIRECTION_ORDER = [2, 3, 4, 5, 6, 7, 0, 1]


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def choose_candidate(candidates: list[dict[str, str]], category: str, extensions: set[str] | None = None) -> dict[str, str] | None:
    rows = [row for row in candidates if extensions is None or row.get("extension") in extensions]
    if not rows:
        return None

    def score(row: dict[str, str]) -> tuple[int, int, str]:
        path = row.get("path", "").lower()
        archive = row.get("archive", "")
        value = 0
        if archive == "yr":
            value += 100
        if category == "infantry":
            if path.startswith("conqmd/"):
                value += 80
            elif path.startswith("conquer/"):
                value += 70
        elif category in {"vehicle", "aircraft"}:
            if path.startswith("localmd/"):
                value += 80
            elif path.startswith("local/"):
                value += 70
        elif category == "building":
            for prefix, bonus in [
                ("genermd/", 90), ("snowmd/", 85), ("desert/", 80), ("urbann/", 78),
                ("generic/", 75), ("snow/", 70), ("temperat/", 68), ("urban/", 66),
            ]:
                if path.startswith(prefix):
                    value += bonus
                    break
        return value, -len(path), path

    return sorted(rows, key=score, reverse=True)[0]


def extract_entry(archives: dict[str, zipfile.ZipFile], entry: dict[str, str] | None, destination: Path) -> Path | None:
    if entry is None:
        return None
    archive = archives.get(entry.get("archive", ""))
    if archive is None:
        return None
    path = entry.get("path", "")
    if path not in archive.namelist():
        return None
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(archive.read(path))
    return destination


def palette_entry(archives: dict[str, zipfile.ZipFile], asset_path: str) -> tuple[str, str]:
    lower = asset_path.lower()
    if any(part in lower for part in ("desert/", "isodes/", "des/")):
        return "yr", "cachemd/unitdes.pal"
    if any(part in lower for part in ("lunar/", "isolun/", "lun/")):
        return "yr", "cachemd/unitlun.pal"
    if any(part in lower for part in ("urbann/", "isoubn/", "ubn/")):
        return "yr", "cachemd/unitubn.pal"
    if any(part in lower for part in ("snow/", "snowmd/", "isosnow/", "isosnomd/", "sno/")):
        return "ra2", "cache/unitsno.pal"
    if any(part in lower for part in ("urban/", "isourb/", "urb/")):
        return "ra2", "cache/uniturb.pal"
    return "ra2", "cache/unittem.pal"


def extract_palette(archives: dict[str, zipfile.ZipFile], source_path: str, temp: Path) -> Palette:
    archive_id, palette_path = palette_entry(archives, source_path)
    archive = archives[archive_id]
    if palette_path not in archive.namelist():
        # The temperate palette is the safest fallback for unit/building SHP files.
        archive_id, palette_path = "ra2", "cache/unittem.pal"
        archive = archives[archive_id]
    path = temp / Path(palette_path).name
    path.write_bytes(archive.read(palette_path))
    return Palette.from_file(path)


def sequence_animation_config(entity: dict[str, Any]) -> dict[str, Any] | None:
    sequence = entity.get("sequence", {})
    if not isinstance(sequence, dict) or not sequence:
        return None

    state_candidates = {
        "stand": ["Ready", "Guard", "Prone", "Deployed"],
        "idle": ["Idle1", "Idle2", "Ready", "Guard"],
        "move": ["Walk", "Crawl", "Fly", "Ready"],
        "attack": ["FireUp", "FireProne", "DeployedFire", "Ready"],
        "death": ["Die1", "Die2", "Die3", "Ready"],
    }
    states: dict[str, Any] = {}
    for runtime_state, candidates in state_candidates.items():
        chosen = next((sequence.get(name) for name in candidates if name in sequence), None)
        if not isinstance(chosen, dict):
            continue
        directional = int(chosen.get("direction_stride", 0)) > 0
        states[runtime_state] = {
            "start": int(chosen.get("start", 0)),
            "facings": 8 if directional else 1,
            "frames_per_facing": max(1, int(chosen.get("frames_per_facing", 1))),
            "fps": 10.0 if runtime_state == "move" else (12.0 if runtime_state == "attack" else 8.0),
            "loop": runtime_state not in {"attack", "death"},
            "direction_order": ENGINE_DIRECTION_ORDER if directional else [0],
        }
    return {"all_fps": 8.0, "states": states} if states else None


def render_settings(entity: dict[str, Any]) -> RenderSettings:
    category = entity.get("category", "")
    size = float(entity.get("rules", {}).get("Size", 3) or 3)
    if category == "aircraft":
        return RenderSettings(208, 160, 2, 0.90, 0.45, 0.90, 0.50, 0.68, 0.0)
    if size >= 6:
        return RenderSettings(224, 176, 2, 0.90, 0.45, 0.90, 0.50, 0.68, 0.0)
    return RenderSettings(176, 136, 2, 0.90, 0.45, 0.90, 0.50, 0.68, 0.0)


def import_entity(
    entity_id: str,
    entity: dict[str, Any],
    archives: dict[str, zipfile.ZipFile],
    output_root: Path,
    temp_root: Path,
) -> dict[str, Any]:
    category = str(entity.get("category", ""))
    assets = entity.get("assets", {})
    output = output_root / entity_id.lower()
    output.mkdir(parents=True, exist_ok=True)
    body = choose_candidate(assets.get("body", []), category)
    if body is None:
        raise FileNotFoundError(f"No body asset for {entity_id}")

    result: dict[str, Any] = {
        "entity_id": entity_id,
        "category": category,
        "source": body,
        "output": "res://" + output.relative_to(PROJECT_ROOT).as_posix(),
    }
    work = temp_root / entity_id.lower()
    work.mkdir(parents=True, exist_ok=True)

    if body.get("extension") in {".shp", ".sha"}:
        source = extract_entry(archives, body, work / (Path(body["path"]).stem + ".shp"))
        if source is None:
            raise FileNotFoundError(body.get("path", ""))
        palette = extract_palette(archives, body["path"], work)
        imported = import_shp(
            source,
            output,
            PROJECT_ROOT,
            palette,
            sequence_animation_config(entity) if category == "infantry" else None,
        )
        result.update(imported)
        result["visual_kind"] = "shp"

        # Optional voxel turret used by Grand Cannon and similar structures.
        turret_anim = choose_candidate(assets.get("turret_anim", []), category, {".vxl"})
        if turret_anim is not None:
            turret_vxl = extract_entry(archives, turret_anim, work / Path(turret_anim["path"]).name)
            turret_hva_entry = choose_candidate(assets.get("turret_anim_hva", []), category, {".hva"})
            turret_hva = extract_entry(archives, turret_hva_entry, work / Path(turret_hva_entry["path"]).name) if turret_hva_entry else None
            turret_render = import_vxl_group(
                entity_id + "_turret",
                turret_vxl,
                output / "turret",
                PROJECT_ROOT,
                turret_hva,
                facing_count=8,
                settings=render_settings(entity),
            )
            result["building_turret"] = turret_render
        return result

    if body.get("extension") == ".vxl":
        body_vxl = extract_entry(archives, body, work / Path(body["path"]).name)
        body_hva_entry = choose_candidate(assets.get("hva", []), category, {".hva"})
        body_hva = extract_entry(archives, body_hva_entry, work / Path(body_hva_entry["path"]).name) if body_hva_entry else None
        turret_entry = choose_candidate(assets.get("turret", []), category, {".vxl"})
        turret_vxl = extract_entry(archives, turret_entry, work / Path(turret_entry["path"]).name) if turret_entry else None
        turret_hva_entry = choose_candidate(assets.get("turret_hva", []), category, {".hva"})
        turret_hva = extract_entry(archives, turret_hva_entry, work / Path(turret_hva_entry["path"]).name) if turret_hva_entry else None
        barrel_entry = choose_candidate(assets.get("barrel", []), category, {".vxl"})
        barrel_vxl = extract_entry(archives, barrel_entry, work / Path(barrel_entry["path"]).name) if barrel_entry else None
        barrel_hva_entry = choose_candidate(assets.get("barrel_hva", []), category, {".hva"})
        barrel_hva = extract_entry(archives, barrel_hva_entry, work / Path(barrel_hva_entry["path"]).name) if barrel_hva_entry else None
        imported = import_vxl_group(
            entity_id,
            body_vxl,
            output,
            PROJECT_ROOT,
            body_hva,
            turret_vxl,
            turret_hva,
            barrel_vxl,
            barrel_hva,
            8,
            render_settings(entity),
        )
        result.update(imported)
        result["visual_kind"] = "vxl"
        return result

    raise ValueError(f"Unsupported body extension for {entity_id}: {body.get('extension')}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Bulk-convert all playable RA2/YR entity visuals into Godot resources")
    parser.add_argument("ra2_zip", type=Path)
    parser.add_argument("yr_zip", type=Path)
    parser.add_argument("catalog", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--ids", nargs="*")
    parser.add_argument("--categories", nargs="*", choices=["infantry", "vehicle", "aircraft", "building"])
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--clean", action="store_true")
    args = parser.parse_args()

    catalog = load_json(args.catalog.resolve())
    entities = catalog.get("entities", {})
    selected = list(catalog.get("playable_or_starting_entities", []))
    if args.ids:
        wanted = {value.upper() for value in args.ids}
        selected = [entity_id for entity_id in selected if entity_id.upper() in wanted]
    if args.categories:
        wanted_categories = set(args.categories)
        selected = [entity_id for entity_id in selected if entities.get(entity_id, {}).get("category") in wanted_categories]
    if args.limit > 0:
        selected = selected[:args.limit]

    output = args.output.resolve()
    if args.clean and output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True, exist_ok=True)

    results: list[dict[str, Any]] = []
    errors: list[dict[str, str]] = []
    with zipfile.ZipFile(args.ra2_zip.resolve()) as ra2, zipfile.ZipFile(args.yr_zip.resolve()) as yr:
        archives = {"ra2": ra2, "yr": yr}
        with tempfile.TemporaryDirectory(prefix="ra2_bulk_") as temp_name:
            temp = Path(temp_name)
            total = len(selected)
            for index, entity_id in enumerate(selected, start=1):
                entity = entities.get(entity_id, {})
                print(f"[{index}/{total}] {entity_id} {entity.get('category', '')}", flush=True)
                try:
                    results.append(import_entity(entity_id, entity, archives, output, temp))
                except Exception as error:
                    errors.append({
                        "entity_id": entity_id,
                        "error": str(error),
                        "traceback": traceback.format_exc(limit=4),
                    })
                    print(f"  ERROR: {error}", flush=True)

    manifest = {
        "version": 1,
        "source_catalog": "res://data/ra2/catalog.json",
        "converted": len(results),
        "failed": len(errors),
        "assets": results,
        "errors": errors,
    }
    (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"ok": not errors, "converted": len(results), "failed": len(errors), "manifest": str(output / 'manifest.json')}, ensure_ascii=False))
    return 0 if not errors else 2


if __name__ == "__main__":
    raise SystemExit(main())

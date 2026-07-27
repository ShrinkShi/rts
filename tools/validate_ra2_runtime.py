#!/usr/bin/env python3
"""Static validation for the v0.14 RA2/YR runtime vertical slice."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROFILE_PATH = ROOT / "data/ra2/runtime_profiles.json"
PREVIEW_ROOT = ROOT / "assets/ra2_preview"
ENTITY_ROOT = ROOT / "data/ra2/entities"
LOCALIZATION_PATH = ROOT / "data/ra2/localization.json"

UNIT_STATE_CANDIDATES = {
    "stand": ["Stand", "Ready", "Guard", "HVA", "Walk"],
    "move": ["Walk", "HVA", "Stand", "Ready"],
    "attack": ["Fire", "FireUp", "DeployedFire", "HVA", "Stand", "Ready"],
    "death": ["Die1", "Die2"],
}
BUILDING_STATE_CANDIDATES = {
    "normal": ["Operational", "Ready", "BodyStates"],
    "construction": ["Buildup"],
    "damaged": ["DamagedOperational", "DamagedReady", "BodyStates", "Operational", "Ready"],
    "destroyed": ["BodyStates", "DamagedReady"],
    "production": ["ProductionAnim", "DeployingAnim", "Operational", "Ready", "BodyStates"],
    "special": ["SpecialAnim", "SpecialAnimTwo", "SpecialAnimThree", "Operational", "Ready", "BodyStates"],
    "repair": ["SpecialAnim", "SpecialAnimTwo", "SpecialAnimThree", "Operational", "Ready", "BodyStates"],
}


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def animation_dict(manifest: dict) -> dict:
    if "theaters" not in manifest:
        return manifest.get("animations", {})
    theater = manifest.get("default_theater", "temperate")
    theater_data = manifest.get("theaters", {}).get(theater, {})
    return theater_data.get("animations", {})


def resolve(candidates: list[str], animations: dict) -> str | None:
    return next((item for item in candidates if item in animations), None)


def main() -> int:
    errors: list[str] = []
    warnings: list[str] = []
    profiles = load_json(PROFILE_PATH)
    raw_localization = load_json(LOCALIZATION_PATH).get("lookup", {})
    localization = {str(key).lower(): value for key, value in raw_localization.items()}
    mapped_ids: set[str] = set()
    validated_ids: set[tuple[str, str]] = set()

    for kind in ("units", "buildings"):
        section = profiles.get(kind, {})
        if set(section) != {"union", "dominion", "republic"}:
            errors.append(f"{kind}: faction mapping is incomplete: {sorted(section)}")
        for faction_id, entries in section.items():
            for generic_id, profile in entries.items():
                entity_id = str(profile.get("ra2_id", "")).upper()
                if not entity_id:
                    errors.append(f"{kind}/{faction_id}/{generic_id}: empty ra2_id")
                    continue
                mapped_ids.add(entity_id)
                validation_key = (kind, entity_id)
                if validation_key in validated_ids:
                    continue
                validated_ids.add(validation_key)
                entity_path = ENTITY_ROOT / f"{entity_id.lower()}.json"
                manifest_path = PREVIEW_ROOT / entity_id.lower() / "manifest.json"
                if not entity_path.is_file():
                    errors.append(f"{entity_id}: entity JSON missing")
                    continue
                if not manifest_path.is_file():
                    errors.append(f"{entity_id}: preview manifest missing")
                    continue
                entity = load_json(entity_path)
                token = str(entity.get("name_token", ""))
                if token and token.lower() not in localization:
                    warnings.append(f"{entity_id}: localization token unresolved: {token}")
                manifest = load_json(manifest_path)
                animations = animation_dict(manifest)
                candidates = UNIT_STATE_CANDIDATES if kind == "units" else BUILDING_STATE_CANDIDATES
                for state, options in candidates.items():
                    resolved = resolve(options, animations)
                    if resolved is None:
                        if kind == "units" and state == "death" and entity.get("category") == "vehicle":
                            continue
                        warnings.append(f"{entity_id}: no runtime animation for {state}")
                for animation_name, animation in animations.items():
                    if animation.get("directional"):
                        directions = animation.get("directions", {})
                        if len(directions) != int(animation.get("facing_count", 8)):
                            errors.append(f"{entity_id}/{animation_name}: direction count mismatch")
                        frame_groups = directions.values()
                    else:
                        frame_groups = [animation]
                    for group in frame_groups:
                        frames = group.get("frames", [])
                        masks = group.get("remap_masks", [])
                        if masks and len(masks) != len(frames):
                            errors.append(f"{entity_id}/{animation_name}: frame/mask count mismatch")
                        base = manifest_path.parent
                        if "theaters" in manifest:
                            base = base / manifest.get("default_theater", "temperate")
                        for relative in [*frames, *masks]:
                            if not (base / relative).is_file():
                                errors.append(f"{entity_id}/{animation_name}: missing {relative}")

    ytnk_manifest = load_json(PREVIEW_ROOT / "ytnk/manifest.json")
    if set(ytnk_manifest.get("animations", {})) < {"Stand", "Fire"}:
        errors.append("YTNK must expose both Stand and Fire animations")

    for marine_id in ("DLPH", "SQD"):
        manifest = load_json(PREVIEW_ROOT / marine_id.lower() / "manifest.json")
        walk = manifest.get("animations", {}).get("Walk", {})
        directions = walk.get("directions", {})
        starts = [directions.get(str(index), {}).get("source_indices", [None])[0] for index in range(8)]
        positive = sorted({int(value) for value in starts if value not in (None, 0)})
        step = min(positive) if positive else 0
        source_dirs = [int(value) // step if step > 0 else None for value in starts]
        if source_dirs != [2, 3, 4, 5, 6, 7, 0, 1]:
            errors.append(f"{marine_id}: unexpected marine direction map: {source_dirs}")

    required_autoload = 'RA2RuntimeDatabase="*res://scripts/ra2/ra2_runtime_database.gd"'
    project_text = (ROOT / "project.godot").read_text(encoding="utf-8")
    if required_autoload not in project_text:
        errors.append("project.godot: RA2RuntimeDatabase autoload missing")

    print(f"Mapped RA2/YR entities: {len(mapped_ids)}")
    print(f"Warnings: {len(warnings)}")
    for warning in warnings:
        print(f"WARN: {warning}")
    print(f"Errors: {len(errors)}")
    for error in errors:
        print(f"ERROR: {error}")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())

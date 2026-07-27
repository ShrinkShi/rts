#!/usr/bin/env python3
from __future__ import annotations

import argparse
import io
import json
import os
import re
import zipfile
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable

LIST_SECTIONS = {
    "InfantryTypes": "infantry",
    "VehicleTypes": "vehicle",
    "AircraftTypes": "aircraft",
    "BuildingTypes": "building",
}

BOOL_KEYS = {
    "Cloakable", "Naval", "Organic", "ImmuneToPsionics", "ImmuneToRadiation",
    "ImmuneToPoison", "Crushable", "Crusher", "OmniCrusher", "Harvester",
    "ResourceGatherer", "Refinery", "ConstructionYard", "WeaponsFactory",
    "Wall", "BaseNormal", "Capturable", "Repairable", "Trainable", "Turret",
    "BalloonHover", "JumpJet", "AirportBound", "ConsideredAircraft", "DeployToLand",
    "IsSimpleDeployer", "Powered", "Unsellable", "InvisibleInGame", "Insignificant",
    "Selectable", "CanBeOccupied", "CanOccupyFire", "Garrisonable", "WaterBound",
    "Amphibious", "HoverAttack", "LandTargeting", "Underwater", "Teleporter",
    "ChronoInSound", "ChronoOutSound", "DistributedFire", "OpportunityFire",
    "CanPassiveAquire", "CanRetaliate", "NoShadow", "Voxel", "Remapable",
}

NUMERIC_KEYS = {
    "Strength", "Cost", "TechLevel", "Sight", "Speed", "ROF", "Range", "Damage",
    "BuildTimeMultiplier", "Power", "Storage", "Passengers", "Size", "SizeLimit",
    "BuildLimit", "Ammo", "Soylent", "ThreatPosed", "SpecialThreatValue",
    "GuardRange", "MinimumRange", "Adjacent", "FlightLevel", "JumpjetHeight",
    "JumpjetSpeed", "JumpjetTurnRate", "JumpjetClimb", "JumpjetCrash",
    "JumpJetAccel", "JumpJetWobbles", "JumpJetDeviation", "VoiceFeedback",
}

PERCENT_KEYS = {
    "FirepowerMult", "GroundspeedMult", "AirspeedMult", "ArmorMult", "ROFMult",
    "CostMult", "BuildTimeMult", "IncomeMult", "VeteranCombat", "VeteranSpeed",
    "VeteranArmor", "VeteranROF", "RefundPercent", "RepairPercent",
}

COUNTRY_COLORS = {
    "Americans": "4F86E8", "Alliance": "4FA3FF", "French": "4B73C4",
    "Germans": "6C83B5", "British": "5B9BE0", "Russians": "D94B4B",
    "Africans": "BE593F", "Confederation": "C45A44", "Arabs": "C7773F",
    "YuriCountry": "A96BD7", "Neutral": "8F9AA3", "Special": "B4B4B4",
    "GDI": "5A8ED8", "Nod": "C95757",
}

COUNTRY_NAMES_ZH = {
    "Americans": "美国", "Alliance": "韩国", "French": "法国", "Germans": "德国",
    "British": "英国", "Russians": "苏俄", "Africans": "利比亚",
    "Confederation": "古巴", "Arabs": "伊拉克", "YuriCountry": "尤里",
    "Neutral": "中立", "Special": "特殊", "GDI": "盟军阵营", "Nod": "苏军阵营",
}

SIDE_NAMES_ZH = {
    "GDI": "盟军", "Nod": "苏军", "ThirdSide": "尤里", "Civilian": "平民", "Mutant": "特殊",
}


def _decode(raw: bytes) -> str:
    for encoding in ("utf-8-sig", "cp936", "latin1"):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            pass
    return raw.decode("latin1", errors="ignore")


def _strip_comment(line: str) -> str:
    # Westwood INI uses ';' as the comment delimiter. Quoted semicolons are not
    # used by the official RA2/YR configuration files.
    return line.split(";", 1)[0].strip()


def parse_westwood_ini(text: str) -> dict[str, dict[str, str]]:
    sections: dict[str, dict[str, str]] = {}
    current: str | None = None
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith(";"):
            continue
        if line.startswith("[") and "]" in line:
            current = line[1:line.index("]")].strip()
            sections.setdefault(current, {})
            continue
        if current is None:
            continue
        clean = _strip_comment(raw)
        if not clean or "=" not in clean:
            continue
        key, value = clean.split("=", 1)
        sections[current][key.strip()] = value.strip()
    return sections


def read_zip_text(archive: zipfile.ZipFile, candidates: Iterable[str]) -> str:
    names = {name.lower(): name for name in archive.namelist()}
    for candidate in candidates:
        actual = names.get(candidate.lower())
        if actual:
            return _decode(archive.read(actual))
    raise FileNotFoundError(f"None of the files exist in archive: {list(candidates)}")


def ordered_list(section: dict[str, str]) -> list[str]:
    def key_order(item: tuple[str, str]) -> tuple[int, str]:
        key = item[0]
        try:
            return int(key), key
        except ValueError:
            return 10**9, key.lower()
    return [value for _, value in sorted(section.items(), key=key_order) if value]


def split_csv(value: str | None) -> list[str]:
    if not value:
        return []
    return [part.strip() for part in value.split(",") if part.strip() and part.strip().lower() != "none"]


def parse_bool(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"yes", "true", "1", "on"}


def parse_number(value: str | None, default: float | int | None = None) -> float | int | None:
    if value is None or value == "":
        return default
    raw = value.strip()
    if raw.endswith("%"):
        try:
            return float(raw[:-1]) / 100.0
        except ValueError:
            return default
    try:
        number = float(raw)
    except ValueError:
        return default
    return int(number) if number.is_integer() else number


def normalize_value(key: str, value: str) -> Any:
    if key in BOOL_KEYS:
        return parse_bool(value)
    if key in NUMERIC_KEYS or key in PERCENT_KEYS:
        return parse_number(value, value)
    return value


def normalize_section(section: dict[str, str]) -> dict[str, Any]:
    return {key: normalize_value(key, value) for key, value in section.items()}


def build_asset_registry(*archives: tuple[str, zipfile.ZipFile]) -> dict[str, list[dict[str, str]]]:
    registry: dict[str, list[dict[str, str]]] = defaultdict(list)
    supported = {".shp", ".sha", ".vxl", ".hva", ".pal", ".aud", ".wav", ".pcx", ".fnt", ".vpl"}
    for archive_id, archive in archives:
        for path in archive.namelist():
            if path.endswith("/"):
                continue
            suffix = Path(path).suffix.lower()
            if suffix not in supported:
                continue
            name = Path(path).name.lower()
            stem = Path(path).stem.lower()
            entry = {"archive": archive_id, "path": path, "extension": suffix}
            registry[name].append(entry)
            registry[stem].append(entry)
    return dict(registry)


def asset_candidates(registry: dict[str, list[dict[str, str]]], stem: str, extensions: Iterable[str] | None = None) -> list[dict[str, str]]:
    candidates = registry.get(stem.lower(), [])
    if extensions is None:
        return candidates
    allowed = {extension.lower() for extension in extensions}
    return [entry for entry in candidates if entry["extension"] in allowed]


def parse_sequence(sequence_section: dict[str, str]) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for state, raw in sequence_section.items():
        parts = [part.strip() for part in raw.split(",")]
        if len(parts) < 3:
            continue
        try:
            start = int(parts[0])
            count = int(parts[1])
            facings = int(parts[2])
        except ValueError:
            continue
        result[state] = {
            "start": start,
            "frames_per_facing": max(1, count),
            # In Westwood infantry Sequence entries the third integer is the
            # frame stride between facings, not the number of facings. A zero
            # stride denotes a non-directional animation such as Idle or Die.
            "direction_stride": max(0, facings),
            "facings": 8 if facings > 0 else 1,
            "extra": parts[3:],
        }
    return result


def weapon_payload(rules: dict[str, dict[str, str]], weapon_id: str | None) -> dict[str, Any] | None:
    if not weapon_id or weapon_id.lower() == "none":
        return None
    raw = rules.get(weapon_id, {})
    if not raw:
        return {"id": weapon_id, "missing_definition": True}
    payload = normalize_section(raw)
    payload["id"] = weapon_id
    warhead_id = raw.get("Warhead")
    if warhead_id:
        payload["warhead_id"] = warhead_id
    projectile_id = raw.get("Projectile")
    if projectile_id:
        payload["projectile_id"] = projectile_id
    return payload


def entity_payload(
    entity_id: str,
    category: str,
    rules: dict[str, dict[str, str]],
    art: dict[str, dict[str, str]],
    registry: dict[str, list[dict[str, str]]],
) -> dict[str, Any]:
    raw = rules.get(entity_id, {})
    image_id = raw.get("Image", entity_id)
    art_raw = art.get(image_id, art.get(entity_id, {}))
    art_image = art_raw.get("Image", image_id)
    owners = split_csv(raw.get("Owner"))
    tech_level = parse_number(raw.get("TechLevel"), -1)
    cost = parse_number(raw.get("Cost"), 0)
    strength = parse_number(raw.get("Strength"), 100)
    primary_id = raw.get("Primary")
    secondary_id = raw.get("Secondary")
    elite_primary_id = raw.get("ElitePrimary")
    elite_secondary_id = raw.get("EliteSecondary")
    sequence_id = art_raw.get("Sequence")
    sequence = parse_sequence(art.get(sequence_id, {})) if sequence_id else {}
    voxel = parse_bool(art_raw.get("Voxel"), category in {"vehicle", "aircraft"})

    stem = art_image.lower()
    body_candidates = asset_candidates(registry, stem, {".vxl"} if voxel else {".shp", ".sha"})
    if not body_candidates and not voxel and parse_bool(art_raw.get("NewTheater"), False) and len(stem) >= 3:
        # NewTheater artwork replaces the second character according to theater.
        # Keep all available variants in the registry; the importer can choose the
        # active map theater later. This also resolves objects such as GTGCAN -> GAGCAN.
        seen_paths: set[tuple[str, str]] = set()
        for theater_code in "agtundl":
            alias = stem[0] + theater_code + stem[2:]
            for entry in asset_candidates(registry, alias, {".shp", ".sha"}):
                key = (entry["archive"], entry["path"])
                if key not in seen_paths:
                    seen_paths.add(key)
                    body_candidates.append(entry)

    assets: dict[str, Any] = {
        "image_id": art_image,
        "voxel": voxel,
        "body": body_candidates,
        "hva": asset_candidates(registry, stem, {".hva"}),
        "turret": asset_candidates(registry, stem + "tur", {".vxl"}),
        "turret_hva": asset_candidates(registry, stem + "tur", {".hva"}),
        "barrel": asset_candidates(registry, stem + "barl", {".vxl"}),
        "barrel_hva": asset_candidates(registry, stem + "barl", {".hva"}),
    }
    cameo = art_raw.get("Cameo")
    if cameo:
        assets["cameo_id"] = cameo
        assets["cameo"] = asset_candidates(registry, cameo.lower(), {".shp", ".sha", ".pcx"})

    if category == "building":
        turret_anim = raw.get("TurretAnim", art_raw.get("TurretAnim", ""))
        if turret_anim:
            assets["turret_anim_id"] = turret_anim
            assets["turret_anim"] = asset_candidates(registry, turret_anim.lower(), {".vxl", ".shp", ".sha"})
            assets["turret_anim_hva"] = asset_candidates(registry, turret_anim.lower(), {".hva"})
        buildup = art_raw.get("Buildup", "")
        if buildup:
            assets["buildup_id"] = buildup
            assets["buildup"] = asset_candidates(registry, buildup.lower(), {".shp", ".sha"})
        overlay_keys = [
            "ActiveAnim", "ActiveAnimDamaged", "ProductionAnim", "ProductionAnimDamaged",
            "IdleAnim", "IdleAnimDamaged", "SuperAnim", "SuperAnimDamaged",
        ]
        overlays: dict[str, Any] = {}
        for overlay_key in overlay_keys:
            overlay_id = art_raw.get(overlay_key, "")
            if overlay_id:
                overlays[overlay_key] = {
                    "id": overlay_id,
                    "assets": asset_candidates(registry, overlay_id.lower(), {".shp", ".sha", ".vxl"}),
                }
        if overlays:
            assets["overlays"] = overlays

    normalized = normalize_section(raw)
    payload: dict[str, Any] = {
        "id": entity_id,
        "category": category,
        "name": raw.get("Name", entity_id),
        "ui_name_key": raw.get("UIName", ""),
        "owners": owners,
        "tech_level": tech_level,
        "cost": cost,
        "strength": strength,
        "armor": raw.get("Armor", "none"),
        "sight": parse_number(raw.get("Sight"), 5),
        "speed": parse_number(raw.get("Speed"), 0),
        "prerequisite": split_csv(raw.get("Prerequisite")),
        "required_houses": split_csv(raw.get("RequiredHouses")),
        "forbidden_houses": split_csv(raw.get("ForbiddenHouses")),
        "primary_weapon": weapon_payload(rules, primary_id),
        "secondary_weapon": weapon_payload(rules, secondary_id),
        "elite_primary_weapon": weapon_payload(rules, elite_primary_id),
        "elite_secondary_weapon": weapon_payload(rules, elite_secondary_id),
        "art": normalize_section(art_raw),
        "sequence_id": sequence_id or "",
        "sequence": sequence,
        "assets": assets,
        "rules": normalized,
    }
    payload["buildable"] = bool(
        owners
        and isinstance(tech_level, (int, float)) and tech_level >= 0
        and isinstance(cost, (int, float)) and cost >= 0
        and not parse_bool(raw.get("Insignificant"), False)
    )
    payload["playable_or_starting"] = payload["buildable"] or entity_id in {"GACNST", "NACNST", "YACNST", "AMCV", "SMCV", "PCV"}
    payload["special_flags"] = {
        key: parse_bool(raw.get(key))
        for key in [
            "Cloakable", "Naval", "Organic", "Crusher", "OmniCrusher", "Harvester",
            "ResourceGatherer", "Refinery", "ConstructionYard", "WeaponsFactory",
            "Wall", "Capturable", "Repairable", "Trainable", "Turret", "BalloonHover",
            "JumpJet", "AirportBound", "ConsideredAircraft", "IsSimpleDeployer", "Powered",
            "CanBeOccupied", "WaterBound", "Teleporter",
        ]
        if key in raw
    }
    return payload


def build_database(ra2_zip: Path, yr_zip: Path) -> dict[str, Any]:
    with zipfile.ZipFile(ra2_zip) as ra2, zipfile.ZipFile(yr_zip) as yr:
        # Yuri's Revenge files are complete supersets in these extracted archives.
        rules = parse_westwood_ini(read_zip_text(yr, ["localmd/rulesmd.ini"]))
        art = parse_westwood_ini(read_zip_text(yr, ["localmd/artmd.ini"]))
        sound = parse_westwood_ini(read_zip_text(yr, ["localmd/soundmd.ini"]))
        eva = parse_westwood_ini(read_zip_text(yr, ["localmd/evamd.ini"]))
        ai = parse_westwood_ini(read_zip_text(yr, ["localmd/aimd.ini"]))
        registry = build_asset_registry(("ra2", ra2), ("yr", yr))

    sides_section = rules.get("Sides", {})
    side_members: dict[str, list[str]] = {side: split_csv(members) for side, members in sides_section.items()}
    country_side: dict[str, str] = {}
    for side, members in side_members.items():
        for country in members:
            country_side[country] = side

    countries: dict[str, Any] = {}
    for country_id in ordered_list(rules.get("Countries", {})):
        raw = rules.get(country_id, {})
        countries[country_id] = {
            "id": country_id,
            "name": raw.get("Name", COUNTRY_NAMES_ZH.get(country_id, country_id)),
            "name_zh": COUNTRY_NAMES_ZH.get(country_id, raw.get("Name", country_id)),
            "ui_name_key": raw.get("UIName", ""),
            "side": raw.get("Side", country_side.get(country_id, "")),
            "side_name_zh": SIDE_NAMES_ZH.get(raw.get("Side", country_side.get(country_id, "")), ""),
            "color": COUNTRY_COLORS.get(country_id, "7F8C8D"),
            "multiplay": parse_bool(raw.get("Multiplay"), country_id not in {"Neutral", "Special", "GDI", "Nod"}),
            "smart_ai": parse_bool(raw.get("SmartAI"), False),
            "veteran_units": split_csv(raw.get("VeteranUnits")),
            "cost_units_mult": parse_number(raw.get("CostUnitsMult"), 1.0),
            "cost_infantry_mult": parse_number(raw.get("CostInfantryMult"), 1.0),
            "cost_buildings_mult": parse_number(raw.get("CostBuildingsMult"), 1.0),
            "speed_units_mult": parse_number(raw.get("SpeedUnitsMult"), 1.0),
            "armor_units_mult": parse_number(raw.get("ArmorUnitsMult"), 1.0),
            "firepower_mult": parse_number(raw.get("FirepowerMult"), 1.0),
            "rules": normalize_section(raw),
        }

    entities: dict[str, Any] = {}
    category_lists: dict[str, list[str]] = {}
    for section, category in LIST_SECTIONS.items():
        ids = ordered_list(rules.get(section, {}))
        category_lists[category] = ids
        for entity_id in ids:
            entities[entity_id] = entity_payload(entity_id, category, rules, art, registry)

    superweapon_ids = ordered_list(rules.get("SuperWeaponTypes", {}))
    superweapons = {
        weapon_id: {
            "id": weapon_id,
            "rules": normalize_section(rules.get(weapon_id, {})),
        }
        for weapon_id in superweapon_ids
    }

    referenced_weapons: set[str] = set()
    referenced_warheads: set[str] = set()
    for entity in entities.values():
        for key in ("primary_weapon", "secondary_weapon", "elite_primary_weapon", "elite_secondary_weapon"):
            weapon = entity.get(key)
            if not isinstance(weapon, dict):
                continue
            weapon_id = str(weapon.get("id", ""))
            if weapon_id:
                referenced_weapons.add(weapon_id)
            warhead_id = str(weapon.get("warhead_id", ""))
            if warhead_id:
                referenced_warheads.add(warhead_id)

    weapons = {
        weapon_id: {"id": weapon_id, **normalize_section(rules.get(weapon_id, {}))}
        for weapon_id in sorted(referenced_weapons)
    }
    warheads = {
        warhead_id: {"id": warhead_id, **normalize_section(rules.get(warhead_id, {}))}
        for warhead_id in sorted(referenced_warheads)
    }

    playable_countries = [
        country_id for country_id, country in countries.items()
        if country.get("multiplay") and country.get("side") in {"GDI", "Nod", "ThirdSide"}
    ]
    playable_entities = [entity_id for entity_id, entity in entities.items() if entity.get("playable_or_starting")]
    buildable_entities = [entity_id for entity_id, entity in entities.items() if entity.get("buildable")]
    missing_visuals = [
        entity_id for entity_id in playable_entities
        if not entities[entity_id].get("assets", {}).get("body")
    ]

    return {
        "version": 1,
        "source": {
            "ra2_archive": ra2_zip.name,
            "yr_archive": yr_zip.name,
            "warning": "The source archives and derived assets are for local compatibility testing only; do not publish them in a public repository.",
        },
        "summary": {
            "countries": len(countries),
            "playable_countries": len(playable_countries),
            "sides": len(side_members),
            "infantry": len(category_lists.get("infantry", [])),
            "vehicles": len(category_lists.get("vehicle", [])),
            "aircraft": len(category_lists.get("aircraft", [])),
            "buildings": len(category_lists.get("building", [])),
            "superweapons": len(superweapons),
            "buildable_entities": len(buildable_entities),
            "playable_or_starting_entities": len(playable_entities),
            "referenced_weapons": len(weapons),
            "referenced_warheads": len(warheads),
            "playable_entities_missing_visual_asset": len(missing_visuals),
        },
        "sides": {
            side: {
                "id": side,
                "name_zh": SIDE_NAMES_ZH.get(side, side),
                "countries": members,
            }
            for side, members in side_members.items()
        },
        "countries": countries,
        "playable_countries": playable_countries,
        "category_lists": category_lists,
        "entities": entities,
        "buildable_entities": buildable_entities,
        "playable_or_starting_entities": playable_entities,
        "superweapons": superweapons,
        "weapons": weapons,
        "warheads": warheads,
        "sound_sections": len(sound),
        "eva_sections": len(eva),
        "ai_sections": len(ai),
        "asset_registry": registry,
        "missing_visuals": missing_visuals,
    }


def write_database(database: dict[str, Any], output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    files = {
        "catalog.json": database,
        "summary.json": database["summary"],
        "sides.json": database["sides"],
        "countries.json": database["countries"],
        "entities.json": database["entities"],
        "superweapons.json": database["superweapons"],
        "weapons.json": database["weapons"],
        "warheads.json": database["warheads"],
        "asset_registry.json": database["asset_registry"],
    }
    for name, payload in files.items():
        (output / name).write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build a complete RA2/YR data and asset registry for the Godot compatibility layer")
    parser.add_argument("ra2_zip", type=Path)
    parser.add_argument("yr_zip", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    database = build_database(args.ra2_zip.resolve(), args.yr_zip.resolve())
    write_database(database, args.output.resolve())
    print(json.dumps({"ok": True, "summary": database["summary"], "output": str(args.output.resolve())}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

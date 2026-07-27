#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

COUNTRY_NAME_ZH = {
    "Americans": "美国", "Alliance": "韩国", "French": "法国", "Germans": "德国",
    "British": "英国", "Russians": "苏俄", "Africans": "利比亚",
    "Confederation": "古巴", "Arabs": "伊拉克", "YuriCountry": "尤里",
}

SIDE_NAME_ZH = {"GDI": "盟军", "Nod": "苏军", "ThirdSide": "尤里"}
SIDE_START = {
    "GDI": {
        "command": "GACNST", "power": "GAPOWR", "refinery": "GAREFN",
        "barracks": "GAPILE", "war_factory": "GAWEAP", "basic_infantry": "E1",
        "basic_tank": "MTNK", "harvester": "CMIN", "mcv": "AMCV",
    },
    "Nod": {
        "command": "NACNST", "power": "NAPOWR", "refinery": "NAREFN",
        "barracks": "NAHAND", "war_factory": "NAWEAP", "basic_infantry": "E2",
        "basic_tank": "HTNK", "harvester": "HARV", "mcv": "SMCV",
    },
    "ThirdSide": {
        "command": "YACNST", "power": "YAPOWR", "refinery": "YAREFN",
        "barracks": "YABRCK", "war_factory": "YAWEAP", "basic_infantry": "INIT",
        "basic_tank": "LTNK", "harvester": "SMIN", "mcv": "PCV",
    },
}

ARMOR_SCORE = {
    "none": 0, "flak": 1, "plate": 2, "light": 2, "medium": 4,
    "heavy": 6, "wood": 2, "steel": 7, "concrete": 9, "special_1": 8,
    "special_2": 8,
}


def load(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def rid(original_id: str) -> str:
    return "ra2_" + original_id.lower()


def first_number(value: Any, default: float = 0.0) -> float:
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(str(value).split(",", 1)[0])
    except (TypeError, ValueError):
        return default


def weapon_stats(entity: dict[str, Any]) -> dict[str, Any]:
    weapon = entity.get("primary_weapon")
    if not isinstance(weapon, dict):
        weapon = {}
    damage = first_number(weapon.get("Damage"), 0.0)
    rof_frames = max(1.0, first_number(weapon.get("ROF"), 15.0))
    range_cells = max(0.0, first_number(weapon.get("Range"), 0.0))
    warhead = str(weapon.get("warhead_id", weapon.get("Warhead", "none")))
    return {
        "weapon_name": str(weapon.get("id", "无")),
        "damage": damage,
        "reload": rof_frames / 15.0,
        "range": range_cells * 44.0,
        "damage_type": warhead,
        "warhead": warhead,
    }


def visual_paths(asset_root: Path, original_id: str, project_root: Path) -> dict[str, str]:
    folder = asset_root / original_id.lower()
    result: dict[str, str] = {}
    candidates = {
        "ra2_body_frames": folder / "body_frames.tres",
        "ra2_turret_frames": folder / "turret_frames.tres",
        "ra2_combined_frames": folder / "combined_frames.tres",
        "ra2_sprite_frames": folder / "sprite_frames.tres",
        "ra2_shp_resource": folder / "shp_resource.tres",
        "ra2_building_turret_frames": folder / "turret" / "body_frames.tres",
    }
    for key, path in candidates.items():
        if path.exists():
            result[key] = "res://" + path.resolve().relative_to(project_root.resolve()).as_posix()
    return result


def inferred_building_side(original_id: str) -> str:
    upper = original_id.upper()
    if upper.startswith(("GA", "GG", "GT")):
        return "GDI"
    if upper.startswith(("NA", "NG", "NT")):
        return "Nod"
    if upper.startswith(("YA", "YG", "YT")):
        return "ThirdSide"
    return ""


def entity_allowed_for_country(entity: dict[str, Any], country_id: str, country_side: str = "") -> bool:
    owners = entity.get("owners", [])
    required = entity.get("required_houses", [])
    forbidden = entity.get("forbidden_houses", [])
    rules = entity.get("rules", {})
    secret_houses = [item.strip() for item in str(rules.get("SecretHouses", "")).split(",") if item.strip()]
    if owners and country_id not in owners:
        return False
    if required and country_id not in required:
        return False
    if secret_houses and country_id not in secret_houses:
        return False
    if country_id in forbidden:
        return False
    if entity.get("category") == "building":
        building_side = inferred_building_side(str(entity.get("id", "")))
        if building_side and country_side and building_side != country_side:
            return False
    return bool(entity.get("buildable", False))


def special_requirements(rules: dict[str, Any]) -> list[str]:
    result: list[str] = []
    if bool(rules.get("RequiresStolenAlliedTech", False)):
        result.append("ra2_stolen_allied_tech")
    if bool(rules.get("RequiresStolenSovietTech", False)):
        result.append("ra2_stolen_soviet_tech")
    if bool(rules.get("RequiresStolenThirdTech", False)):
        result.append("ra2_stolen_yuri_tech")
    return result


def category_for_unit(entity: dict[str, Any]) -> str:
    category = str(entity.get("category", "vehicle"))
    rules = entity.get("rules", {})
    flags = entity.get("special_flags", {})
    movement_zone = str(rules.get("MovementZone", ""))
    if category == "infantry":
        return "infantry"
    if bool(flags.get("Naval", False)) or movement_zone in {"Water", "WaterBeach", "WaterOnly"}:
        return "naval"
    if category == "aircraft" or bool(flags.get("BalloonHover", False)) or bool(flags.get("JumpJet", False)) or bool(flags.get("ConsideredAircraft", False)):
        return "air"
    return "vehicle"


def convert_unit(entity: dict[str, Any], assets: Path, project_root: Path) -> dict[str, Any]:
    original_id = str(entity["id"])
    rules = entity.get("rules", {})
    weapon = weapon_stats(entity)
    raw_speed = max(0.0, first_number(entity.get("speed"), 0.0))
    size = max(1.0, first_number(rules.get("Size"), 3.0))
    category = category_for_unit(entity)
    engine_category = "infantry" if category == "infantry" else "vehicle"
    is_harvester = bool(rules.get("Harvester", False)) or bool(rules.get("ResourceGatherer", False)) or original_id in {"HARV", "CMIN", "SMIN"}
    collision = 8.0 + size * (2.0 if engine_category == "infantry" else 3.2)
    prerequisites = [rid(value) for value in entity.get("prerequisite", [])] + special_requirements(rules)
    result = {
        "name": str(entity.get("name", original_id)),
        "original_id": original_id,
        "ra2_category": category,
        "category": engine_category,
        "cost": int(first_number(entity.get("cost"), 0.0)),
        "build_time": max(1.0, first_number(entity.get("cost"), 100.0) / 110.0),
        "hp": max(1.0, first_number(entity.get("strength"), 100.0)),
        "speed": max(28.0, raw_speed * 10.0) if raw_speed > 0 else 0.0,
        "damage": weapon["damage"],
        "range": weapon["range"],
        "reload": weapon["reload"],
        "sight": int(first_number(entity.get("sight"), 5.0)),
        "radius": collision,
        "collision_radius": collision,
        "crushable": engine_category == "infantry" and not bool(rules.get("NotHuman", False)),
        "can_crush": bool(rules.get("Crusher", False)) or bool(rules.get("OmniCrusher", False)),
        "description": "YR兼容对象 %s；原始规则由 rulesmd.ini 数据驱动。" % original_id,
        "unit_type": str(entity.get("name", original_id)),
        "armor": ARMOR_SCORE.get(str(entity.get("armor", "none")).lower(), 3),
        "armor_type": str(entity.get("armor", "none")),
        "shield": 0,
        "weapon_name": weapon["weapon_name"],
        "damage_type": weapon["damage_type"],
        "aoe_radius": 0.0,
        "experience_required": [max(100, int(first_number(entity.get("cost"), 100.0) * 0.75)), max(300, int(first_number(entity.get("cost"), 100.0) * 2.2))],
        "guard_range": max(180.0, weapon["range"] * 1.25),
        "retaliate_default": True,
        "support_default": True,
        "guard_default": True,
        "chase_default": not is_harvester,
        "chase_distance": max(0.0, weapon["range"] * 0.8) if not is_harvester else 0.0,
        "support_range": max(220.0, weapon["range"] * 1.4),
        "support_allied_default": False,
        "owners": entity.get("owners", []),
        "tech_level": entity.get("tech_level", -1),
        "requires_all": prerequisites,
        "requires": prerequisites[0] if prerequisites else "",
        "required_houses": entity.get("required_houses", []),
        "forbidden_houses": entity.get("forbidden_houses", []),
        "secret_houses": [item.strip() for item in str(rules.get("SecretHouses", "")).split(",") if item.strip()],
        "build_limit": int(first_number(rules.get("BuildLimit"), 0.0)),
        "ra2_rules": rules,
        "ra2_special_flags": entity.get("special_flags", {}),
        "is_harvester": is_harvester,
        "capacity": 1000 if is_harvester else 0,
        "ore_value": 1.0,
        "is_air_unit": category == "air",
        "is_naval_unit": category == "naval",
        "team_tint": False,
    }
    result.update(visual_paths(assets, original_id, project_root))
    result["has_independent_turret"] = bool(result.get("ra2_turret_frames"))
    return result


def parse_foundation(value: Any) -> list[int]:
    text = str(value or "1x1").lower().replace(" ", "")
    if "x" in text:
        left, right = text.split("x", 1)
        try:
            return [max(1, int(left)), max(1, int(right))]
        except ValueError:
            return [1, 1]
    return [1, 1]


def convert_building(entity: dict[str, Any], assets: Path, project_root: Path) -> dict[str, Any]:
    original_id = str(entity["id"])
    rules = entity.get("rules", {})
    art = entity.get("art", {})
    weapon = weapon_stats(entity)
    power = int(first_number(rules.get("Power"), 0.0))
    factory_type = str(rules.get("Factory", ""))
    repair_facility = original_id in {"GADEPT", "NADEPT", "YADEPT"} or bool(rules.get("UnitRepair", False))
    prerequisites = [rid(value) for value in entity.get("prerequisite", [])] + special_requirements(rules)
    result = {
        "name": str(entity.get("name", original_id)),
        "original_id": original_id,
        "category": "building",
        "cost": int(first_number(entity.get("cost"), 0.0)),
        "build_time": max(1.0, first_number(entity.get("cost"), 100.0) / 95.0),
        "hp": max(1.0, first_number(entity.get("strength"), 500.0)),
        "footprint": parse_foundation(art.get("Foundation", "1x1")),
        "power_output": max(0, power),
        "power_use": max(0, -power),
        "damage": weapon["damage"],
        "range": weapon["range"],
        "reload": weapon["reload"],
        "sight": int(first_number(entity.get("sight"), 5.0)),
        "description": "YR兼容建筑 %s；原始规则由 rulesmd.ini / artmd.ini 数据驱动。" % original_id,
        "building_type": str(entity.get("name", original_id)),
        "armor": ARMOR_SCORE.get(str(entity.get("armor", "concrete")).lower(), 7),
        "armor_type": str(entity.get("armor", "concrete")),
        "shield": 0,
        "weapon_name": weapon["weapon_name"],
        "damage_type": weapon["damage_type"],
        "aoe_radius": 0.0,
        "owners": entity.get("owners", []),
        "tech_level": entity.get("tech_level", -1),
        "requires_all": prerequisites,
        "requires": prerequisites[0] if prerequisites else "",
        "required_houses": entity.get("required_houses", []),
        "forbidden_houses": entity.get("forbidden_houses", []),
        "secret_houses": [item.strip() for item in str(rules.get("SecretHouses", "")).split(",") if item.strip()],
        "build_limit": int(first_number(rules.get("BuildLimit"), 0.0)),
        "factory_type": factory_type,
        "is_production_building": factory_type in {"InfantryType", "UnitType", "AircraftType"},
        "is_naval_factory": bool(rules.get("Naval", False)) or bool(rules.get("WaterBound", False)),
        "repair_facility": repair_facility,
        "is_refinery": bool(rules.get("Refinery", False)) or original_id in {"GAREFN", "NAREFN", "YAREFN"},
        "construction_yard": bool(rules.get("ConstructionYard", False)) or original_id in {"GACNST", "NACNST", "YACNST"},
        "has_turret_visual": bool(entity.get("assets", {}).get("turret_anim")),
        "ra2_rules": rules,
        "ra2_art": art,
        "team_tint": False,
    }
    result.update(visual_paths(assets, original_id, project_root))
    if result["is_refinery"]:
        side = "GDI" if original_id.startswith("GA") else ("ThirdSide" if original_id.startswith("YA") else "Nod")
        result["grants_unit"] = rid(SIDE_START[side]["harvester"])
    return result


def production_bucket(entity: dict[str, Any]) -> str:
    if entity.get("category") == "building":
        rules = entity.get("rules", {})
        build_cat = str(rules.get("BuildCat", "")).lower()
        if bool(rules.get("Refinery", False)) or bool(rules.get("ConstructionYard", False)) or bool(rules.get("Factory", "")):
            return "primary"
        return "defense" if build_cat == "combat" or bool(rules.get("Wall", False)) else "primary"
    return category_for_unit(entity)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Iron Meridian runtime data from the full RA2/YR catalog and converted assets")
    parser.add_argument("catalog", type=Path)
    parser.add_argument("asset_root", type=Path)
    parser.add_argument("project_root", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    catalog = load(args.catalog.resolve())
    project_root = args.project_root.resolve()
    asset_root = args.asset_root.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)

    units: dict[str, Any] = {}
    buildings: dict[str, Any] = {}
    for original_id in catalog.get("playable_or_starting_entities", []):
        entity = catalog["entities"][original_id]
        if entity.get("category") == "building":
            converted_building = convert_building(entity, asset_root, project_root)
            converted_building["production_category"] = production_bucket(entity)
            buildings[rid(original_id)] = converted_building
        else:
            units[rid(original_id)] = convert_unit(entity, asset_root, project_root)

    factions: dict[str, Any] = {}
    production: dict[str, Any] = {}
    for country_id in catalog.get("playable_countries", []):
        country = catalog["countries"][country_id]
        side = str(country.get("side", ""))
        faction_id = "ra2_" + country_id.lower()
        factions[faction_id] = {
            "name": COUNTRY_NAME_ZH.get(country_id, country_id),
            "description": "%s国家；单位、建筑和国家专属限制来自 rulesmd.ini。" % SIDE_NAME_ZH.get(side, side),
            "accent": country.get("color", "7F8C8D"),
            "unit_modifiers": {"hp": 1.0, "speed": 1.0, "damage": 1.0, "cost": 1.0},
            "ra2_country": country_id,
            "ra2_side": side,
            "compatibility_mode": True,
            "starting": {key: rid(value) for key, value in SIDE_START[side].items()},
        }
        buckets = {"primary": [], "defense": [], "infantry": [], "vehicle": [], "air": [], "naval": []}
        for original_id in catalog.get("buildable_entities", []):
            entity = catalog["entities"][original_id]
            if not entity_allowed_for_country(entity, country_id, side):
                continue
            bucket = production_bucket(entity)
            if bucket in buckets:
                buckets[bucket].append(rid(original_id))
        for key in buckets:
            buckets[key].sort(key=lambda item: (int((buildings if key in {"primary", "defense"} else units).get(item, {}).get("tech_level", -1)), int((buildings if key in {"primary", "defense"} else units).get(item, {}).get("cost", 0)), item))
        production[faction_id] = buckets

    payloads = {
        "runtime_units.json": units,
        "runtime_buildings.json": buildings,
        "runtime_factions.json": factions,
        "production_lists.json": production,
    }
    for name, payload in payloads.items():
        (output / name).write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"ok": True, "units": len(units), "buildings": len(buildings), "factions": len(factions)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

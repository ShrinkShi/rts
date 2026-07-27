from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import json
from pathlib import Path
from typing import Any, Iterable

from .assets import AssetIndex, AssetRecord, THEATERS
from .sequences import parse_sequence_entry
from .values import as_bool, as_number, as_vector, normalized_scalar, split_csv
from .westwood_ini import ParsedIni, ParsedSection, merge_ini_layers, ordered_values, parse_ini_file

ENTITY_LIST_SECTIONS = {
    "InfantryTypes": "infantry",
    "VehicleTypes": "vehicle",
    "AircraftTypes": "aircraft",
    "BuildingTypes": "building",
}

BUILDING_COMPONENT_KEYS = (
    "Buildup", "BibShape",
    "ActiveAnim", "ActiveAnimDamaged",
    "ActiveAnimTwo", "ActiveAnimTwoDamaged",
    "ActiveAnimThree", "ActiveAnimThreeDamaged",
    "ActiveAnimFour", "ActiveAnimFourDamaged",
    "IdleAnim", "IdleAnimDamaged", "IdleAnimTwo", "IdleAnimTwoDamaged",
    "SpecialAnim", "SpecialAnimDamaged",
    "SpecialAnimTwo", "SpecialAnimTwoDamaged",
    "SpecialAnimThree", "SpecialAnimThreeDamaged",
    "SpecialAnimFour", "SpecialAnimFourDamaged",
    "ProductionAnim", "ProductionAnimDamaged",
    "DeployingAnim", "DeployingAnimDamaged",
    "RoofDeployingAnim", "RoofDeployingAnimDamaged",
    "UnderDoorAnim", "UnderDoorAnimDamaged",
    "UnderRoofDoorAnim", "UnderRoofDoorAnimDamaged",
    "DoorAnim", "DoorAnimDamaged",
    "PowerUp1Anim", "PowerUp1AnimDamaged",
    "PowerUp2Anim", "PowerUp2AnimDamaged",
    "PowerUp3Anim", "PowerUp3AnimDamaged",
    "SuperAnim", "SuperAnimDamaged",
    "SuperAnimTwo", "SuperAnimTwoDamaged",
    "SuperAnimThree", "SuperAnimThreeDamaged",
    "SuperAnimFour", "SuperAnimFourDamaged",
    "SuperLowPower", "SuperLowPowerDamaged",
    "ActiveAnimGarrisoned",
)


WEAPON_KEYS = (
    "Primary", "Secondary", "ElitePrimary", "EliteSecondary",
    *tuple(f"Weapon{index}" for index in range(1, 18)),
    *tuple(f"EliteWeapon{index}" for index in range(1, 18)),
)

SOUND_KEYS = (
    "VoiceSelect", "VoiceMove", "VoiceAttack", "VoiceFeedback", "VoiceSpecialAttack",
    "DieSound", "CrushSound", "MoveSound", "DeploySound", "UndeploySound",
    "CreateSound", "EnterTransportSound", "LeaveTransportSound", "TurretRotateSound",
    "AuxSound1", "AuxSound2", "AmbientSound", "WorkingSound", "NotWorkingSound",
)


@dataclass(frozen=True)
class BuildPaths:
    ra2_root: Path
    ra2md_root: Path
    output: Path
    extra_roots: tuple[tuple[str, Path], ...] = ()


class DatabaseBuilder:
    def __init__(self, paths: BuildPaths):
        self.paths = paths
        self.assets = AssetIndex()
        self.rules: ParsedIni
        self.art: ParsedIni
        self.sound: ParsedIni
        self.ai: ParsedIni
        self.issues: list[dict[str, Any]] = []
        self.referenced_weapons: set[str] = set()
        self.referenced_projectiles: set[str] = set()
        self.referenced_warheads: set[str] = set()
        self.referenced_sounds: set[str] = set()

    def load(self) -> None:
        roots = (("ra2", self.paths.ra2_root), ("ra2md", self.paths.ra2md_root), *self.paths.extra_roots)
        self.assets.scan(roots)

        def existing_layers(base_layers: list[ParsedIni], filename: str) -> ParsedIni:
            layers = list(base_layers)
            for layer_name, root in self.paths.extra_roots:
                candidate = root / filename
                if candidate.is_file():
                    layers.append(parse_ini_file(candidate, layer=layer_name))
            return merge_ini_layers(layers)

        self.rules = existing_layers([
            parse_ini_file(self.paths.ra2_root / "local" / "rules.ini", layer="ra2"),
            parse_ini_file(self.paths.ra2md_root / "localmd" / "rulesmd.ini", layer="ra2md"),
        ], "rulesmd.ini")
        self.art = existing_layers([
            parse_ini_file(self.paths.ra2_root / "local" / "art.ini", layer="ra2"),
            parse_ini_file(self.paths.ra2md_root / "localmd" / "artmd.ini", layer="ra2md"),
        ], "artmd.ini")
        self.sound = existing_layers([
            parse_ini_file(self.paths.ra2_root / "local" / "sound.ini", layer="ra2"),
            parse_ini_file(self.paths.ra2md_root / "localmd" / "soundmd.ini", layer="ra2md"),
        ], "soundmd.ini")
        self.ai = existing_layers([
            parse_ini_file(self.paths.ra2_root / "local" / "ai.ini", layer="ra2"),
            parse_ini_file(self.paths.ra2md_root / "localmd" / "aimd.ini", layer="ra2md"),
        ], "aimd.ini")

    @staticmethod
    def _record(record: AssetRecord | None) -> dict[str, Any] | None:
        return record.to_dict() if record is not None else None

    @staticmethod
    def _section_payload(section: ParsedSection | None) -> dict[str, Any]:
        if section is None:
            return {"values": {}, "provenance": {}}
        return {
            "values": {key: normalized_scalar(value) for key, value in section.items()},
            "raw_values": section.values_dict(),
            "provenance": section.provenance_dict(),
        }

    def _issue(self, issue_type: str, subject: str, **details: Any) -> None:
        self.issues.append({"type": issue_type, "subject": subject, **details})

    @staticmethod
    def _building_component_slot(key: str) -> str:
        return key[:-7] if key.endswith("Damaged") else key

    @classmethod
    def _building_component_parent_metadata(cls, art_section: ParsedSection, key: str) -> dict[str, Any]:
        slot = cls._building_component_slot(key)
        result: dict[str, Any] = {
            "component_key": key,
            "slot": slot,
            "damaged": key.endswith("Damaged"),
        }
        for suffix in ("X", "Y", "ZAdjust", "YSort"):
            raw = art_section.get(slot + suffix)
            if raw is not None:
                result[suffix] = as_number(raw, 0)
        for suffix in ("Powered", "PoweredSpecial", "PoweredLight"):
            raw = art_section.get(slot + suffix)
            if raw is not None:
                result[suffix] = as_bool(raw, False)
        return result

    def _resolve_art_object(self, art_id: str, *, theater: str, role: str = "body", inherited_new_theater: bool = False) -> dict[str, Any]:
        section = self.art.get_section(art_id)
        image = section.get("Image", art_id) if section else art_id
        new_theater = inherited_new_theater or (as_bool(section.get("NewTheater"), False) if section else False)
        record = self.assets.resolve_shp(str(image), theater=theater, new_theater=new_theater, role=role)
        result: dict[str, Any] = {
            "art_id": art_id,
            "image": image,
            "new_theater": new_theater,
            "asset": self._record(record),
        }
        if section is not None:
            for key in (
                "Start", "End", "LoopStart", "LoopEnd", "LoopCount", "Rate",
                "Reverse", "Shadow", "DoubleThick", "Surface",
                "Layer", "DetailLevel", "Translucency", "ZAdjust", "YSortAdjust",
            ):
                value = section.get(key)
                if value is not None:
                    result[key] = normalized_scalar(value)
            result["provenance"] = section.provenance_dict()
        if record is None:
            self._issue("missing_art_asset", art_id, image=image, theater=theater, role=role, new_theater=new_theater)
        return result

    def _resolve_entity_visuals(self, entity_id: str, category: str, rules_section: ParsedSection, art_id: str, art_section: ParsedSection | None) -> dict[str, Any]:
        new_theater = as_bool(art_section.get("NewTheater"), False) if art_section else False
        voxel_body = self.assets.resolve_voxel_part(art_id, ".vxl")
        visual_kind = "building_shp" if category == "building" else ("voxel" if voxel_body is not None else "shp")
        visuals: dict[str, Any] = {
            "kind": visual_kind,
            "art_id": art_id,
            "new_theater": new_theater,
            "theaters": {},
        }

        if visual_kind == "voxel":
            body_hva = self.assets.resolve_voxel_part(art_id, ".hva")
            turret_stem = art_id + "tur"
            barrel_stem = art_id + "barl"
            visuals["body"] = self._record(voxel_body)
            visuals["body_hva"] = self._record(body_hva)
            visuals["turret"] = self._record(self.assets.resolve_voxel_part(turret_stem, ".vxl"))
            visuals["turret_hva"] = self._record(self.assets.resolve_voxel_part(turret_stem, ".hva"))
            visuals["barrel"] = self._record(self.assets.resolve_voxel_part(barrel_stem, ".vxl"))
            visuals["barrel_hva"] = self._record(self.assets.resolve_voxel_part(barrel_stem, ".hva"))
            visuals["turret_offset_leptons"] = as_number(art_section.get("TurretOffset"), 0) if art_section else 0
            visuals["primary_fire_flh"] = as_vector(art_section.get("PrimaryFireFLH"), 3) if art_section else None
            visuals["secondary_fire_flh"] = as_vector(art_section.get("SecondaryFireFLH"), 3) if art_section else None
            visuals["shadow_index"] = as_number(art_section.get("ShadowIndex"), 0) if art_section else 0
            visuals["use_turret_shadow"] = as_bool(art_section.get("UseTurretShadow"), False) if art_section else False
            visuals["no_spawn_alt"] = as_bool(art_section.get("NoSpawnAlt"), False) if art_section else False
            if visuals["no_spawn_alt"]:
                visuals["no_spawn_body"] = self._record(self.assets.resolve_voxel_part(art_id + "wo", ".vxl"))
                visuals["no_spawn_hva"] = self._record(self.assets.resolve_voxel_part(art_id + "wo", ".hva"))
            if body_hva is None:
                self._issue("missing_voxel_hva", entity_id, art_id=art_id)
        else:
            for theater in THEATERS:
                body = self.assets.resolve_shp(art_id, theater=theater, new_theater=new_theater, role="body")
                palette_name = str(THEATERS[theater]["unit_palette"])
                visuals["theaters"][theater] = {
                    "body": self._record(body),
                    "palette": self._record(self.assets.resolve_palette(palette_name)),
                }
                if body is None:
                    self._issue("missing_entity_shp", entity_id, art_id=art_id, theater=theater)

        if category == "infantry" and art_section is not None:
            sequence_id = art_section.get("Sequence", "") or ""
            sequence_section = self.art.get_section(sequence_id) if sequence_id else None
            sequences: dict[str, Any] = {}
            if sequence_section is not None:
                for name, raw in sequence_section.items():
                    parsed = parse_sequence_entry(name, raw)
                    if parsed is None:
                        self._issue("invalid_sequence_entry", entity_id, sequence=sequence_id, name=name, raw=raw)
                        continue
                    sequences[name] = parsed.to_dict()
            else:
                self._issue("missing_sequence", entity_id, sequence=sequence_id, art_id=art_id)
            visuals["sequence_id"] = sequence_id
            visuals["sequences"] = sequences

        if category == "building" and art_section is not None:
            components: dict[str, Any] = {}
            for key in BUILDING_COMPONENT_KEYS:
                component_id = art_section.get(key)
                if not component_id or component_id.casefold() == "none":
                    continue
                role = "buildup" if key in {"Buildup", "BibShape"} else "body"
                parent_metadata = self._building_component_parent_metadata(art_section, key)
                theater_components: dict[str, Any] = {}
                for theater in THEATERS:
                    resolved = self._resolve_art_object(
                        component_id,
                        theater=theater,
                        role=role,
                        inherited_new_theater=new_theater,
                    )
                    resolved.update(parent_metadata)
                    theater_components[theater] = resolved
                components[key] = theater_components
            visuals["components"] = components
            visuals["foundation"] = art_section.get("Foundation", "1x1")
            visuals["height"] = as_number(art_section.get("Height"), 0)
            visuals["occupy_height"] = as_number(art_section.get("OccupyHeight"), 0)
            visuals["damage_fire_offsets"] = [
                as_vector(value, 2)
                for key, value in art_section.items()
                if key.casefold().startswith("damagefireoffset") and as_vector(value, 2) is not None
            ]
            visuals["zshape_point_move"] = as_vector(art_section.get("ZShapePointMove"), 2)

            turret_anim = rules_section.get("TurretAnim")
            if turret_anim:
                turret_is_voxel = as_bool(rules_section.get("TurretAnimIsVoxel"), False)
                visuals["building_turret"] = {
                    "id": turret_anim,
                    "is_voxel": turret_is_voxel,
                    "x": as_number(rules_section.get("TurretAnimX"), 0),
                    "y": as_number(rules_section.get("TurretAnimY"), 0),
                    "z_adjust": as_number(rules_section.get("TurretAnimZAdjust"), 0),
                    "model": self._record(self.assets.resolve_voxel_part(turret_anim, ".vxl")) if turret_is_voxel else None,
                    "hva": self._record(self.assets.resolve_voxel_part(turret_anim, ".hva")) if turret_is_voxel else None,
                    "barrel": self._record(self.assets.resolve_voxel_part(art_id + "barl", ".vxl")) if turret_is_voxel else None,
                    "barrel_hva": self._record(self.assets.resolve_voxel_part(art_id + "barl", ".hva")) if turret_is_voxel else None,
                }
        else:
            deploy_anim = rules_section.get("DeployingAnim")
            if deploy_anim:
                deploy_section = self.art.get_section(deploy_anim)
                deploy_image = deploy_section.get("Image", deploy_anim) if deploy_section else deploy_anim
                deploy_record = self.assets.resolve_shp(str(deploy_image), theater="temperate", new_theater=False, role="body")
                visuals["deploying_animation"] = {
                    "id": deploy_anim,
                    "asset": self._record(deploy_record),
                    "rate": as_number(deploy_section.get("Rate"), 100) if deploy_section else 100,
                    "shadow": as_bool(deploy_section.get("Shadow"), False) if deploy_section else False,
                }
        return visuals

    def _weapon_ref(self, weapon_id: str) -> dict[str, Any]:
        section = self.rules.get_section(weapon_id)
        self.referenced_weapons.add(weapon_id)
        if section is None:
            self._issue("missing_weapon_section", weapon_id)
            return {"id": weapon_id, "missing": True}
        projectile = section.get("Projectile")
        warhead = section.get("Warhead")
        report = split_csv(section.get("Report"))
        if projectile:
            self.referenced_projectiles.add(projectile)
        if warhead:
            self.referenced_warheads.add(warhead)
        self.referenced_sounds.update(report)
        return {
            "id": weapon_id,
            "projectile": projectile,
            "warhead": warhead,
            "report": report,
            **self._section_payload(section),
        }

    def _entity(self, entity_id: str, category: str) -> dict[str, Any]:
        rules_section = self.rules.get_section(entity_id)
        if rules_section is None:
            self._issue("missing_entity_section", entity_id, category=category)
            return {"id": entity_id, "category": category, "missing": True}
        art_id = rules_section.get("Image", entity_id) or entity_id
        art_section = self.art.get_section(art_id) or self.art.get_section(entity_id)
        if art_section is None:
            self._issue("missing_art_section", entity_id, art_id=art_id)

        weapons: dict[str, Any] = {}
        for key in WEAPON_KEYS:
            weapon_id = rules_section.get(key)
            if weapon_id and weapon_id.casefold() != "none":
                weapons[key] = self._weapon_ref(weapon_id)

        sounds: dict[str, list[str]] = {}
        for key in SOUND_KEYS:
            values = split_csv(rules_section.get(key))
            if values:
                sounds[key] = values
                self.referenced_sounds.update(values)

        owners = split_csv(rules_section.get("Owner"))
        required = split_csv(rules_section.get("RequiredHouses"))
        forbidden = split_csv(rules_section.get("ForbiddenHouses"))
        prerequisites = split_csv(rules_section.get("Prerequisite"))
        return {
            "id": entity_id,
            "category": category,
            "name_token": rules_section.get("UIName") or rules_section.get("Name") or entity_id,
            "art_id": art_id,
            "owners": owners,
            "required_houses": required,
            "forbidden_houses": forbidden,
            "prerequisite": prerequisites,
            "tech_level": as_number(rules_section.get("TechLevel"), -1),
            "cost": as_number(rules_section.get("Cost"), 0),
            "strength": as_number(rules_section.get("Strength"), 0),
            "armor": rules_section.get("Armor", ""),
            "speed": as_number(rules_section.get("Speed"), 0),
            "sight": as_number(rules_section.get("Sight"), 0),
            "locomotor": rules_section.get("Locomotor", ""),
            "movement_zone": rules_section.get("MovementZone", ""),
            "weapons": weapons,
            "sounds": sounds,
            "visuals": self._resolve_entity_visuals(entity_id, category, rules_section, art_id, art_section),
            "rules": self._section_payload(rules_section),
            "art": self._section_payload(art_section),
        }

    def _list_entities(self) -> list[dict[str, Any]]:
        result: list[dict[str, Any]] = []
        seen: set[str] = set()
        for list_section_name, category in ENTITY_LIST_SECTIONS.items():
            section = self.rules.get_section(list_section_name)
            for entity_id in ordered_values(section):
                folded = entity_id.casefold()
                if folded in seen:
                    continue
                seen.add(folded)
                result.append(self._entity(entity_id, category))
        return result

    def _referenced_sections(self, ids: Iterable[str], source: ParsedIni, kind: str) -> list[dict[str, Any]]:
        result: list[dict[str, Any]] = []
        for section_id in sorted(set(ids), key=str.casefold):
            section = source.get_section(section_id)
            if section is None:
                self._issue(f"missing_{kind}_section", section_id)
                result.append({"id": section_id, "missing": True})
                continue
            result.append({"id": section_id, **self._section_payload(section)})
        return result

    def _countries(self) -> list[dict[str, Any]]:
        result: list[dict[str, Any]] = []
        for country_id in ordered_values(self.rules.get_section("Countries")):
            section = self.rules.get_section(country_id)
            result.append({"id": country_id, **self._section_payload(section)})
        return result

    def _sides(self) -> dict[str, Any]:
        return self._section_payload(self.rules.get_section("Sides"))

    def build(self) -> dict[str, Any]:
        entities = self._list_entities()
        weapons = self._referenced_sections(self.referenced_weapons, self.rules, "weapon")
        projectiles = self._referenced_sections(self.referenced_projectiles, self.rules, "projectile")
        warheads = self._referenced_sections(self.referenced_warheads, self.rules, "warhead")
        sounds = self._referenced_sections(self.referenced_sounds, self.sound, "sound")

        category_counts: dict[str, int] = {}
        visual_counts: dict[str, int] = {}
        for entity in entities:
            category = str(entity.get("category", "unknown"))
            category_counts[category] = category_counts.get(category, 0) + 1
            kind = str(entity.get("visuals", {}).get("kind", "missing"))
            visual_counts[kind] = visual_counts.get(kind, 0) + 1

        database = {
            "schema_version": 2,
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "source_policy": {
                "rules": ["rules.ini", "rulesmd.ini"],
                "art": ["art.ini", "artmd.ini"],
                "sound": ["sound.ini", "soundmd.ini"],
                "override_rule": "later Yuri's Revenge layer wins; every overridden value keeps history",
            },
            "summary": {
                **self.assets.summary(),
                "entity_count": len(entities),
                "category_counts": category_counts,
                "visual_kind_counts": visual_counts,
                "weapon_count": len(weapons),
                "projectile_count": len(projectiles),
                "warhead_count": len(warheads),
                "sound_count": len(sounds),
                "country_count": len(self._countries()),
                "issue_count": len(self.issues),
            },
            "theaters": THEATERS,
            "countries": self._countries(),
            "sides": self._sides(),
            "entities": entities,
            "weapons": weapons,
            "projectiles": projectiles,
            "warheads": warheads,
            "sounds": sounds,
            "assets": [record.to_dict() for record in self.assets.records],
            "issues": self.issues,
            "parser": {
                "rules_encodings": self.rules.encodings,
                "art_encodings": self.art.encodings,
                "sound_encodings": self.sound.encodings,
                "ai_encodings": self.ai.encodings,
                "warnings": [*self.rules.parse_warnings, *self.art.parse_warnings, *self.sound.parse_warnings, *self.ai.parse_warnings],
            },
        }
        return database

    def write(self, database: dict[str, Any]) -> None:
        output = self.paths.output
        output.mkdir(parents=True, exist_ok=True)
        (output / "database.json").write_text(json.dumps(database, ensure_ascii=False, indent=2), encoding="utf-8")
        for key in ("summary", "countries", "sides", "entities", "weapons", "projectiles", "warheads", "sounds", "assets", "issues", "theaters"):
            payload = database[key] if key in database else database.get("summary", {})
            (output / f"{key}.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

        entity_dir = output / "entities"
        entity_dir.mkdir(parents=True, exist_ok=True)
        catalog: list[dict[str, Any]] = []
        for entity in database["entities"]:
            entity_id = str(entity.get("id", "unknown"))
            safe_name = "".join(character.lower() if character.isalnum() else "_" for character in entity_id)
            (entity_dir / f"{safe_name}.json").write_text(
                json.dumps(entity, ensure_ascii=False, indent=2), encoding="utf-8"
            )
            visuals = entity.get("visuals", {})
            catalog.append({
                "id": entity_id,
                "file": f"entities/{safe_name}.json",
                "category": entity.get("category", ""),
                "name_token": entity.get("name_token", entity_id),
                "art_id": entity.get("art_id", entity_id),
                "visual_kind": visuals.get("kind", "missing"),
                "owners": entity.get("owners", []),
                "cost": entity.get("cost", 0),
                "tech_level": entity.get("tech_level", -1),
                "preview": f"res://assets/ra2_preview/{entity_id.lower()}/normal.png",
            })
        (output / "catalog.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2), encoding="utf-8")

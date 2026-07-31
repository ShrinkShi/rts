extends Node

const RA2_RESOURCE_MANIFEST := "res://data/ra2_embedded/temperate_resources_v2.json"

var factions = {}
var units = {}
var buildings = {}
var maps = {}
var modes = {}
var current_match = {}


func _ready():
    load_all()


func load_all():
    factions = _load_json("res://data/factions.json")
    units = _load_json("res://data/units.json")
    buildings = _load_json("res://data/buildings.json")
    maps = _load_json("res://data/maps.json")
    var height_maps: Dictionary = _load_json("res://data/maps_height.json")
    for map_id in height_maps.keys():
        maps[str(map_id)] = height_maps[map_id]
    var ra2_maps: Dictionary = _load_json("res://data/maps_ra2.json")
    for map_id in ra2_maps.keys():
        var definition_variant: Variant = ra2_maps[map_id]
        if not definition_variant is Dictionary:
            push_warning("Ignoring invalid RA2 map definition: %s" % str(map_id))
            continue
        var definition: Dictionary = definition_variant
        if _ra2_map_bundle_ready(definition):
            maps[str(map_id)] = definition
        else:
            push_warning(
                "RA2 map bundle is incomplete and will not appear in the map list: %s"
                % str(map_id)
            )
    modes = _load_json("res://data/modes.json")


func _ra2_map_bundle_ready(definition: Dictionary) -> bool:
    var format_name: String = str(definition.get("format", ""))
    if format_name != "ra2_runtime_v2":
        return false
    var manifest_path: String = str(definition.get("runtime_manifest", ""))
    var manifest: Dictionary = _load_json_quiet(manifest_path)
    if manifest.is_empty():
        return false
    if str(manifest.get("format", "")) != "ra2-godot-runtime-v2":
        return false
    if not _chunk_definition_ready(manifest.get("cells", {})):
        return false
    if not _chunk_definition_ready(manifest.get("background", {})):
        return false

    var resource_manifest: Dictionary = _load_json_quiet(RA2_RESOURCE_MANIFEST)
    if resource_manifest.is_empty():
        return false
    if str(resource_manifest.get("format", "")) != "ra2-resource-atlas-v2":
        return false
    return _chunk_definition_ready(resource_manifest)


func _chunk_definition_ready(definition_variant: Variant) -> bool:
    if not definition_variant is Dictionary:
        return false
    var definition: Dictionary = definition_variant
    var chunk_template: String = str(definition.get("chunk_template", ""))
    var chunk_count: int = int(definition.get("chunk_count", 0))
    if chunk_template.is_empty() or chunk_count <= 0:
        return false
    for index in range(chunk_count):
        if not FileAccess.file_exists(chunk_template % index):
            return false
    return true


func _load_json(path):
    if not FileAccess.file_exists(path):
        push_error("Missing data file: " + path)
        return {}
    var file = FileAccess.open(path, FileAccess.READ)
    var parsed = JSON.parse_string(file.get_as_text())
    if parsed == null or not (parsed is Dictionary):
        push_error("Invalid JSON: " + path)
        return {}
    return parsed


func _load_json_quiet(path: String) -> Dictionary:
    if path.is_empty() or not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed if parsed is Dictionary else {}


func make_default_skirmish():
    return {
        "kind": "skirmish",
        "map_id": "twin_rivers",
        "mode_id": "standard",
        "starting_credits": 10000,
        "fog_of_war": true,
        "players": [
            {"controller": "human", "faction": "union", "color": "4FA3FF", "position": 0, "team": 1, "difficulty": "normal"},
            {"controller": "ai", "faction": "dominion", "color": "E14B4B", "position": 1, "team": 2, "difficulty": "normal"}
        ]
    }


func make_training_campaign():
    return {
        "kind": "campaign",
        "mission_id": "training_01",
        "map_id": "dust_bowl",
        "mode_id": "headquarters",
        "starting_credits": 6000,
        "fog_of_war": true,
        "players": [
            {"controller": "human", "faction": "union", "color": "4FA3FF", "position": 0, "team": 1, "difficulty": "normal"},
            {"controller": "scripted", "faction": "dominion", "color": "E14B4B", "position": 1, "team": 2, "difficulty": "easy"}
        ]
    }


func make_training_campaign_02():
    return {
        "kind": "campaign",
        "mission_id": "training_02",
        "map_id": "frontier_expanse",
        "mode_id": "headquarters",
        "starting_credits": 9000,
        "fog_of_war": true,
        "players": [
            {"controller":"human","faction":"union","color":"4FA3FF","position":0,"team":1,"difficulty":"normal"},
            {"controller":"scripted","faction":"dominion","color":"E14B4B","position":1,"team":2,"difficulty":"hard"}
        ]
    }


func faction_name(faction_id):
    return factions.get(faction_id, {}).get("name", faction_id)


func get_player_color(player_id):
    if not current_match.has("players") or player_id >= current_match.players.size():
        return Color.WHITE
    return Color("#" + str(current_match.players[player_id].get("color", "FFFFFF")))

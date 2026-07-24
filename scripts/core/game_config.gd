extends Node

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
    modes = _load_json("res://data/modes.json")

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

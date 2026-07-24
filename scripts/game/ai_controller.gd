extends Node

var match_ref
var owner_id = 1
var difficulty = "normal"
var think_timer = 3.0
var attack_timer = 18.0
var economy_timer = 7.0

func setup(next_match, next_owner, next_difficulty):
    match_ref = next_match
    owner_id = next_owner
    difficulty = next_difficulty
    if difficulty == "easy":
        attack_timer = 28.0
    elif difficulty == "hard":
        attack_timer = 13.0

func _process(delta):
    if not is_instance_valid(match_ref) or match_ref.game_over:
        return
    think_timer -= delta
    attack_timer -= delta
    economy_timer -= delta
    if economy_timer <= 0.0:
        economy_timer = 8.0 if difficulty == "easy" else 6.0
        var stipend = 350 if difficulty == "easy" else 550
        if difficulty == "hard":
            stipend = 800
        match_ref.add_credits(owner_id, stipend)
    if think_timer <= 0.0:
        think_timer = 4.5 if difficulty == "easy" else 3.0
        _produce()
    if attack_timer <= 0.0:
        attack_timer = 30.0 if difficulty == "easy" else 21.0
        if difficulty == "hard":
            attack_timer = 15.0
        _launch_attack()

func _produce():
    var combat_count = 0
    for unit in match_ref.units:
        if is_instance_valid(unit) and unit.owner_id == owner_id and unit.is_combat_unit():
            combat_count += 1
    var choice = "rifle"
    if match_ref.has_building(owner_id, "war_factory") and combat_count >= 3:
        choice = "tank" if randf() > 0.35 else "scout"
    elif randf() > 0.72:
        choice = "rocket"
    match_ref.request_ai_unit(owner_id, choice)

func _launch_attack():
    var target_building = match_ref.get_nearest_enemy_command(owner_id)
    if not is_instance_valid(target_building):
        return
    var attackers = []
    for unit in match_ref.units:
        if is_instance_valid(unit) and unit.owner_id == owner_id and unit.is_combat_unit():
            attackers.append(unit)
    var minimum = 3 if difficulty == "easy" else 4
    if attackers.size() < minimum:
        return
    for unit in attackers:
        unit.command_attack(target_building)
    EventBus.notification_requested.emit("敌军正在向我方基地集结", "warning")

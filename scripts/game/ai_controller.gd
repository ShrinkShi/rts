extends Node

var match_ref
var owner_id = 1
var difficulty = "normal"
var think_timer = 3.0
var attack_timer = 18.0
var economy_timer = 7.0
var defend_timer = 1.2

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
    defend_timer -= delta
    if economy_timer <= 0.0:
        economy_timer = 8.0 if difficulty == "easy" else 6.0
        var stipend = 350 if difficulty == "easy" else 550
        if difficulty == "hard":
            stipend = 800
        match_ref.add_credits(owner_id, stipend)
    if defend_timer <= 0.0:
        defend_timer = 1.8 if difficulty == "easy" else 1.1
        _respond_to_local_threats()
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

func _army_center(units):
    var center = Vector2.ZERO
    var count = 0
    for unit in units:
        if is_instance_valid(unit):
            center += unit.global_position
            count += 1
    return center / float(count) if count > 0 else Vector2.ZERO

func _strategic_priority(building_id):
    # Lower is attacked earlier. The command center is deliberately not the
    # default target while production, defense or economy structures survive.
    return {
        "turret": -140000.0,
        "bunker": -125000.0,
        "war_factory": -105000.0,
        "barracks": -85000.0,
        "repair_bay": -72000.0,
        "refinery": -65000.0,
        "power": -42000.0,
        "command": 60000.0
    }.get(building_id, 0.0)

func _choose_strategic_target(attackers):
    var center = _army_center(attackers)
    var best = null
    var best_score = INF
    var has_non_command = false
    for building in match_ref.buildings:
        if not is_instance_valid(building) or not match_ref.are_enemies(owner_id, building.owner_id):
            continue
        if building.building_id != "command":
            has_non_command = true
    for building in match_ref.buildings:
        if not is_instance_valid(building) or not match_ref.are_enemies(owner_id, building.owner_id):
            continue
        if has_non_command and building.building_id == "command":
            continue
        var score = center.distance_squared_to(building.global_position) + _strategic_priority(str(building.building_id))
        # Prefer objectives with nearby enemy units: the wave will attack-move
        # there and clear the encountered screen before damaging the structure.
        var defenders = match_ref.query_units_in_radius(building.global_position, 260.0)
        for defender in defenders:
            if is_instance_valid(defender) and match_ref.are_enemies(owner_id, defender.owner_id):
                score -= 8500.0
        if score < best_score:
            best_score = score
            best = building
    return best

func _available_attackers():
    var result = []
    for unit in match_ref.units:
        if not is_instance_valid(unit) or unit.owner_id != owner_id or not unit.is_combat_unit():
            continue
        if unit.dying or unit.inside_repair_bay or unit.inside_refinery:
            continue
        result.append(unit)
    return result

func _launch_attack():
    var attackers = _available_attackers()
    var minimum = 3 if difficulty == "easy" else 4
    if attackers.size() < minimum:
        return
    var objective = _choose_strategic_target(attackers)
    if not is_instance_valid(objective):
        return
    # Keep a small reserve instead of emptying the whole base every cycle.
    attackers.sort_custom(func(a, b): return a.global_position.distance_squared_to(objective.global_position) < b.global_position.distance_squared_to(objective.global_position))
    var reserve = 2 if attackers.size() >= 7 else 1
    var wave_count = max(minimum, attackers.size() - reserve)
    for index in range(min(wave_count, attackers.size())):
        var unit = attackers[index]
        unit.command_attack_move(objective.global_position)
    EventBus.notification_requested.emit("敌军正在向我方重要设施推进", "warning")

func _respond_to_local_threats():
    var base_anchor = match_ref.get_nearest_building(owner_id, "command", Vector2.ZERO)
    if not is_instance_valid(base_anchor):
        return
    var threat = match_ref.find_nearest_enemy(owner_id, base_anchor.global_position, 430.0)
    if not is_instance_valid(threat):
        return
    var responders = []
    for unit in _available_attackers():
        var order_type = str(unit.active_order.get("type", ""))
        if unit.global_position.distance_to(base_anchor.global_position) <= 520.0 and (unit.active_order.is_empty() or order_type in ["hold", "support_attack"]):
            responders.append(unit)
    responders.sort_custom(func(a, b): return a.global_position.distance_squared_to(threat.global_position) < b.global_position.distance_squared_to(threat.global_position))
    var response_count = min(responders.size(), 2 if difficulty == "easy" else 4)
    for index in range(response_count):
        responders[index].command_attack_move(threat.global_position)

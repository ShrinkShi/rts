extends Node

var match_ref
var owner_id: int = 1
var difficulty: String = "normal"
var think_timer: float = 2.0
var attack_timer: float = 18.0
var economy_timer: float = 6.0
var defend_timer: float = 1.2
var build_job: Dictionary = {}
var last_completed_structure: String = ""
var build_plan_step: String = ""

func setup(next_match, next_owner, next_difficulty):
    match_ref = next_match
    owner_id = int(next_owner)
    difficulty = str(next_difficulty)
    if difficulty == "easy":
        attack_timer = 28.0
    elif difficulty == "hard":
        attack_timer = 13.0

func _process(delta):
    if not is_instance_valid(match_ref) or match_ref.game_over:
        return
    _process_build_job(delta)
    think_timer -= delta
    attack_timer -= delta
    economy_timer -= delta
    defend_timer -= delta
    if economy_timer <= 0.0:
        economy_timer = 10.0 if difficulty == "easy" else 7.0
        _emergency_economy_support()
    if defend_timer <= 0.0:
        defend_timer = 1.8 if difficulty == "easy" else 1.1
        _respond_to_local_threats()
    if think_timer <= 0.0:
        think_timer = 4.5 if difficulty == "easy" else 2.8
        _think_economy_and_production()
    if attack_timer <= 0.0:
        attack_timer = 30.0 if difficulty == "easy" else 21.0
        if difficulty == "hard":
            attack_timer = 15.0
        _launch_attack()

func _think_economy_and_production() -> void:
    if build_job.is_empty():
        var next_structure: String = _next_structure_choice()
        if not next_structure.is_empty():
            _begin_structure(next_structure)
        elif build_plan_step.begins_with("等待资金"):
            return
    _produce()

func _next_structure_choice() -> String:
    var desired: Array = [
        ["power", 1],
        ["barracks", 1],
        ["refinery", 1],
        ["war_factory", 1],
        ["power", 2],
        ["repair_bay", 1],
        ["turret", 1],
        ["bunker", 1],
    ]
    if difficulty == "hard":
        desired.append(["refinery", 2])
        desired.append(["turret", 2])
        desired.append(["bunker", 2])
    for item in desired:
        var building_id: String = str(item[0])
        var desired_count: int = int(item[1])
        if match_ref.count_buildings(owner_id, building_id) >= desired_count:
            continue
        var data: Dictionary = GameConfig.buildings.get(building_id, {})
        var requirement: String = str(data.get("requires", ""))
        if not requirement.is_empty() and not match_ref.has_building(owner_id, requirement):
            continue
        var display_name: String = _runtime_building_name(building_id)
        if match_ref.can_ai_construct(owner_id, building_id):
            build_plan_step = "准备建造：" + display_name
            return building_id
        build_plan_step = "等待资金：%s（$%d）" % [display_name, int(data.get("cost", 0))]
        return ""
    build_plan_step = "基地发展完成，扩充防线与部队"
    return ""

func _runtime_building_name(building_id: String) -> String:
    var faction_id: String = str(match_ref.get_player_data(owner_id).get("faction", "union"))
    var ra2_id: String = RA2RuntimeDatabase.resolve_entity_id("buildings", faction_id, building_id)
    return RA2RuntimeDatabase.display_name(ra2_id) if not ra2_id.is_empty() else str(GameConfig.buildings.get(building_id, {}).get("name", building_id))

func _runtime_unit_name(unit_id: String) -> String:
    var faction_id: String = str(match_ref.get_player_data(owner_id).get("faction", "union"))
    var ra2_id: String = RA2RuntimeDatabase.resolve_entity_id("units", faction_id, unit_id)
    return RA2RuntimeDatabase.display_name(ra2_id) if not ra2_id.is_empty() else str(GameConfig.units.get(unit_id, {}).get("name", unit_id))

func _begin_structure(building_id: String) -> bool:
    if not GameConfig.buildings.has(building_id):
        return false
    var data: Dictionary = GameConfig.buildings[building_id]
    var cost: int = int(data.get("cost", 0))
    if not match_ref.try_spend_credits(owner_id, cost):
        return false
    var multiplier: float = 1.18 if difficulty == "easy" else (0.82 if difficulty == "hard" else 1.0)
    build_job = {
        "id": building_id,
        "cost": cost,
        "remaining": maxf(1.0, float(data.get("build_time", 5.0)) * multiplier),
        "total": maxf(1.0, float(data.get("build_time", 5.0)) * multiplier),
    }
    return true

func _process_build_job(delta: float) -> void:
    if build_job.is_empty():
        return
    build_job["remaining"] = maxf(0.0, float(build_job.get("remaining", 0.0)) - delta)
    if float(build_job.get("remaining", 0.0)) > 0.0:
        return
    var building_id: String = str(build_job.get("id", ""))
    var building = match_ref.place_ai_structure(owner_id, building_id)
    if is_instance_valid(building):
        last_completed_structure = building_id
    else:
        match_ref.add_credits(owner_id, int(build_job.get("cost", 0)))
    build_job = {}

func _emergency_economy_support() -> void:
    # Normal income must come from harvesters. A small anti-deadlock grant is
    # only used when the AI has lost every economy unit and cannot rebuild one.
    var harvester_count: int = 0
    for unit in match_ref.units:
        if is_instance_valid(unit) and unit.owner_id == owner_id and unit.unit_id == "harvester" and not unit.dying:
            harvester_count += 1
    var harvester_cost: int = int(GameConfig.units.get("harvester", {}).get("cost", 1400))
    if harvester_count == 0 and match_ref.has_building(owner_id, "war_factory") and int(match_ref.credits.get(owner_id, 0)) < harvester_cost:
        match_ref.add_credits(owner_id, 220 if difficulty != "hard" else 320)

func _produce():
    var combat_count: int = 0
    var harvester_count: int = 0
    for unit in match_ref.units:
        if not is_instance_valid(unit) or unit.owner_id != owner_id:
            continue
        if unit.unit_id == "harvester":
            harvester_count += 1
        elif unit.is_combat_unit():
            combat_count += 1
    if harvester_count == 0 and match_ref.has_building(owner_id, "war_factory"):
        match_ref.request_ai_unit(owner_id, "harvester")
        return
    var choice: String = "rifle"
    if match_ref.has_building(owner_id, "war_factory") and combat_count >= 3:
        choice = "tank" if randf() > 0.35 else "scout"
    elif match_ref.has_building(owner_id, "barracks") and randf() > 0.72:
        choice = "rocket"
    match_ref.request_ai_unit(owner_id, choice)

func get_debug_snapshot() -> Dictionary:
    var unit_job: String = "无"
    var unit_progress: float = 0.0
    for building in match_ref.buildings:
        if not is_instance_valid(building) or building.owner_id != owner_id or building.destroyed or building.production_queue.is_empty():
            continue
        var front: Dictionary = building.production_queue[0]
        unit_job = _runtime_unit_name(str(front.get("id", "")))
        unit_progress = building.queue_progress()
        break
    var building_name: String = "无"
    var building_progress: float = 0.0
    if not build_job.is_empty():
        var building_id: String = str(build_job.get("id", ""))
        building_name = _runtime_building_name(building_id)
        building_progress = 1.0 - float(build_job.get("remaining", 0.0)) / maxf(0.01, float(build_job.get("total", 1.0)))
    return {
        "owner_id": owner_id,
        "credits": int(match_ref.credits.get(owner_id, 0)),
        "building": building_name,
        "building_progress": clampf(building_progress, 0.0, 1.0),
        "unit": unit_job,
        "unit_progress": clampf(unit_progress, 0.0, 1.0),
        "plan": build_plan_step,
        "army": _available_attackers().size(),
    }

func _army_center(units):
    var center = Vector2.ZERO
    var count = 0
    for unit in units:
        if is_instance_valid(unit):
            center += unit.global_position
            count += 1
    return center / float(count) if count > 0 else Vector2.ZERO

func _strategic_priority(building_id):
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
        if is_instance_valid(building) and match_ref.are_enemies(owner_id, building.owner_id) and building.building_id != "command":
            has_non_command = true
    for building in match_ref.buildings:
        if not is_instance_valid(building) or not match_ref.are_enemies(owner_id, building.owner_id):
            continue
        if has_non_command and building.building_id == "command":
            continue
        var score = center.distance_squared_to(building.global_position) + _strategic_priority(str(building.building_id))
        for defender in match_ref.query_units_in_radius(building.global_position, 260.0):
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
        # Armed harvesters can defend themselves, but they are economic units and
        # must never be consumed by the AI attack-wave or local-response planners.
        if str(unit.unit_id) == "harvester" or not bool(unit.stats.get("ai_attack_unit", true)):
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
    attackers.sort_custom(func(a, b): return a.global_position.distance_squared_to(objective.global_position) < b.global_position.distance_squared_to(objective.global_position))
    var reserve = 2 if attackers.size() >= 7 else 1
    var wave_count = max(minimum, attackers.size() - reserve)
    for index in range(min(wave_count, attackers.size())):
        attackers[index].command_attack_move(objective.global_position)
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

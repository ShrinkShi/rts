extends Node2D

signal exit_to_menu

const GridWorld = preload("res://scripts/game/grid_world.gd")
const UnitEntity = preload("res://scripts/game/unit.gd")
const BuildingEntity = preload("res://scripts/game/building.gd")
const OreEntity = preload("res://scripts/game/ore_entity.gd")
const TreeEntity = preload("res://scripts/game/tree_entity.gd")
const CombatEffect = preload("res://scripts/game/combat_effect.gd")
const FogOfWar = preload("res://scripts/game/fog_of_war.gd")
const WorldOverlay = preload("res://scripts/game/world_overlay.gd")
const Tracer = preload("res://scripts/game/tracer.gd")
const MatchHUD = preload("res://scripts/ui/match_hud.gd")
const AIController = preload("res://scripts/game/ai_controller.gd")
const UIFactory = preload("res://scripts/ui/ui_factory.gd")
const SettingsMenu = preload("res://scripts/ui/settings_menu.gd")
const FloatingText = preload("res://scripts/game/floating_text.gd")

var match_config = {}
var grid
var entity_layer
var effect_layer
var fog
var overlay
var camera
var hud
var units = []
var buildings = []
var ore_entities = []
var tree_entities = []
var harvester_unload_jobs = []
var primary_producers = {}
var ai_controllers = []
var credits = {}
var power_state = {}
var selected_entities = []
var control_groups = {}
var structure_jobs = {"primary": {}, "defense": {}}
var ready_structures = {"primary": "", "defense": ""}
var ready_structure_costs = {"primary": 0, "defense": 0}
var ready_structure_id = ""
var ready_structure_cost = 0
var repairing_buildings = []
var repair_credit_buffers = {}
var placement_mode = false
var selecting = false
var selection_start = Vector2.ZERO
var selection_end = Vector2.ZERO
var selection_start_screen = Vector2.ZERO
var selection_end_screen = Vector2.ZERO
var power_update_timer = 0.0
var victory_check_timer = 1.0
var campaign_stage = 0
var game_over = false
var pause_layer
var right_pan_candidate = false
var right_panning = false
var right_pan_hold = 0.0
var right_pan_anchor_screen = Vector2.ZERO
var right_pan_anchor_camera = Vector2.ZERO
var hover_entity
var hover_state = ""
var cursor_update_timer = 0.0
var fog_visibility_timer = 0.0
var command_mode = ""
var active_group_number = -1
var last_clicked_entity
var last_click_ms = 0
var selection_ctrl_pressed = false
var last_viewport_size = Vector2.ZERO

# Lightweight broad-phase cache. Unit steering previously scanned the complete
# unit array several times per moving unit and per physics frame, producing
# quadratic spikes that could freeze or terminate larger battles.
const UNIT_SPATIAL_CELL_SIZE = 96.0
const MAX_ACTIVE_TRACERS = 160
const MAX_ACTIVE_COMBAT_TEXTS = 96
var unit_spatial_hash = {}
var unit_spatial_frame = -1
var support_broadcast_until = {}
var active_tracer_count = 0
var active_combat_text_count = 0

func _ready():
    process_mode = Node.PROCESS_MODE_PAUSABLE
    _build_world()
    _spawn_players()
    _build_hud()
    get_viewport().size_changed.connect(_on_viewport_size_changed)
    call_deferred("_on_viewport_size_changed")
    _create_ai_controllers()
    _update_power()
    _initialize_objectives()
    SaveManager.settings_applied.connect(_on_settings_applied)
    EventBus.notification_requested.emit("左键选择，右键移动或攻击；空选时长按右键拖动画面", "info")

func _exit_tree():
    CursorManager.reset()
    VoiceManager.stop()

func _build_world():
    grid = GridWorld.new()
    add_child(grid)
    var map_data = GameConfig.maps.get(str(match_config.get("map_id", "twin_rivers")), GameConfig.maps["twin_rivers"])
    grid.generate(map_data)

    entity_layer = Node2D.new()
    entity_layer.name = "Entities"
    entity_layer.y_sort_enabled = true
    add_child(entity_layer)
    effect_layer = Node2D.new()
    effect_layer.name = "Effects"
    effect_layer.y_sort_enabled = true
    add_child(effect_layer)
    _spawn_ore_entities()
    _spawn_tree_entities()

    fog = FogOfWar.new()
    add_child(fog)
    fog.setup(self, grid, bool(match_config.get("fog_of_war", true)))

    overlay = WorldOverlay.new()
    add_child(overlay)
    overlay.setup(grid)

    camera = Camera2D.new()
    camera.name = "RTSCamera"
    camera.enabled = true
    camera.zoom = Vector2(0.9, 0.9)
    camera.position = grid.get_world_bounds().get_center()
    # The visible battlefield is smaller than the root viewport because HUD panels
    # occupy the top, right and bottom. Built-in Camera2D limits use the complete
    # viewport and therefore conflict with that asymmetric view. Manual clamping
    # below is the single source of truth.
    camera.limit_left = -10000000
    camera.limit_top = -10000000
    camera.limit_right = 10000000
    camera.limit_bottom = 10000000
    camera.position_smoothing_enabled = false
    add_child(camera)

func _spawn_ore_entities():
    ore_entities.clear()
    for cell in grid.get_ore_cells(true):
        var ore = OreEntity.new()
        entity_layer.add_child(ore)
        ore.setup(self, grid, cell)
        ore_entities.append(ore)

func get_nearest_ore_entity(from_position, requester = null):
    var best = null
    var best_score = INF
    for ore in ore_entities:
        if not is_instance_valid(ore) or ore.is_depleted():
            continue
        var route = grid.find_path_for_unit(from_position, ore.global_position, "vehicle")
        if route.is_empty() and from_position.distance_to(ore.global_position) > grid.tile_px * 0.8:
            continue
        var assigned_count = 0
        var occupied_penalty = 0.0
        for unit in units:
            if not is_instance_valid(unit) or unit == requester or unit.unit_id != "harvester" or unit.inside_refinery:
                continue
            if unit.harvest_target == ore and unit.harvester_state in ["to_ore", "harvest"]:
                assigned_count += 1
            var clearance = float(unit.stats.get("collision_radius", 20.0)) + 22.0
            var distance_to_cell = unit.global_position.distance_to(ore.global_position)
            if distance_to_cell < clearance:
                occupied_penalty += (clearance - distance_to_cell) * 12000.0
        var score = from_position.distance_squared_to(ore.global_position) + assigned_count * 900000.0 + occupied_penalty
        if score < best_score:
            best_score = score
            best = ore
    return best

func get_harvest_approach_position(ore, harvester = null):
    if not is_instance_valid(ore) or ore.is_depleted():
        return Vector2.ZERO
    # Ore cells are traversable ground. Driving onto the deposit removes the
    # artificial ring of approach cells that caused harvesters to deadlock around
    # dense ore fields. Target reservation keeps automatic harvesters distributed.
    return ore.global_position

func _spawn_tree_entities():
    for definition in grid.get_tree_cells():
        var tree = TreeEntity.new()
        entity_layer.add_child(tree)
        tree.setup(self, grid, definition.get("cell", Vector2i.ZERO), bool(definition.get("dense", false)))
        tree.died.connect(_on_tree_died)
        tree_entities.append(tree)

func _on_tree_died(tree):
    selected_entities.erase(tree)
    tree_entities.erase(tree)
    if hover_entity == tree:
        _set_hover_entity(null, "")
    if is_instance_valid(hud):
        hud.set_selection(selected_entities)

func _spawn_players():
    var player_list = match_config.get("players", [])
    var starting_credits = int(match_config.get("starting_credits", 10000))
    for player_id in range(player_list.size()):
        credits[player_id] = starting_credits
        power_state[player_id] = {"produced": 0, "consumed": 0}
        _spawn_starting_force(player_id)
    if str(match_config.get("mission_id", "")) == "training_02":
        call_deferred("_spawn_campaign_two_reinforcements")

func _spawn_starting_force(player_id):
    var player = get_player_data(player_id)
    var map_data = GameConfig.maps[str(match_config.get("map_id", "twin_rivers"))]
    var position_index = int(player.get("position", player_id))
    var positions = map_data.get("positions", [])
    position_index = clamp(position_index, 0, positions.size() - 1)
    var start_data = positions[position_index]
    var start = Vector2i(int(start_data[0]), int(start_data[1]))
    var horizontal = 1 if start.x < grid.map_width / 2 else -1
    var vertical = 1 if start.y < grid.map_height / 2 else -1

    var command = spawn_building(player_id, "command", start - Vector2i(1, 1))
    spawn_building(player_id, "power", start + Vector2i(4 * horizontal, -1))

    if str(match_config.get("kind", "skirmish")) == "campaign":
        if player_id == 0:
            spawn_building(player_id, "barracks", start + Vector2i(-1, 4 * vertical))
            for offset in [Vector2i(5 * horizontal, 3 * vertical), Vector2i(6 * horizontal, 4 * vertical), Vector2i(5 * horizontal, 5 * vertical)]:
                spawn_unit(player_id, "rifle", grid.cell_to_world(grid.nearest_walkable_cell(start + offset)))
            spawn_unit(player_id, "tank", grid.cell_to_world(grid.nearest_walkable_cell(start + Vector2i(7 * horizontal, 4 * vertical))))
        else:
            spawn_building(player_id, "barracks", start + Vector2i(-1, 4 * vertical))
            spawn_building(player_id, "turret", start + Vector2i(4 * horizontal, 3 * vertical))
            for offset in [Vector2i(5 * horizontal, 2 * vertical), Vector2i(6 * horizontal, 3 * vertical), Vector2i(5 * horizontal, 4 * vertical), Vector2i(6 * horizontal, 5 * vertical)]:
                spawn_unit(player_id, "rifle", grid.cell_to_world(grid.nearest_walkable_cell(start + offset)))
    else:
        var refinery = spawn_building(player_id, "refinery", start + Vector2i(-1, 4 * vertical))
        if player_id > 0:
            spawn_building(player_id, "barracks", start + Vector2i(5 * horizontal, 3 * vertical))
            spawn_building(player_id, "war_factory", start + Vector2i(5 * horizontal, -4 * vertical))
            spawn_building(player_id, "turret", start + Vector2i(2 * horizontal, 5 * vertical))
        for offset in [Vector2i(5 * horizontal, 2 * vertical), Vector2i(6 * horizontal, 3 * vertical)]:
            spawn_unit(player_id, "rifle", grid.cell_to_world(grid.nearest_walkable_cell(start + offset)))
        if player_id > 0:
            spawn_unit(player_id, "tank", grid.cell_to_world(grid.nearest_walkable_cell(start + Vector2i(7 * horizontal, -2 * vertical))))

    if player_id == 0 and is_instance_valid(command):
        camera.position = command.global_position

func _spawn_campaign_two_reinforcements():
    var enemy_command = get_nearest_building(1, "command", Vector2.ZERO)
    if not is_instance_valid(enemy_command): return
    var offsets = [Vector2(-140,-90),Vector2(-90,-130),Vector2(-40,-100),Vector2(80,-110),Vector2(140,-60),Vector2(-150,40),Vector2(120,70),Vector2(40,120)]
    var ids = ["rifle","rifle","rocket","tank","scout","rifle","tank","rocket"]
    for i in range(offsets.size()):
        spawn_unit(1, ids[i], enemy_command.global_position + offsets[i])
    EventBus.notification_requested.emit("敌军在扩大战区部署了额外守备力量", "warning")

func _build_hud():
    hud = MatchHUD.new()
    add_child(hud)
    hud.setup(self, grid)
    hud.structure_requested.connect(request_structure)
    hud.unit_requested.connect(func(unit_id): request_unit(0, unit_id))
    hud.pause_requested.connect(_toggle_pause)
    hud.minimap_world_requested.connect(_move_camera_from_minimap)
    hud.minimap_command_requested.connect(_command_from_minimap)
    hud.command_requested.connect(execute_command_from_hud)
    hud.behavior_settings_requested.connect(_apply_selected_behavior_settings)
    _clamp_camera(true)

func _move_camera_from_minimap(world_position):
    camera.position = world_position
    _clamp_camera(true)

func _command_from_minimap(world_position):
    if selected_entities.is_empty():
        _move_camera_from_minimap(world_position)
        return
    var queued = Input.is_key_pressed(KEY_SHIFT)
    # The minimap is a ground-command surface. A normal right click moves the
    # selection; attack-move/patrol/rally keep their explicit command modes.
    # This avoids an ore or hidden entity under the minimap coordinate stealing
    # a movement command through contextual target detection.
    if command_mode in ["attack_move", "patrol", "harvest", "rally", "building_attack", "force_attack"]:
        _issue_targeted_command(world_position, queued)
    else:
        _issue_move_command(world_position, queued)
        if command_mode == "move" and not Input.is_key_pressed(KEY_SHIFT):
            _set_command_mode("")

func _create_ai_controllers():
    var player_list = match_config.get("players", [])
    for player_id in range(1, player_list.size()):
        var controller_type = str(player_list[player_id].get("controller", "ai"))
        if controller_type == "ai":
            var ai = AIController.new()
            add_child(ai)
            ai.setup(self, player_id, str(player_list[player_id].get("difficulty", "normal")))
            ai_controllers.append(ai)

func _initialize_objectives():
    if str(match_config.get("kind", "skirmish")) == "campaign":
        campaign_stage = 0
        if str(match_config.get("mission_id", "")) == "training_02":
            overlay.training_line_x = -1.0
            EventBus.objective_changed.emit("边境反击：摧毁敌军司令部", "在更大的战区建立经济和部队，击退敌军守备并摧毁其建造中心。")
        else:
            overlay.training_line_x = grid.map_width * grid.tile_px * 0.42
            EventBus.objective_changed.emit("训练 1/3：选择部队", "拖动鼠标框选或单击选择至少一个己方单位。")
    else:
        var mode = GameConfig.modes.get(str(match_config.get("mode_id", "standard")), {})
        EventBus.objective_changed.emit(str(mode.get("name", "标准歼灭")), str(mode.get("description", "摧毁敌军。")))

func _unit_spatial_key(world_position):
    return Vector2i(
        int(floor(float(world_position.x) / UNIT_SPATIAL_CELL_SIZE)),
        int(floor(float(world_position.y) / UNIT_SPATIAL_CELL_SIZE))
    )

func _invalidate_unit_spatial_hash():
    unit_spatial_frame = -1

func _ensure_unit_spatial_hash():
    var physics_frame = int(Engine.get_physics_frames())
    if unit_spatial_frame == physics_frame:
        return
    unit_spatial_frame = physics_frame
    unit_spatial_hash.clear()
    var live_units = []
    for unit in units:
        if not is_instance_valid(unit):
            continue
        live_units.append(unit)
        if bool(unit.dying) or bool(unit.inside_refinery) or bool(unit.inside_repair_bay):
            continue
        var key = _unit_spatial_key(unit.global_position)
        if not unit_spatial_hash.has(key):
            unit_spatial_hash[key] = []
        unit_spatial_hash[key].append(unit)
    if live_units.size() != units.size():
        units = live_units

func query_units_in_radius(world_position, radius, excluded = null):
    _ensure_unit_spatial_hash()
    var result = []
    var query_radius = max(1.0, float(radius))
    var min_key = _unit_spatial_key(Vector2(world_position) - Vector2.ONE * query_radius)
    var max_key = _unit_spatial_key(Vector2(world_position) + Vector2.ONE * query_radius)
    var radius_squared = query_radius * query_radius
    for cell_x in range(min_key.x, max_key.x + 1):
        for cell_y in range(min_key.y, max_key.y + 1):
            var key = Vector2i(cell_x, cell_y)
            for unit in unit_spatial_hash.get(key, []):
                if not is_instance_valid(unit) or unit == excluded:
                    continue
                if Vector2(world_position).distance_squared_to(unit.global_position) <= radius_squared:
                    result.append(unit)
    return result

func _on_tracer_exited():
    active_tracer_count = max(0, active_tracer_count - 1)

func _on_combat_text_exited():
    active_combat_text_count = max(0, active_combat_text_count - 1)

func _process(delta):
    if game_over:
        return
    var real_delta = delta / max(0.01, Engine.time_scale)
    _process_right_pan(real_delta)
    _process_camera(real_delta)
    _process_structure_queue(delta)
    _process_harvester_unloads(delta)
    _process_building_repairs(delta)
    _process_campaign_objectives()
    power_update_timer -= delta
    if power_update_timer <= 0.0:
        power_update_timer = 0.45
        _update_power()
    victory_check_timer -= delta
    if victory_check_timer <= 0.0:
        victory_check_timer = 1.0
        _check_victory()
    if placement_mode:
        _update_placement_preview()
    cursor_update_timer -= real_delta
    if cursor_update_timer <= 0.0:
        cursor_update_timer = 0.04
        _update_cursor_and_hover()
    fog_visibility_timer -= real_delta
    if fog_visibility_timer <= 0.0:
        fog_visibility_timer = 0.12
        _update_enemy_visibility()

func _update_enemy_visibility():
    if not is_instance_valid(fog) or not fog.enabled:
        for unit in units:
            if is_instance_valid(unit):
                unit.visible = not unit.inside_refinery
        for entity in buildings + ore_entities + tree_entities:
            if is_instance_valid(entity):
                entity.visible = true
        return
    for unit in units:
        if is_instance_valid(unit):
            unit.visible = not unit.inside_refinery and (unit.owner_id == 0 or fog.is_world_visible(unit.global_position))
    for building in buildings:
        if is_instance_valid(building):
            building.visible = building.owner_id == 0 or fog.is_world_visible(building.global_position)
    for ore in ore_entities:
        if is_instance_valid(ore):
            ore.visible = fog.get_cell_state(ore.cell) > 0
    for tree in tree_entities:
        if is_instance_valid(tree):
            tree.visible = fog.get_cell_state(tree.cell) > 0

func _process_camera(delta):
    # WASD is reserved for production pages and unit commands. Camera movement
    # remains available through arrow keys, edge scrolling, minimap dragging and
    # anchored right-mouse panning.
    var keyboard_direction = Vector2.ZERO
    if Input.is_key_pressed(KEY_UP):
        keyboard_direction.y -= 1
    if Input.is_key_pressed(KEY_DOWN):
        keyboard_direction.y += 1
    if Input.is_key_pressed(KEY_LEFT):
        keyboard_direction.x -= 1
    if Input.is_key_pressed(KEY_RIGHT):
        keyboard_direction.x += 1

    var edge_direction = Vector2.ZERO
    if bool(SaveManager.settings.get("edge_scroll", true)) and not right_panning:
        var mouse = get_viewport().get_mouse_position()
        var viewport_size = get_viewport_rect().size
        var edge = 10.0
        if mouse.x <= edge:
            edge_direction.x -= 1
        elif mouse.x >= viewport_size.x - edge:
            edge_direction.x += 1
        if mouse.y <= edge:
            edge_direction.y -= 1
        elif mouse.y >= viewport_size.y - edge:
            edge_direction.y += 1

    var speed = float(SaveManager.settings.get("scroll_speed", 650.0)) / camera.zoom.x
    if keyboard_direction.length_squared() > 0:
        camera.position += keyboard_direction.normalized() * speed * delta
    if edge_direction.length_squared() > 0:
        var mouse_speed = float(SaveManager.settings.get("mouse_speed", 1.0))
        camera.position += edge_direction.normalized() * speed * mouse_speed * delta
    if keyboard_direction.length_squared() > 0 or edge_direction.length_squared() > 0:
        _clamp_camera()

func _process_right_pan(delta):
    if not right_pan_candidate:
        return
    if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
        _finish_right_pan()
        return
    if not right_panning:
        right_pan_hold += delta
        if right_pan_hold >= 0.16:
            right_panning = true
            CursorManager.set_state("pan")
    if right_panning:
        _apply_right_pan(get_viewport().get_mouse_position())

func _begin_right_pan(screen_position):
    right_pan_candidate = true
    right_panning = false
    right_pan_hold = 0.0
    right_pan_anchor_screen = screen_position
    right_pan_anchor_camera = camera.position

func _apply_right_pan(screen_position):
    var mouse_speed = float(SaveManager.settings.get("mouse_speed", 1.0))
    var displacement = (screen_position - right_pan_anchor_screen) / camera.zoom.x * mouse_speed
    camera.position = right_pan_anchor_camera - displacement
    _clamp_camera()

func _finish_right_pan():
    right_pan_candidate = false
    right_panning = false
    right_pan_hold = 0.0
    CursorManager.set_state("default")

func _on_viewport_size_changed():
    var viewport_size = get_viewport_rect().size
    if viewport_size == last_viewport_size and last_viewport_size != Vector2.ZERO:
        return
    last_viewport_size = viewport_size
    _clamp_camera(true)

func get_world_viewport_size():
    var viewport_size = get_viewport_rect().size
    var sidebar_width = float(hud.get_sidebar_width()) if is_instance_valid(hud) else 282.0
    var bottom_height = float(hud.get_bottom_height()) if is_instance_valid(hud) else 224.0
    var navigation_height = float(hud.get_navigation_height()) if is_instance_valid(hud) else 38.0
    return Vector2(max(1.0, viewport_size.x - sidebar_width), max(1.0, viewport_size.y - bottom_height - navigation_height))

func _update_camera_view_offset():
    if not is_instance_valid(camera): return
    var sidebar_width = float(hud.get_sidebar_width()) if is_instance_valid(hud) else 282.0
    var bottom_height = float(hud.get_bottom_height()) if is_instance_valid(hud) else 224.0
    var navigation_height = float(hud.get_navigation_height()) if is_instance_valid(hud) else 38.0
    # Camera2D normally centers the world in the whole window. Shift its projection
    # into the actual battlefield rectangle so no world is rendered behind the sidebar.
    camera.offset = Vector2(-sidebar_width * 0.5, (navigation_height - bottom_height) * 0.5)

func _battle_screen_rect():
    var viewport_size = get_viewport_rect().size
    var sidebar_width = float(hud.get_sidebar_width()) if is_instance_valid(hud) else 282.0
    var bottom_height = float(hud.get_bottom_height()) if is_instance_valid(hud) else 224.0
    var navigation_height = float(hud.get_navigation_height()) if is_instance_valid(hud) else 38.0
    return Rect2(
        Vector2(0.0, navigation_height),
        Vector2(
            max(1.0, viewport_size.x - sidebar_width),
            max(1.0, viewport_size.y - navigation_height - bottom_height)
        )
    )

func _visible_battle_world_rect():
    if not is_instance_valid(camera):
        return Rect2()
    camera.force_update_scroll()
    var screen_rect = _battle_screen_rect()
    var world_start = _screen_to_world(screen_rect.position)
    var world_end = _screen_to_world(screen_rect.end)
    return Rect2(world_start, world_end - world_start).abs()

func _clamp_camera(snap = false):
    if not is_instance_valid(camera) or not is_instance_valid(grid):
        return
    _update_camera_view_offset()
    if snap and camera.has_method("reset_smoothing"):
        camera.reset_smoothing()
    camera.force_update_scroll()

    # Clamp the *actual battlefield screen rectangle*, not Camera2D.position.
    # Camera2D.offset moves the projection into the HUD-free area, so assuming
    # camera.position is the visible battlefield center produces the exact
    # top/left empty margin and right/bottom clipping seen at map boundaries.
    var visible_rect = _visible_battle_world_rect()
    var map_rect = grid.get_world_bounds()
    var correction = Vector2.ZERO

    if map_rect.size.x <= visible_rect.size.x:
        correction.x = map_rect.get_center().x - visible_rect.get_center().x
    elif visible_rect.position.x < map_rect.position.x:
        correction.x = map_rect.position.x - visible_rect.position.x
    elif visible_rect.end.x > map_rect.end.x:
        correction.x = map_rect.end.x - visible_rect.end.x

    if map_rect.size.y <= visible_rect.size.y:
        correction.y = map_rect.get_center().y - visible_rect.get_center().y
    elif visible_rect.position.y < map_rect.position.y:
        correction.y = map_rect.position.y - visible_rect.position.y
    elif visible_rect.end.y > map_rect.end.y:
        correction.y = map_rect.end.y - visible_rect.end.y

    if correction.length_squared() > 0.0001:
        camera.position += correction
        camera.force_update_scroll()
    if snap and camera.has_method("reset_smoothing"):
        camera.reset_smoothing()
        camera.force_update_scroll()

func get_world_battle_rect():
    return _visible_battle_world_rect()

func is_world_position_in_battle_view(world_position, margin = 12.0):
    return _visible_battle_world_rect().grow(float(margin)).has_point(Vector2(world_position))

func _input(event):
    if game_over:
        return
    if selecting:
        if event is InputEventMouseMotion:
            _update_selection_drag(event.position)
            get_viewport().set_input_as_handled()
            return
        if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
            _finish_selection(event.position)
            get_viewport().set_input_as_handled()
            return
    if right_pan_candidate:
        if event is InputEventMouseMotion:
            if right_panning:
                _apply_right_pan(event.position)
            get_viewport().set_input_as_handled()
            return
        if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
            _finish_right_pan()
            get_viewport().set_input_as_handled()

func _unhandled_input(event):
    if game_over:
        return
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
            _zoom_camera(1.12)
            get_viewport().set_input_as_handled()
            return
        if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
            _zoom_camera(0.89)
            get_viewport().set_input_as_handled()
            return
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                if placement_mode:
                    _attempt_place_structure_at(_screen_to_world(event.position))
                elif command_mode != "":
                    _issue_targeted_command(_screen_to_world(event.position), Input.is_key_pressed(KEY_SHIFT))
                else:
                    _begin_selection(event.position, event.ctrl_pressed)
            elif selecting:
                _finish_selection(event.position)
            get_viewport().set_input_as_handled()
            return
        if event.button_index == MOUSE_BUTTON_RIGHT:
            if event.pressed:
                if command_mode != "":
                    _set_command_mode("")
                elif placement_mode:
                    placement_mode = false
                    overlay.set_placement(false)
                    EventBus.notification_requested.emit("已取消部署，已完成的建筑仍保留在侧栏", "info")
                    VoiceManager.speak_adjutant("cancel")
                elif selected_entities.is_empty():
                    _begin_right_pan(event.position)
                else:
                    _issue_context_command(_screen_to_world(event.position), Input.is_key_pressed(KEY_SHIFT))
            elif right_pan_candidate:
                _finish_right_pan()
            get_viewport().set_input_as_handled()
            return
    elif event is InputEventMouseMotion and selecting:
        _update_selection_drag(event.position)
    elif event is InputEventKey and event.pressed and not event.echo:
        _handle_hotkey(event)

func _screen_to_world(screen_position):
    # Godot 4.7 CanvasItem conversion includes Camera2D zoom and translation.
    # Using the event's own position avoids a one-frame mismatch with the
    # viewport's current mouse position during rapid drags.
    return make_canvas_position_local(screen_position)

func _current_world_mouse_position():
    return _screen_to_world(get_viewport().get_mouse_position())

func _begin_selection(screen_position, ctrl_pressed = false):
    selecting = true
    selection_ctrl_pressed = bool(ctrl_pressed)
    selection_start_screen = screen_position
    selection_end_screen = screen_position
    selection_start = _screen_to_world(screen_position)
    selection_end = selection_start
    overlay.set_selection(true, selection_start, selection_end)

func _update_selection_drag(screen_position):
    if not selecting:
        return
    selection_end_screen = screen_position
    selection_end = _screen_to_world(screen_position)
    overlay.set_selection(true, selection_start, selection_end)

func _finish_selection(screen_position):
    if not selecting:
        return
    _update_selection_drag(screen_position)
    selecting = false
    overlay.set_selection(false, selection_start, selection_end)
    _complete_selection(Input.is_key_pressed(KEY_SHIFT), selection_ctrl_pressed)
    selection_ctrl_pressed = false

func _handle_hotkey(event):
    if event.keycode == KEY_ESCAPE:
        if is_instance_valid(hud) and hud.is_behavior_panel_open():
            hud.close_behavior_panel()
        elif command_mode != "":
            _set_command_mode("")
        elif placement_mode:
            placement_mode = false
            overlay.set_placement(false)
        else:
            _toggle_pause()
        return
    var production_hotkeys = {
        KEY_Q: "primary",
        KEY_W: "defense",
        KEY_E: "infantry",
        KEY_R: "vehicle",
        KEY_T: "air",
        KEY_Y: "naval"
    }
    if production_hotkeys.has(event.keycode):
        _activate_production_category_hotkey(str(production_hotkeys[event.keycode]))
        return
    if event.keycode == KEY_F2:
        _select_all_combat_units()
        return
    if event.keycode == KEY_A and event.ctrl_pressed and (_selection_has_combat_unit() or _selection_has_defense_building()):
        _set_command_mode("force_attack")
        return
    if event.keycode == KEY_A:
        if _selection_has_defense_building() and not _selection_has_combat_unit():
            _set_command_mode("building_attack")
        elif _selection_has_combat_unit():
            _set_command_mode("attack_move")
        return
    if event.keycode == KEY_S and (_selection_has_movable_unit() or _selection_has_defense_building()):
        _issue_immediate_selection_command("stop")
        return
    if event.keycode == KEY_H and _selection_has_movable_unit():
        _issue_immediate_unit_command("hold")
        return
    if event.keycode == KEY_P:
        if command_mode == "patrol":
            _set_command_mode("")
        elif _selection_has_movable_unit():
            _set_command_mode("patrol")
        return
    if event.keycode == KEY_M and _selection_has_movable_unit():
        _set_command_mode("" if command_mode == "move" else "move")
        return
    if event.keycode == KEY_Z and not _selected_production_buildings().is_empty():
        _set_selected_producers_primary()
        return
    if event.keycode == KEY_C and not _selected_harvesters().is_empty():
        _set_command_mode("harvest")
        return
    if event.keycode == KEY_G and _selection_has_movable_unit():
        _open_selected_behavior_panel()
        return
    if event.keycode == KEY_HOME:
        var command = get_nearest_building(0, "command", camera.position)
        if is_instance_valid(command):
            _set_selection([command], false)
            camera.position = command.global_position
            _clamp_camera()
        return
    var group_number = _key_to_group(event.keycode)
    if group_number >= 0:
        _handle_control_group_key(group_number, event.ctrl_pressed, event.shift_pressed)

func _activate_production_category_hotkey(category_id):
    if is_instance_valid(hud):
        hud.activate_production_category(category_id)
    if placement_mode:
        return
    var ready_id = str(ready_structures.get(category_id, ""))
    if ready_id != "":
        request_structure(ready_id)

func _key_to_group(keycode):
    var mapping = {
        KEY_1: 1,
        KEY_2: 2,
        KEY_3: 3,
        KEY_4: 4,
        KEY_5: 5,
        KEY_6: 6,
        KEY_7: 7,
        KEY_8: 8,
        KEY_9: 9,
        KEY_0: 0
    }
    return int(mapping.get(keycode, -1))

func _zoom_camera(multiplier):
    var next_zoom = clamp(camera.zoom.x * multiplier, 0.55, 1.55)
    camera.zoom = Vector2(next_zoom, next_zoom)
    _clamp_camera()

func _complete_selection(additive, ctrl_pressed = false):
    var rect = Rect2(selection_start, selection_end - selection_start).abs()
    var next_selection = selected_entities.duplicate() if additive else []
    # Click-vs-drag is measured in physical screen pixels so zoom does not alter it.
    if selection_start_screen.distance_to(selection_end_screen) < 7.0:
        var entity = get_entity_at(selection_end, true)
        var now = Time.get_ticks_msec()
        var double_clicked = is_instance_valid(entity) and entity == last_clicked_entity and now - last_click_ms <= 420
        var repeated_selected = is_instance_valid(entity) and entity in selected_entities and selected_entities.size() == 1
        last_clicked_entity = entity
        last_click_ms = now
        if is_instance_valid(entity) and (entity.owner_id == 0 or (entity.has_method("is_resource_entity") and entity.is_resource_entity()) or (entity.has_method("is_tree_entity") and entity.is_tree_entity())):
            if (entity.has_method("is_resource_entity") and entity.is_resource_entity()) or (entity.has_method("is_tree_entity") and entity.is_tree_entity()):
                next_selection = [entity]
            elif ctrl_pressed and entity.owner_id == 0:
                next_selection = _same_type_entities(entity, true)
            elif double_clicked and entity.owner_id == 0:
                next_selection = _same_type_entities(entity, false)
            elif additive and entity in next_selection:
                next_selection.erase(entity)
            elif not entity in next_selection:
                next_selection.append(entity)
            if (double_clicked or repeated_selected) and entity.has_method("is_production_building") and entity.is_production_building():
                set_primary_producer(entity)
    else:
        var boxed_units = []
        var boxed_combat = []
        for unit in units:
            if not is_instance_valid(unit) or unit.owner_id != 0 or unit.inside_refinery:
                continue
            if not rect.intersects(unit.get_selection_rect()):
                continue
            boxed_units.append(unit)
            if unit.is_combat_unit():
                boxed_combat.append(unit)
        var accepted_units = boxed_combat if not boxed_combat.is_empty() else boxed_units
        for unit in accepted_units:
            if not unit in next_selection:
                next_selection.append(unit)
        if accepted_units.is_empty() and next_selection.is_empty():
            for building in buildings:
                if is_instance_valid(building) and building.owner_id == 0 and rect.intersects(building.get_selection_rect()):
                    next_selection.append(building)
    _set_selection(next_selection, false)

func _same_type_entities(reference, on_screen_only):
    var result = []
    if not is_instance_valid(reference) or reference.owner_id != 0:
        return result
    var battle_rect = get_world_battle_rect()
    if reference.has_method("is_movable_unit"):
        for unit in units:
            if not is_instance_valid(unit) or unit.owner_id != 0 or unit.inside_refinery:
                continue
            if str(unit.unit_id) != str(reference.unit_id):
                continue
            if on_screen_only and not battle_rect.has_point(unit.global_position):
                continue
            result.append(unit)
    elif reference.has_method("is_production_building"):
        for building in buildings:
            if not is_instance_valid(building) or building.owner_id != 0:
                continue
            if str(building.building_id) != str(reference.building_id):
                continue
            if on_screen_only and not battle_rect.has_point(building.global_position):
                continue
            result.append(building)
    return result

func _set_selection(next_selection, _additive):
    for entity in selected_entities:
        if is_instance_valid(entity):
            entity.set_selected(false)
    selected_entities = []
    for entity in next_selection:
        if not is_instance_valid(entity):
            continue
        if entity.has_method("is_movable_unit") and bool(entity.inside_refinery):
            continue
        entity.set_selected(true)
        selected_entities.append(entity)
    if is_instance_valid(hud):
        hud.set_selection(selected_entities)
    if is_instance_valid(overlay):
        overlay.set_selected_entities(selected_entities)
    for entity in selected_entities:
        if is_instance_valid(entity) and entity.has_method("command_move"):
            VoiceManager.speak(entity.unit_id, "select")
            break
    EventBus.selection_changed.emit(selected_entities)

func _remove_entity_from_selection(entity):
    if not entity in selected_entities:
        return
    if is_instance_valid(entity):
        entity.set_selected(false)
    selected_entities.erase(entity)
    if is_instance_valid(hud):
        hud.set_selection(selected_entities)
    if is_instance_valid(overlay):
        overlay.set_selected_entities(selected_entities)
    EventBus.selection_changed.emit(selected_entities)

func _formation_targets(movable, target_position):
    var targets = []
    if movable.is_empty():
        return targets
    var max_radius = 12.0
    for unit in movable:
        max_radius = max(max_radius, float(unit.stats.get("collision_radius", unit.stats.get("radius", 12.0))))
    # The old hard-coded 34 px spacing was smaller than two tank collision radii,
    # so a formation could be ordered into a guaranteed overlap. Spacing now
    # derives from the largest selected footprint and is centered on the click.
    var spacing = max(34.0, max_radius * 2.0 + 10.0)
    var columns = max(1, int(ceil(sqrt(float(movable.size())))))
    var rows = int(ceil(float(movable.size()) / float(columns)))
    for index in range(movable.size()):
        var row = int(index / columns)
        var column = index % columns
        var row_count = min(columns, movable.size() - row * columns)
        var offset_x = (float(column) - (float(row_count) - 1.0) * 0.5) * spacing
        var offset_y = (float(row) - (float(rows) - 1.0) * 0.5) * spacing
        var desired = Vector2(target_position) + Vector2(offset_x, offset_y)
        var category = str(movable[index].stats.get("category", "vehicle"))
        var cell = grid.nearest_walkable_cell(grid.world_to_cell(desired), category)
        targets.append(grid.cell_to_world(cell) if cell.x >= 0 else desired)
    return targets

func _issue_move_command(target_position, queued = false):
    var production_buildings = _selected_production_buildings()
    for building in production_buildings:
        building.set_rally_point(target_position)
    if not production_buildings.is_empty():
        overlay.add_command_marker(target_position, Color("#69D889"), "集")
        EventBus.notification_requested.emit("已设置集结点", "info")

    var movable = _selected_movable_units()
    var targets = _formation_targets(movable, target_position)
    for index in range(movable.size()):
        movable[index].command_move(targets[index], true, queued)
    if not movable.is_empty():
        overlay.add_command_marker(target_position, Color("#69D889"), _queued_marker_label(movable, queued))
        VoiceManager.speak(movable[0].unit_id, "move")

func _issue_context_command(target_position, queued = false):
    if selected_entities.is_empty():
        return
    var target_entity = get_entity_at(target_position, true)
    if is_instance_valid(target_entity) and target_entity.owner_id == 0 and target_entity.has_method("is_repair_facility") and target_entity.is_repair_facility():
        var repairables = []
        for unit in _selected_movable_units():
            if str(unit.stats.get("category", "")) == "vehicle" and unit.hp < unit.max_hp:
                unit.command_repair(target_entity, queued)
                repairables.append(unit)
        if not repairables.is_empty():
            overlay.add_command_marker(target_entity.global_position, Color("#69D889"), "修")
            return
    if is_instance_valid(target_entity) and target_entity.has_method("is_resource_entity") and target_entity.is_resource_entity():
        if target_entity.is_depleted():
            EventBus.notification_requested.emit("该矿石格已枯竭", "warning")
            return
        var harvesters = _selected_harvesters()
        for harvester in harvesters:
            harvester.command_harvest(target_entity, queued)
        if not harvesters.is_empty():
            overlay.add_command_marker(target_entity.global_position, Color("#E4C44E"), _queued_marker_label(harvesters, queued))
            VoiceManager.speak("harvester", "move")
        return

    if is_instance_valid(target_entity) and target_entity.owner_id >= 0 and are_enemies(0, target_entity.owner_id) and fog.is_world_visible(target_entity.global_position):
        var attackers = []
        var speaking_unit
        for entity in selected_entities:
            if not is_instance_valid(entity) or not entity.has_method("command_attack"):
                continue
            var can_attack = false
            if entity.has_method("is_combat_unit"):
                can_attack = entity.is_combat_unit()
            elif entity.has_method("is_defense_building"):
                can_attack = entity.is_defense_building()
            if not can_attack:
                continue
            if entity.has_method("is_combat_unit"):
                entity.command_attack(target_entity, queued)
            else:
                entity.command_attack(target_entity)
            attackers.append(entity)
            if entity.has_method("is_combat_unit") and speaking_unit == null:
                speaking_unit = entity
        overlay.add_command_marker(target_position, Color("#F06E67"), _queued_marker_label(attackers, queued))
        if is_instance_valid(speaking_unit):
            VoiceManager.speak(speaking_unit.unit_id, "attack")
        return

    _issue_move_command(target_position, queued)

func get_entity_at(world_position, include_friendly):
    var candidates = []
    for unit in units:
        if is_instance_valid(unit) and not unit.inside_refinery and unit.get_selection_rect().grow(4.0 / camera.zoom.x).has_point(world_position):
            if include_friendly or unit.owner_id != 0:
                candidates.append(unit)
    for building in buildings:
        if is_instance_valid(building) and building.get_selection_rect().grow(4.0 / camera.zoom.x).has_point(world_position):
            if include_friendly or building.owner_id != 0:
                candidates.append(building)
    if include_friendly:
        for ore in ore_entities:
            if is_instance_valid(ore) and ore.visible and ore.get_selection_rect().has_point(world_position):
                candidates.append(ore)
        for tree in tree_entities:
            if is_instance_valid(tree) and tree.visible and tree.get_selection_rect().has_point(world_position):
                candidates.append(tree)
    if candidates.is_empty():
        return null
    candidates.sort_custom(func(a, b): return a.global_position.distance_to(world_position) < b.global_position.distance_to(world_position))
    return candidates[0]

func _update_cursor_and_hover():
    if right_panning:
        _set_hover_entity(null, "")
        CursorManager.set_state("pan")
        return
    var mouse = get_viewport().get_mouse_position()
    if _mouse_over_hud(mouse):
        _set_hover_entity(null, "")
        CursorManager.set_state("default")
        return
    var world = _screen_to_world(mouse)
    if placement_mode and ready_structure_id != "":
        var data = GameConfig.buildings[ready_structure_id]
        var footprint = Vector2i(int(data.footprint[0]), int(data.footprint[1]))
        var cell = grid.world_to_cell(world)
        var valid = _can_place_structure_without_units(cell, footprint) and _is_in_build_radius(cell, 0)
        _set_hover_entity(null, "")
        CursorManager.set_state("build_valid" if valid else "build_invalid")
        return
    if command_mode == "repair_building":
        var repair_target = get_entity_at(world, true)
        var valid_repair = is_instance_valid(repair_target) and repair_target.owner_id == 0 and repair_target.has_method("is_defense_building") and repair_target.hp < repair_target.max_hp
        _set_hover_entity(repair_target if valid_repair else null, "selected" if valid_repair else "")
        CursorManager.set_state("select" if valid_repair else "default")
        return
    if command_mode == "sell_building":
        var sell_target = get_entity_at(world, true)
        var valid_sell = is_instance_valid(sell_target) and sell_target.owner_id == 0 and sell_target.has_method("is_defense_building")
        _set_hover_entity(sell_target if valid_sell else null, "selected" if valid_sell else "")
        CursorManager.set_state("select" if valid_sell else "default")
        return
    if command_mode == "force_attack":
        var forced = get_entity_at(world, true)
        _set_hover_entity(forced if is_instance_valid(forced) else null, "attack" if is_instance_valid(forced) else "")
        CursorManager.set_state("attack")
        return
    if command_mode == "building_attack":
        var defense_target = get_entity_at(world, true)
        var valid_defense_target = is_instance_valid(defense_target) and not (defense_target.has_method("is_resource_entity") and defense_target.is_resource_entity()) and are_enemies(0, defense_target.owner_id)
        _set_hover_entity(defense_target if valid_defense_target else null, "attack" if valid_defense_target else "")
        CursorManager.set_state("attack")
        return
    if command_mode == "attack_move":
        var attack_entity = get_entity_at(world, true)
        var valid_attack = is_instance_valid(attack_entity) and not (attack_entity.has_method("is_resource_entity") and attack_entity.is_resource_entity()) and attack_entity.owner_id != 0
        _set_hover_entity(attack_entity if valid_attack else null, "attack" if valid_attack else "")
        CursorManager.set_state("attack")
        return
    if command_mode == "harvest":
        var resource = get_entity_at(world, true)
        var valid_resource = is_instance_valid(resource) and resource.has_method("is_resource_entity") and resource.is_resource_entity() and not resource.is_depleted()
        _set_hover_entity(resource if valid_resource else null, "resource" if valid_resource else "")
        CursorManager.set_state("select" if valid_resource else "move")
        return
    if command_mode == "patrol" or command_mode == "rally" or command_mode == "move":
        _set_hover_entity(null, "")
        CursorManager.set_state("move")
        return
    var entity = get_entity_at(world, true)
    if is_instance_valid(entity):
        if entity.has_method("is_resource_entity") and entity.is_resource_entity():
            _set_hover_entity(entity, "selected" if entity.selected else "resource")
            CursorManager.set_state("selected" if entity.selected else "select")
            return
        if entity.owner_id == 0:
            if entity.selected and entity.has_method("is_production_building") and entity.is_production_building():
                _set_hover_entity(entity, "primary")
                CursorManager.set_state("primary")
                return
            var state = "selected" if entity.selected else "friendly"
            _set_hover_entity(entity, state)
            CursorManager.set_state("selected" if entity.selected else "select")
            return
        if fog.is_world_visible(entity.global_position):
            if _selection_has_combat_unit() or _selection_has_defense_building():
                _set_hover_entity(entity, "attack")
                CursorManager.set_state("attack")
            else:
                _set_hover_entity(entity, "enemy")
                CursorManager.set_state("enemy")
            return
    _set_hover_entity(null, "")
    CursorManager.set_state("move" if _selection_has_movable_unit() else "default")

func _mouse_over_hud(position):
    var viewport_size = get_viewport_rect().size
    var sidebar_width = float(hud.get_sidebar_width()) if is_instance_valid(hud) else 282.0
    var bottom_height = float(hud.get_bottom_height()) if is_instance_valid(hud) else 224.0
    var navigation_height = float(hud.get_navigation_height()) if is_instance_valid(hud) else 38.0
    if position.y <= navigation_height:
        return true
    if position.y >= viewport_size.y - bottom_height:
        return true
    if position.x >= viewport_size.x - sidebar_width:
        return true
    return false

func _set_hover_entity(entity, state):
    if is_instance_valid(hover_entity) and hover_entity != entity:
        hover_entity.set_hover_state("")
    hover_entity = entity
    hover_state = state
    if is_instance_valid(hover_entity):
        hover_entity.set_hover_state(state)

func _selection_has_combat_unit():
    for entity in selected_entities:
        if is_instance_valid(entity) and entity.has_method("is_combat_unit") and entity.is_combat_unit():
            return true
    return false

func _selection_has_movable_unit():
    for entity in selected_entities:
        if is_instance_valid(entity) and entity.has_method("command_move"):
            return true
    return false

func _selected_movable_units():
    var result = []
    for entity in selected_entities:
        if is_instance_valid(entity) and entity.has_method("command_move"):
            result.append(entity)
    return result

func _selected_harvesters():
    var result = []
    for entity in selected_entities:
        if is_instance_valid(entity) and entity.has_method("command_harvest") and entity.unit_id == "harvester":
            result.append(entity)
    return result

func _selected_production_buildings():
    var result = []
    for entity in selected_entities:
        if is_instance_valid(entity) and entity.has_method("is_production_building") and entity.is_production_building():
            result.append(entity)
    return result

func _selected_defense_buildings():
    var result = []
    for entity in selected_entities:
        if is_instance_valid(entity) and entity.has_method("is_defense_building") and entity.is_defense_building():
            result.append(entity)
    return result

func _selection_has_defense_building():
    return not _selected_defense_buildings().is_empty()

func _set_command_mode(next_mode):
    command_mode = next_mode
    if is_instance_valid(hud):
        hud.set_command_mode(command_mode)
    if command_mode == "attack_move":
        EventBus.notification_requested.emit("攻击移动：左键选择目标点；按住 Shift 可加入路径点", "info")
    elif command_mode == "patrol":
        EventBus.notification_requested.emit("巡逻：连续点击设置多个巡逻点；再次点击第一个点形成闭环", "info")
    elif command_mode == "harvest":
        EventBus.notification_requested.emit("采集：左键点击矿石格指定采集目标", "info")
    elif command_mode == "rally":
        EventBus.notification_requested.emit("设置集结点：左键选择生产单位前往的位置；右键可快捷设置", "info")
    elif command_mode == "building_attack":
        EventBus.notification_requested.emit("防御建筑攻击：左键选择可见的敌方目标", "info")
    elif command_mode == "force_attack":
        EventBus.notification_requested.emit("强制攻击：点击地面、矿石、树木或其他目标；Ctrl+A", "info")
    elif command_mode == "repair_building":
        EventBus.notification_requested.emit("维修：点击受损的己方建筑，再次点击可停止维修", "info")
    elif command_mode == "sell_building":
        EventBus.notification_requested.emit("变卖：点击己方建筑，按当前生命值返还25%至75%原价", "warning")

func execute_command_from_hud(command_id):
    if command_id in ["move", "attack_move", "patrol", "harvest", "rally", "building_attack", "force_attack", "repair_building", "sell_building"]:
        _set_command_mode("" if command_mode == command_id else command_id)
    elif command_id == "primary":
        _set_selected_producers_primary()
    elif command_id == "stop" or command_id == "hold":
        _issue_immediate_unit_command(command_id)
    elif command_id == "building_stop":
        _issue_immediate_selection_command("stop")
    elif command_id == "behavior":
        _open_selected_behavior_panel()

func _issue_targeted_command(target_position, queued):
    var mode = command_mode
    var movable = _selected_movable_units()
    if mode == "move":
        _issue_move_command(target_position, queued)
    elif mode == "repair_building":
        var repair_target = get_entity_at(target_position, true)
        if not is_instance_valid(repair_target) or repair_target.owner_id != 0 or not repair_target.has_method("is_defense_building"):
            EventBus.notification_requested.emit("请选择受损的己方建筑", "warning")
            return
        toggle_building_repair(repair_target)
    elif mode == "sell_building":
        var sell_target = get_entity_at(target_position, true)
        if not is_instance_valid(sell_target) or sell_target.owner_id != 0 or not sell_target.has_method("is_defense_building"):
            EventBus.notification_requested.emit("请选择己方建筑", "warning")
            return
        sell_building(sell_target)
    elif mode == "force_attack":
        var forced_target = get_entity_at(target_position, true)
        var forced_units = []
        for entity in movable:
            if entity.is_combat_unit():
                entity.command_force_attack(forced_target if is_instance_valid(forced_target) else target_position, queued)
                forced_units.append(entity)
        var forced_buildings = []
        for building in _selected_defense_buildings():
            if building.command_force_attack(forced_target if is_instance_valid(forced_target) else target_position):
                forced_buildings.append(building)
        if not forced_units.is_empty() or not forced_buildings.is_empty():
            overlay.add_command_marker(target_position, Color("#F06E67"), "强")
            if not forced_units.is_empty():
                VoiceManager.speak(forced_units[0].unit_id, "attack")
    elif mode == "building_attack":
        var target = get_entity_at(target_position, false)
        var defenders = _selected_defense_buildings()
        if not is_instance_valid(target) or not are_enemies(0, target.owner_id) or not fog.is_world_visible(target.global_position):
            EventBus.notification_requested.emit("请选择可见的敌方目标", "warning")
            return
        var commanded = []
        for building in defenders:
            if building.command_attack(target):
                commanded.append(building)
        if not commanded.is_empty():
            overlay.add_command_marker(target.global_position, Color("#F06E67"), "攻")
    elif mode == "attack_move":
        var enemy = get_entity_at(target_position, false)
        var attackers = []
        if is_instance_valid(enemy) and are_enemies(0, enemy.owner_id) and fog.is_world_visible(enemy.global_position):
            for entity in movable:
                if entity.is_combat_unit():
                    entity.command_attack(enemy, queued)
                    attackers.append(entity)
            overlay.add_command_marker(target_position, Color("#F06E67"), _queued_marker_label(attackers, queued))
        else:
            var targets = _formation_targets(movable, target_position)
            for index in range(movable.size()):
                movable[index].command_attack_move(targets[index], queued)
            overlay.add_command_marker(target_position, Color("#F06E67"), _queued_marker_label(movable, queued))
            attackers = movable
        if not attackers.is_empty():
            VoiceManager.speak(attackers[0].unit_id, "attack")
    elif mode == "patrol":
        var route_closed = false
        var patrol_targets = _formation_targets(movable, target_position)
        for index in range(movable.size()):
            var entity = movable[index]
            route_closed = bool(entity.command_patrol(patrol_targets[index], entity.is_patrolling())) or route_closed
        var patrol_label = "1"
        if not movable.is_empty():
            patrol_label = str(max(1, movable[0].get_patrol_point_count()))
        overlay.add_command_marker(target_position, Color("#58AFFF"), "闭" if route_closed else patrol_label)
        if route_closed:
            EventBus.notification_requested.emit("巡逻路线已闭合", "info")
            _set_command_mode("")
        return
    elif mode == "harvest":
        var ore = get_entity_at(target_position, true)
        var harvesters = _selected_harvesters()
        if is_instance_valid(ore) and ore.has_method("is_resource_entity") and ore.is_resource_entity() and not ore.is_depleted():
            for harvester in harvesters:
                harvester.command_harvest(ore, queued)
            overlay.add_command_marker(ore.global_position, Color("#E4C44E"), _queued_marker_label(harvesters, queued))
        else:
            EventBus.notification_requested.emit("请点击仍有储量的矿石格", "warning")
            return
    elif mode == "rally":
        var producers = _selected_production_buildings()
        for building in producers:
            building.set_rally_point(target_position)
        if not producers.is_empty():
            overlay.add_command_marker(target_position, Color("#69D889"), "集")
    if not Input.is_key_pressed(KEY_SHIFT):
        _set_command_mode("")

func _issue_immediate_unit_command(command_id):
    for entity in _selected_movable_units():
        if command_id == "stop":
            entity.command_stop()
        elif command_id == "hold":
            entity.command_hold()
    overlay.add_command_marker(_selection_center(), Color("#E0D477"))
    _set_command_mode("")

func _issue_immediate_selection_command(command_id):
    _issue_immediate_unit_command(command_id)
    if command_id == "stop":
        for building in _selected_defense_buildings():
            building.command_stop()
    if is_instance_valid(hud):
        hud.set_selection(selected_entities)

func _set_selected_producers_primary():
    var producers = _selected_production_buildings()
    if producers.is_empty():
        return
    for producer in producers:
        set_primary_producer(producer)
    EventBus.notification_requested.emit("已设为主要生产建筑", "info")
    if is_instance_valid(hud):
        hud.set_selection(selected_entities)

func _open_selected_behavior_panel():
    var movable = _selected_movable_units()
    if movable.is_empty():
        return
    if is_instance_valid(hud):
        hud.open_behavior_panel(movable)

func _apply_selected_behavior_settings(settings):
    var applied_count = 0
    for unit in _selected_movable_units():
        if is_instance_valid(unit) and unit.has_method("apply_behavior_settings"):
            unit.apply_behavior_settings(settings)
            applied_count += 1
    if applied_count > 0:
        EventBus.notification_requested.emit("已更新 %d 个单位的智能逻辑" % applied_count, "info")
        if is_instance_valid(hud):
            hud.set_selection(selected_entities)

func notify_allies_under_attack(victim, attacker):
    if not is_instance_valid(victim) or not is_instance_valid(attacker):
        return
    var victim_key = int(victim.get_instance_id())
    var now = int(Time.get_ticks_msec())
    if now < int(support_broadcast_until.get(victim_key, 0)):
        return
    support_broadcast_until[victim_key] = now + 320
    # Search broadly once, then let each unit enforce its own support range and
    # same-owner/allied-player policy.
    for ally in query_units_in_radius(victim.global_position, 920.0, victim):
        if not is_instance_valid(ally) or are_enemies(ally.owner_id, victim.owner_id):
            continue
        ally.support_ally_against(attacker, victim)

func _queued_marker_label(entities, queued):
    if not queued or entities.is_empty():
        return ""
    var highest = 0
    for entity in entities:
        if is_instance_valid(entity) and entity.has_method("get_order_queue_count"):
            highest = max(highest, int(entity.get_order_queue_count()))
    return str(max(1, highest))

func _selection_center():
    var total = Vector2.ZERO
    var count = 0
    for entity in selected_entities:
        if is_instance_valid(entity):
            total += entity.global_position
            count += 1
    return total / float(count) if count > 0 else camera.position

func _select_all_combat_units():
    var combat_units = []
    for unit in units:
        if is_instance_valid(unit) and unit.owner_id == 0 and unit.is_combat_unit():
            combat_units.append(unit)
    _set_selection(combat_units, false)
    EventBus.notification_requested.emit("已选择全部作战单位：%d" % combat_units.size(), "info")

func _handle_control_group_key(group_number, ctrl_pressed, shift_pressed):
    var valid_group = []
    for entity in control_groups.get(group_number, []):
        if is_instance_valid(entity) and not (entity.has_method("is_movable_unit") and bool(entity.inside_refinery)):
            valid_group.append(entity)
    if ctrl_pressed:
        control_groups[group_number] = selected_entities.duplicate()
        active_group_number = group_number
        EventBus.notification_requested.emit("已设置编队 %d，共 %d 个单位" % [group_number, selected_entities.size()], "info")
        return
    if shift_pressed:
        for entity in selected_entities:
            if is_instance_valid(entity) and not entity in valid_group:
                valid_group.append(entity)
        control_groups[group_number] = valid_group
        active_group_number = group_number
        EventBus.notification_requested.emit("已加入编队 %d，当前 %d 个单位" % [group_number, valid_group.size()], "info")
        return
    var already_selected = _same_entity_set(selected_entities, valid_group)
    _set_selection(valid_group, false)
    if already_selected and not valid_group.is_empty():
        camera.position = _entities_center(valid_group)
        _clamp_camera()
    active_group_number = group_number

func _same_entity_set(first, second):
    var valid_first = []
    for entity in first:
        if is_instance_valid(entity):
            valid_first.append(entity)
    if valid_first.size() != second.size():
        return false
    for entity in valid_first:
        if not entity in second:
            return false
    return true

func _entities_center(entities):
    var total = Vector2.ZERO
    var count = 0
    for entity in entities:
        if is_instance_valid(entity):
            total += entity.global_position
            count += 1
    return total / float(count) if count > 0 else camera.position

func _structure_category(building_id):
    return "defense" if str(GameConfig.buildings.get(building_id, {}).get("category", "primary")) == "defense" else "primary"

func get_structure_job(category):
    return structure_jobs.get(str(category), {})

func get_ready_structure(category):
    return str(ready_structures.get(str(category), ""))

func get_structure_status(building_id):
    var category = _structure_category(building_id)
    var ready_id = get_ready_structure(category)
    var job = get_structure_job(category)
    if ready_id == building_id:
        return {"state": "ready", "progress": 1.0, "paused": false}
    if not job.is_empty() and str(job.get("id", "")) == building_id:
        return {
            "state": "paused" if bool(job.get("paused", false)) else "building",
            "progress": clamp(float(job.get("progress", 0.0)) / max(0.01, float(job.get("duration", 1.0))), 0.0, 1.0),
            "paused": bool(job.get("paused", false))
        }
    return {"state": "idle", "progress": 0.0, "paused": false}

func request_structure(building_id):
    if not GameConfig.buildings.has(building_id):
        return
    var category = _structure_category(building_id)
    var job = get_structure_job(category)
    if not job.is_empty() and str(job.get("id", "")) == building_id and bool(job.get("paused", false)):
        job["paused"] = false
        structure_jobs[category] = job
        EventBus.notification_requested.emit("继续建造：" + str(GameConfig.buildings[building_id].name), "info")
        return
    if get_ready_structure(category) == building_id:
        ready_structure_id = building_id
        ready_structure_cost = int(ready_structure_costs.get(category, 0))
        placement_mode = true
        EventBus.notification_requested.emit("选择 %s 的部署位置" % GameConfig.buildings[building_id].name, "info")
        return
    if not can_request_structure(building_id, true):
        return
    var data = GameConfig.buildings[building_id]
    add_credits(0, -int(data.cost))
    structure_jobs[category] = {
        "id": building_id,
        "progress": 0.0,
        "duration": float(data.build_time),
        "paused": false,
        "cost": int(data.cost)
    }
    EventBus.notification_requested.emit("开始建造：" + str(data.name), "info")

func pause_or_cancel_structure(building_id):
    var category = _structure_category(building_id)
    if get_ready_structure(category) == building_id:
        add_credits(0, int(ready_structure_costs.get(category, 0)))
        ready_structures[category] = ""
        ready_structure_costs[category] = 0
        if ready_structure_id == building_id:
            ready_structure_id = ""
            ready_structure_cost = 0
            placement_mode = false
            overlay.set_placement(false)
        EventBus.notification_requested.emit("已取消就绪建筑并退还资金", "info")
        return true
    var job = get_structure_job(category)
    if job.is_empty() or str(job.get("id", "")) != building_id:
        return false
    if not bool(job.get("paused", false)):
        job["paused"] = true
        structure_jobs[category] = job
        EventBus.notification_requested.emit("已暂停建造：" + str(GameConfig.buildings[building_id].name), "info")
        return true
    var progress_ratio = clamp(float(job.get("progress", 0.0)) / max(0.01, float(job.get("duration", 1.0))), 0.0, 1.0)
    var refund = int(round(float(job.get("cost", 0)) * (1.0 - progress_ratio * 0.25)))
    add_credits(0, refund)
    structure_jobs[category] = {}
    EventBus.notification_requested.emit("已取消建造，退还 $%d" % refund, "info")
    return true

func can_request_structure(building_id, notify = false):
    if not GameConfig.buildings.has(building_id):
        return false
    var category = _structure_category(building_id)
    if get_ready_structure(category) != "" or not get_structure_job(category).is_empty():
        if notify:
            EventBus.notification_requested.emit("该建筑分类的建造产能正在使用", "warning")
        return false
    var data = GameConfig.buildings[building_id]
    var requirement = str(data.get("requires", ""))
    if requirement != "" and not has_building(0, requirement):
        if notify:
            EventBus.notification_requested.emit("需要先建造：" + str(GameConfig.buildings[requirement].name), "warning")
        return false
    if int(credits.get(0, 0)) < int(data.cost):
        if notify:
            EventBus.notification_requested.emit("资金不足", "warning")
        return false
    return true

func _process_structure_queue(delta):
    for category in ["primary", "defense"]:
        var job = get_structure_job(category)
        if job.is_empty() or bool(job.get("paused", false)):
            continue
        var speed_factor = 1.0
        var power = power_state.get(0, {"produced": 0, "consumed": 0})
        if int(power.produced) < int(power.consumed):
            speed_factor = 0.35
        job["progress"] = float(job.get("progress", 0.0)) + delta * speed_factor
        if float(job.get("progress", 0.0)) >= float(job.get("duration", 1.0)):
            ready_structures[category] = str(job.get("id", ""))
            ready_structure_costs[category] = int(job.get("cost", 0))
            structure_jobs[category] = {}
            EventBus.notification_requested.emit("建筑已就绪：点击建造栏或按对应分类快捷键部署", "info")
            VoiceManager.speak_adjutant("building_ready")
        else:
            structure_jobs[category] = job

func _update_placement_preview():
    if ready_structure_id == "" or not placement_mode:
        placement_mode = false
        overlay.set_placement(false)
        return
    var data = GameConfig.buildings[ready_structure_id]
    var fp_data = data.footprint
    var footprint = Vector2i(int(fp_data[0]), int(fp_data[1]))
    var cell = grid.world_to_cell(_current_world_mouse_position())
    var valid = _can_place_structure_without_units(cell, footprint) and _is_in_build_radius(cell, 0)
    overlay.set_placement(true, cell, footprint, valid)

func _attempt_place_structure():
    _attempt_place_structure_at(_current_world_mouse_position())

func _attempt_place_structure_at(world_position):
    if ready_structure_id == "":
        return
    var data = GameConfig.buildings[ready_structure_id]
    var footprint = Vector2i(int(data.footprint[0]), int(data.footprint[1]))
    var cell = grid.world_to_cell(world_position)
    if not _can_place_structure_without_units(cell, footprint):
        EventBus.notification_requested.emit("该位置不可建造，建筑范围内存在单位或障碍", "warning")
        return
    if not _is_in_build_radius(cell, 0):
        EventBus.notification_requested.emit("必须部署在己方建筑的建造半径内", "warning")
        return
    spawn_building(0, ready_structure_id, cell, true)
    EventBus.notification_requested.emit("部署完成：" + str(data.name), "info")
    var completed_category = _structure_category(ready_structure_id)
    ready_structures[completed_category] = ""
    ready_structure_costs[completed_category] = 0
    ready_structure_id = ""
    ready_structure_cost = 0
    placement_mode = false
    overlay.set_placement(false)


func _can_place_structure_without_units(cell, footprint):
    if not grid.can_place(cell, footprint):
        return false
    var world_rect = Rect2(grid.cell_to_world(cell) - Vector2(grid.tile_px * 0.5, grid.tile_px * 0.5), Vector2(footprint.x * grid.tile_px, footprint.y * grid.tile_px))
    for unit in units:
        if not is_instance_valid(unit) or unit.inside_refinery:
            continue
        var radius = float(unit.stats.get("collision_radius", unit.stats.get("radius", 12.0)))
        if world_rect.grow(radius).has_point(unit.global_position):
            return false
    return true

func _is_in_build_radius(cell, owner_id):
    for building in buildings:
        if is_instance_valid(building) and building.owner_id == owner_id:
            if Vector2(building.origin_cell).distance_to(Vector2(cell)) <= 10.5:
                return true
    return false

func request_unit(owner_id, unit_id):
    var paused_producer = _producer_with_paused_front(owner_id, unit_id)
    if is_instance_valid(paused_producer):
        paused_producer.resume_front_job(unit_id)
        if owner_id == 0:
            EventBus.notification_requested.emit("继续生产：" + str(GameConfig.units[unit_id].name), "info")
        return true
    if not can_request_unit(owner_id, unit_id, true):
        return false
    var data = GameConfig.units[unit_id]
    var faction = str(get_player_data(owner_id).get("faction", "union"))
    var modifier = float(GameConfig.factions.get(faction, {}).get("unit_modifiers", {}).get("cost", 1.0))
    var actual_cost = int(round(float(data.cost) * modifier))
    add_credits(owner_id, -actual_cost)
    var producer = _producer_building_for_unit(owner_id, unit_id)
    producer.enqueue_unit(unit_id, actual_cost)
    if owner_id == 0:
        EventBus.notification_requested.emit("已加入生产队列：" + str(data.name), "info")
    return true

func pause_or_cancel_unit(owner_id, unit_id):
    var producer = _producer_with_queued_unit(owner_id, unit_id)
    if not is_instance_valid(producer):
        return false
    var result = producer.pause_or_cancel_unit(unit_id)
    var action = str(result.get("action", "none"))
    if action == "paused":
        if owner_id == 0:
            EventBus.notification_requested.emit("已暂停生产：" + str(GameConfig.units[unit_id].name), "info")
        return true
    if action == "canceled":
        var refund = int(result.get("refund", 0))
        add_credits(owner_id, refund)
        if owner_id == 0:
            EventBus.notification_requested.emit("已减少或取消队列，退还 $%d" % refund, "info")
        return true
    return false

func request_ai_unit(owner_id, unit_id):
    return request_unit(owner_id, unit_id)

func can_request_unit(owner_id, unit_id, notify = false):
    if not GameConfig.units.has(unit_id):
        return false
    var producer = _producer_building_for_unit(owner_id, unit_id)
    if not is_instance_valid(producer):
        if notify and owner_id == 0:
            var requirement = str(GameConfig.units[unit_id].requires)
            EventBus.notification_requested.emit("需要可用的" + str(GameConfig.buildings.get(requirement, {}).get("name", requirement)), "warning")
        return false
    if producer.production_queue.size() >= 5:
        if notify and owner_id == 0:
            EventBus.notification_requested.emit("生产队列已满", "warning")
        return false
    var faction = str(get_player_data(owner_id).get("faction", "union"))
    var modifier = float(GameConfig.factions.get(faction, {}).get("unit_modifiers", {}).get("cost", 1.0))
    var actual_cost = int(round(float(GameConfig.units[unit_id].cost) * modifier))
    if int(credits.get(owner_id, 0)) < actual_cost:
        if notify and owner_id == 0:
            EventBus.notification_requested.emit("资金不足", "warning")
        return false
    return true

func _producer_building_for_unit(owner_id, unit_id):
    var category = str(GameConfig.units.get(unit_id, {}).get("category", "infantry"))
    var required = "barracks" if category == "infantry" else "war_factory"
    var primary_key = "%d:%s" % [owner_id, required]
    var primary = primary_producers.get(primary_key)
    if is_instance_valid(primary) and primary.owner_id == owner_id and primary.building_id == required and primary.production_queue.size() < 5:
        return primary
    var best
    var smallest_queue = INF
    for building in buildings:
        if is_instance_valid(building) and building.owner_id == owner_id and building.building_id == required:
            if building.production_queue.size() < smallest_queue:
                smallest_queue = building.production_queue.size()
                best = building
    return best

func set_primary_producer(building):
    if not is_instance_valid(building) or not building.is_production_building():
        return false
    var key = "%d:%s" % [building.owner_id, building.building_id]
    var previous = primary_producers.get(key)
    if is_instance_valid(previous) and previous != building:
        previous.set_primary(false)
    primary_producers[key] = building
    building.set_primary(true)
    return true

func _producer_with_paused_front(owner_id, unit_id):
    for building in buildings:
        if is_instance_valid(building) and building.owner_id == owner_id and building.is_front_job_paused(unit_id):
            return building
    return null

func _producer_with_queued_unit(owner_id, unit_id):
    for building in buildings:
        if is_instance_valid(building) and building.owner_id == owner_id and not building.production_queue.is_empty():
            var front = building.production_queue[0]
            if str(front.get("id", "")) == unit_id:
                return building
    for building in buildings:
        if is_instance_valid(building) and building.owner_id == owner_id and building.has_queued(unit_id):
            return building
    return null

func get_unit_queue_count(owner_id, unit_id):
    var total = 0
    for building in buildings:
        if is_instance_valid(building) and building.owner_id == owner_id:
            total += building.count_queued(unit_id)
    return total

func get_unit_queue_progress(owner_id, unit_id):
    for building in buildings:
        if not is_instance_valid(building) or building.owner_id != owner_id:
            continue
        if building.production_queue.is_empty():
            continue
        var front = building.production_queue[0]
        if str(front.get("id", "")) == unit_id:
            return building.queue_progress()
    return 0.0

func is_unit_queue_paused(owner_id, unit_id):
    return is_instance_valid(_producer_with_paused_front(owner_id, unit_id))

func has_structure_interaction(building_id):
    return str(get_structure_status(building_id).get("state", "idle")) != "idle"

func get_requirement_hint(id_value, is_structure):
    var data = GameConfig.buildings.get(id_value, {}) if is_structure else GameConfig.units.get(id_value, {})
    var requirement = str(data.get("requires", ""))
    var lines = ["%s · $%d · %.1f 秒" % [str(data.get("name", id_value)), int(data.get("cost", 0)), float(data.get("build_time", 0.0))]]
    if requirement != "":
        lines.append("前置：" + str(GameConfig.buildings.get(requirement, {}).get("name", requirement)))
    return "\n".join(lines)

func spawn_building(owner_id, building_id, preferred_cell, animate_construction = false):
    if not GameConfig.buildings.has(building_id):
        return null
    var data = GameConfig.buildings[building_id]
    var footprint = Vector2i(int(data.footprint[0]), int(data.footprint[1]))
    var cell = _find_building_cell(preferred_cell, footprint)
    if cell.x < 0:
        return null
    var building = BuildingEntity.new()
    entity_layer.add_child(building)
    building.setup(self, grid, building_id, owner_id, cell, animate_construction)
    building.died.connect(_on_entity_died)
    building.production_ready.connect(_on_unit_production_ready)
    building.fired.connect(_spawn_tracer)
    buildings.append(building)
    var granted_unit = str(data.get("grants_unit", ""))
    if granted_unit != "":
        call_deferred("_grant_unit_from_building", building, granted_unit)
    return building

func _grant_unit_from_building(building, unit_id):
    if not is_instance_valid(building):
        return
    var spawn_position = get_production_exit_position(building)
    var unit = spawn_unit(building.owner_id, unit_id, spawn_position)
    if is_instance_valid(unit):
        unit.command_move(building.rally_point, false)
        if building.owner_id == 0:
            EventBus.notification_requested.emit("矿石精炼厂附赠一辆采矿车", "info")
            VoiceManager.speak(unit_id, "ready", true)

func _find_building_cell(preferred, footprint):
    if grid.can_place(preferred, footprint):
        return preferred
    for radius in range(1, 9):
        for y in range(preferred.y - radius, preferred.y + radius + 1):
            for x in range(preferred.x - radius, preferred.x + radius + 1):
                var cell = Vector2i(x, y)
                if grid.can_place(cell, footprint):
                    return cell
    return Vector2i(-1, -1)

func spawn_unit(owner_id, unit_id, world_position):
    if not GameConfig.units.has(unit_id):
        return null
    var category = str(GameConfig.units[unit_id].get("category", "vehicle"))
    var spawn_position = find_clear_unit_position(world_position, float(GameConfig.units[unit_id].get("collision_radius", 12.0)), null, category)
    if spawn_position == Vector2.ZERO:
        return null
    var unit = UnitEntity.new()
    entity_layer.add_child(unit)
    unit.setup(self, grid, unit_id, owner_id, spawn_position)
    if owner_id > 0:
        unit.apply_behavior_settings({
            "guard_enabled": true,
            "guard_range": max(float(unit.stats.get("range", 0.0)) * 1.35, float(unit.stats.get("guard_range", 250.0))),
            "auto_attack_enabled": true,
            "chase_enabled": true,
            "chase_distance": 180.0,
            "support_same_owner_enabled": true,
            "support_allied_enabled": true,
            "support_range": 360.0
        })
    unit.died.connect(_on_entity_died)
    unit.fired.connect(_spawn_tracer)
    units.append(unit)
    _invalidate_unit_spatial_hash()
    return unit

func find_clear_unit_position(preferred_position, radius = 12.0, ignore_unit = null, category = "vehicle"):
    var origin = grid.world_to_cell(preferred_position)
    for scan_radius in range(0, 9):
        for y in range(origin.y - scan_radius, origin.y + scan_radius + 1):
            for x in range(origin.x - scan_radius, origin.x + scan_radius + 1):
                var cell = Vector2i(x, y)
                if not grid.is_cell_walkable(cell, category):
                    continue
                var candidate = grid.cell_to_world(cell)
                var clear = true
                for unit in units:
                    if not is_instance_valid(unit) or unit == ignore_unit or unit.inside_refinery or unit.inside_repair_bay or unit.dying:
                        continue
                    var other_radius = float(unit.stats.get("collision_radius", unit.stats.get("radius", 12.0)))
                    if candidate.distance_to(unit.global_position) < radius + other_radius + 4.0:
                        clear = false
                        break
                if clear:
                    return candidate
    return Vector2.ZERO

func get_production_exit_position(building):
    if not is_instance_valid(building):
        return Vector2.ZERO
    var preferred = building.global_position + building.global_position.direction_to(building.rally_point) * max(building.footprint.x, building.footprint.y) * grid.tile_px
    if preferred.distance_to(building.global_position) < 4.0:
        preferred = building.global_position + Vector2((building.footprint.x + 1) * grid.tile_px, 0)
    return find_clear_unit_position(preferred, 18.0)

func _on_unit_production_ready(unit_id, producer):
    if not is_instance_valid(producer):
        return
    var spawn_position = get_production_exit_position(producer)
    var unit = spawn_unit(producer.owner_id, unit_id, spawn_position)
    if is_instance_valid(unit):
        unit.command_move(producer.rally_point, false)
        if producer.owner_id == 0:
            EventBus.notification_requested.emit(str(GameConfig.units[unit_id].name) + " 生产完成", "info")
            VoiceManager.speak_adjutant("unit_ready")
            VoiceManager.speak(unit_id, "ready", true)

func _spawn_tracer(from_point, to_point, owner_id):
    if active_tracer_count >= MAX_ACTIVE_TRACERS or not is_instance_valid(effect_layer):
        return
    var tracer = Tracer.new()
    active_tracer_count += 1
    tracer.tree_exited.connect(_on_tracer_exited)
    effect_layer.add_child(tracer)
    tracer.setup(from_point, to_point, get_player_color(owner_id).lightened(0.28))

func _on_entity_died(entity):
    if hover_entity == entity:
        _set_hover_entity(null, "")
    selected_entities.erase(entity)
    units.erase(entity)
    _invalidate_unit_spatial_hash()
    buildings.erase(entity)
    repairing_buildings.erase(entity)
    repair_credit_buffers.erase(int(entity.get_instance_id()))
    support_broadcast_until.erase(int(entity.get_instance_id()))
    harvester_unload_jobs = harvester_unload_jobs.filter(func(job): return job.get("unit") != entity and job.get("refinery") != entity)
    for key in primary_producers.keys():
        if primary_producers[key] == entity:
            primary_producers.erase(key)
    if is_instance_valid(hud):
        hud.set_selection(selected_entities)
    if is_instance_valid(overlay):
        overlay.set_selected_entities(selected_entities)
    call_deferred("_check_victory")

func _update_power():
    var player_count = match_config.get("players", []).size()
    for player_id in range(player_count):
        var produced = 0
        var consumed = 0
        for building in buildings:
            if is_instance_valid(building) and building.owner_id == player_id:
                produced += building.get_power_output()
                consumed += building.get_power_use()
        power_state[player_id] = {"produced": produced, "consumed": consumed}
        var enough = produced >= consumed
        for building in buildings:
            if is_instance_valid(building) and building.owner_id == player_id:
                building.powered = enough or building.get_power_use() == 0
                building.queue_redraw()
        EventBus.power_changed.emit(player_id, produced, consumed)

func add_credits(player_id, amount):
    credits[player_id] = max(0, int(credits.get(player_id, 0)) + int(amount))
    EventBus.credits_changed.emit(player_id, credits[player_id])

func apply_weapon_damage(source, primary_target, damage, area_radius = 0.0):
    if not is_instance_valid(primary_target):
        return
    primary_target.take_damage(damage, source)
    if area_radius <= 0.0:
        return
    for entity in units + buildings:
        if not is_instance_valid(entity) or entity == primary_target or entity == source:
            continue
        if not are_enemies(source.owner_id, entity.owner_id):
            continue
        var distance = entity.global_position.distance_to(primary_target.global_position)
        if distance <= area_radius:
            var falloff = lerp(0.45, 0.8, 1.0 - distance / max(1.0, area_radius))
            entity.take_damage(damage * falloff, source)

func apply_ground_damage(source, world_position, damage, area_radius = 0.0, ignored_entity = null):
    var radius = max(10.0, area_radius)
    for entity in units + buildings + tree_entities:
        if not is_instance_valid(entity) or entity == source or entity == ignored_entity or not entity.has_method("take_damage"):
            continue
        var distance = entity.global_position.distance_to(world_position)
        if distance <= radius:
            var falloff = lerp(0.4, 0.85, 1.0 - distance / max(1.0, radius))
            entity.take_damage(float(damage) * falloff, source)

func spawn_muzzle_flash(world_position, color):
    if not is_instance_valid(effect_layer):
        return
    var effect = CombatEffect.new()
    effect_layer.add_child(effect)
    effect.global_position = world_position
    effect.setup("muzzle", Color(color), 0.48, false, randi())

func try_spend_credits(player_id, amount):
    var cost = max(0, int(ceil(float(amount))))
    if cost <= 0:
        return true
    if int(credits.get(player_id, 0)) < cost:
        return false
    add_credits(player_id, -cost)
    return true

func repair_entity_step(entity, delta, source = null):
    if not is_instance_valid(entity) or entity.hp >= entity.max_hp:
        return {"complete": true, "healed": 0.0, "cost": 0}
    var original_cost = float(entity.stats.get("cost", 0.0))
    var cost_per_hp = original_cost * 0.40 / max(1.0, float(entity.max_hp))
    var heal_rate = max(8.0, float(entity.max_hp) * 0.075)
    var missing_hp = max(0.0, float(entity.max_hp) - float(entity.hp))
    var requested_heal = min(missing_hp, heal_rate * float(delta))
    if requested_heal <= 0.0:
        return {"complete": true, "healed": 0.0, "cost": 0}
    if cost_per_hp > 0.0:
        var affordable_hp = float(credits.get(entity.owner_id, 0)) / cost_per_hp
        requested_heal = min(requested_heal, affordable_hp)
        if requested_heal <= 0.001:
            return {"complete": false, "healed": 0.0, "cost": 0, "no_funds": true}
    var healed = float(entity.heal(requested_heal))
    var instance_key = int(entity.get_instance_id())
    var accumulated = float(repair_credit_buffers.get(instance_key, 0.0)) + healed * cost_per_hp
    var payable = int(floor(accumulated + 0.0001))
    if payable > 0:
        payable = min(payable, int(credits.get(entity.owner_id, 0)))
        add_credits(entity.owner_id, -payable)
        accumulated -= float(payable)
    repair_credit_buffers[instance_key] = accumulated
    if entity.hp >= entity.max_hp - 0.01:
        repair_credit_buffers.erase(instance_key)
    return {"complete": entity.hp >= entity.max_hp - 0.01, "healed": healed, "cost": payable}

func toggle_building_repair(building):
    if not is_instance_valid(building) or building.owner_id != 0 or building.hp >= building.max_hp:
        return
    if building in repairing_buildings:
        repairing_buildings.erase(building)
        building.set_repair_active(false)
        EventBus.notification_requested.emit("已停止维修建筑", "info")
    else:
        repairing_buildings.append(building)
        building.set_repair_active(true)
        EventBus.notification_requested.emit("开始维修：" + str(building.stats.get("name", building.building_id)), "info")

func _process_building_repairs(delta):
    for building in repairing_buildings.duplicate():
        if not is_instance_valid(building) or building.hp >= building.max_hp or building.selling:
            repairing_buildings.erase(building)
            if is_instance_valid(building):
                building.set_repair_active(false)
            continue
        var result = repair_entity_step(building, delta, building)
        if bool(result.get("no_funds", false)):
            repairing_buildings.erase(building)
            building.set_repair_active(false)
            EventBus.notification_requested.emit("资金不足，建筑维修已停止", "warning")
            continue
        if bool(result.get("complete", false)):
            repairing_buildings.erase(building)
            building.set_repair_active(false)

func sell_building(building):
    if not is_instance_valid(building) or building.owner_id != 0 or building.selling:
        return
    var hp_ratio = clamp(float(building.hp) / max(1.0, float(building.max_hp)), 0.0, 1.0)
    var refund_ratio = 0.25 + hp_ratio * 0.50
    var refund = int(round(float(building.stats.get("cost", 0)) * refund_ratio))
    repairing_buildings.erase(building)
    building.set_repair_active(false)
    if building.begin_sell(refund):
        EventBus.notification_requested.emit("正在变卖：预计返还 $%d" % refund, "warning")

func complete_building_sale(building, refund):
    if not is_instance_valid(building) or not building in buildings:
        return
    if building.has_method("eject_repairing_vehicle"):
        building.eject_repairing_vehicle()
    grid.vacate(building)
    selected_entities.erase(building)
    buildings.erase(building)
    repair_credit_buffers.erase(int(building.get_instance_id()))
    add_credits(building.owner_id, int(refund))
    EventBus.notification_requested.emit("建筑已变卖，返还 $%d" % int(refund), "info")
    if is_instance_valid(hud):
        hud.set_selection(selected_entities)
    building.queue_free()

func spawn_combat_text(world_position, text_value, kind):
    if active_combat_text_count >= MAX_ACTIVE_COMBAT_TEXTS or not is_instance_valid(effect_layer):
        return
    if kind != "credits" and is_instance_valid(fog) and fog.enabled and not fog.is_world_visible(world_position):
        return
    if kind == "damage" and not bool(SaveManager.settings.get("show_damage_numbers", true)):
        return
    if kind == "heal" and not bool(SaveManager.settings.get("show_heal_numbers", true)):
        return
    var color = Color("#F26F66") if kind == "damage" else Color("#6FE08C")
    if kind == "credits":
        color = Color("#E6CA5F")
    var floating = FloatingText.new()
    active_combat_text_count += 1
    floating.tree_exited.connect(_on_combat_text_exited)
    effect_layer.add_child(floating)
    floating.global_position = world_position + Vector2(randf_range(-6.0, 6.0), -18.0)
    floating.setup(text_value, color)

func get_refinery_dropoff_position(refinery, from_position, harvester = null):
    if not is_instance_valid(refinery):
        return Vector2.ZERO
    var min_x = refinery.origin_cell.x - 1
    var max_x = refinery.origin_cell.x + refinery.footprint.x
    var min_y = refinery.origin_cell.y - 1
    var max_y = refinery.origin_cell.y + refinery.footprint.y
    var candidates = []
    for x in range(min_x, max_x + 1):
        candidates.append(Vector2i(x, min_y))
        candidates.append(Vector2i(x, max_y))
    for y in range(min_y + 1, max_y):
        candidates.append(Vector2i(min_x, y))
        candidates.append(Vector2i(max_x, y))
    var best = Vector2.ZERO
    var best_score = INF
    for cell in candidates:
        if not grid.is_cell_walkable(cell):
            continue
        var world = grid.cell_to_world(cell)
        var route = grid.find_path(from_position, world)
        if route.is_empty():
            continue
        var score = from_position.distance_squared_to(world)
        for other in units:
            if not is_instance_valid(other) or other == harvester or other.inside_refinery:
                continue
            var other_radius = float(other.stats.get("collision_radius", other.stats.get("radius", 12.0)))
            var clearance = (float(harvester.stats.get("collision_radius", 20.0)) if is_instance_valid(harvester) else 20.0) + other_radius + 5.0
            var distance = world.distance_to(other.global_position)
            if distance < clearance:
                score += (clearance - distance) * 8000.0
            if other.unit_id == "harvester" and other.refinery_target == refinery and other.refinery_dropoff.distance_to(world) < 8.0:
                score += 300000.0
        if score < best_score:
            best_score = score
            best = world
    if best == Vector2.ZERO:
        var fallback = grid.nearest_walkable_cell(grid.world_to_cell(refinery.rally_point))
        if fallback.x >= 0:
            best = grid.cell_to_world(fallback)
    return best

func begin_harvester_unload(harvester, refinery):
    if not is_instance_valid(harvester) or not is_instance_valid(refinery):
        return false
    if harvester.inside_refinery or int(harvester.carrying) <= 0:
        return false
    if harvester.owner_id != refinery.owner_id or refinery.building_id != "refinery":
        return false
    if not harvester.enter_refinery(refinery):
        return false
    _remove_entity_from_selection(harvester)
    harvester_unload_jobs.append({"unit": harvester, "refinery": refinery, "remaining": 1.25})
    return true

func _process_harvester_unloads(delta):
    if harvester_unload_jobs.is_empty():
        return
    for index in range(harvester_unload_jobs.size() - 1, -1, -1):
        var job = harvester_unload_jobs[index]
        var harvester = job.get("unit")
        var refinery = job.get("refinery")
        if not is_instance_valid(harvester):
            harvester_unload_jobs.remove_at(index)
            continue
        if not is_instance_valid(refinery):
            var emergency_exit = find_clear_unit_position(harvester.global_position, float(harvester.stats.get("collision_radius", 20.0)), harvester)
            harvester.exit_refinery(false, emergency_exit if emergency_exit != Vector2.ZERO else harvester.global_position)
            harvester_unload_jobs.remove_at(index)
            continue
        job["remaining"] = float(job.get("remaining", 0.0)) - delta
        harvester_unload_jobs[index] = job
        if float(job["remaining"]) > 0.0:
            continue
        var success = deposit_harvester_cargo(harvester, refinery)
        var exit_position = get_refinery_exit_position(refinery, harvester)
        if exit_position == Vector2.ZERO:
            exit_position = get_refinery_dropoff_position(refinery, refinery.global_position, harvester)
        harvester.exit_refinery(success, exit_position)
        harvester_unload_jobs.remove_at(index)
        _update_enemy_visibility()

func get_refinery_exit_position(refinery, harvester = null):
    if not is_instance_valid(refinery):
        return harvester.global_position if is_instance_valid(harvester) else Vector2.ZERO
    var preferred = refinery.global_position + Vector2((refinery.footprint.x + 1.5) * grid.tile_px, 0)
    var radius = float(harvester.stats.get("collision_radius", 20.0)) if is_instance_valid(harvester) else 20.0
    var result = find_clear_unit_position(preferred, radius, harvester)
    if result != Vector2.ZERO:
        return result
    result = find_clear_unit_position(refinery.rally_point, radius, harvester)
    return result if result != Vector2.ZERO else get_refinery_dropoff_position(refinery, refinery.global_position, harvester)

func deposit_harvester_cargo(harvester, refinery):
    if not is_instance_valid(harvester) or not is_instance_valid(refinery):
        return false
    if harvester.owner_id != refinery.owner_id or refinery.building_id != "refinery":
        return false
    var cargo = int(harvester.carrying)
    if cargo <= 0:
        return false
    var value_multiplier = float(harvester.stats.get("ore_value", 1.0))
    var payout = max(1, int(round(cargo * value_multiplier)))
    var before = int(credits.get(harvester.owner_id, 0))
    add_credits(harvester.owner_id, payout)
    var after = int(credits.get(harvester.owner_id, 0))
    if after - before != payout:
        push_error("Harvester deposit transaction failed: expected %d, got %d" % [payout, after - before])
        return false
    return true

func get_player_data(player_id):
    var player_list = match_config.get("players", [])
    if player_id < 0 or player_id >= player_list.size():
        return {}
    return player_list[player_id]

func get_player_color(player_id):
    return Color("#" + str(get_player_data(player_id).get("color", "FFFFFF")))

func are_enemies(first_owner, second_owner):
    return int(get_player_data(first_owner).get("team", first_owner + 1)) != int(get_player_data(second_owner).get("team", second_owner + 1))

func has_building(owner_id, building_id):
    for building in buildings:
        if is_instance_valid(building) and building.owner_id == owner_id and building.building_id == building_id:
            return true
    return false

func get_nearest_building(owner_id, building_id, from_position):
    var best
    var best_distance = INF
    for building in buildings:
        if is_instance_valid(building) and building.owner_id == owner_id and building.building_id == building_id:
            var distance = from_position.distance_squared_to(building.global_position)
            if distance < best_distance:
                best_distance = distance
                best = building
    return best

func get_nearest_reachable_building(owner_id, building_id, from_position):
    var candidates = []
    for building in buildings:
        if is_instance_valid(building) and building.owner_id == owner_id and building.building_id == building_id:
            candidates.append(building)
    candidates.sort_custom(func(a, b): return a.global_position.distance_squared_to(from_position) < b.global_position.distance_squared_to(from_position))
    for building in candidates:
        if not grid.find_path(from_position, building.global_position).is_empty():
            return building
    return null

func get_owned_entities(owner_id):
    var result = []
    for unit in units:
        if is_instance_valid(unit) and unit.owner_id == owner_id:
            result.append(unit)
    for building in buildings:
        if is_instance_valid(building) and building.owner_id == owner_id:
            result.append(building)
    return result

func find_nearest_enemy(owner_id, from_position, max_range = INF):
    var best
    var best_distance = max_range * max_range
    var owner_data = get_player_data(owner_id)
    var controller = str(owner_data.get("controller", "human" if owner_id == 0 else "ai"))
    for entity in units + buildings:
        if not is_instance_valid(entity) or not are_enemies(owner_id, entity.owner_id):
            continue
        # Human-controlled units must not acquire targets through unexplored or
        # currently obscured fog. AI vision remains a separate future system.
        if controller == "human" and is_instance_valid(fog) and fog.enabled and not fog.is_world_visible(entity.global_position):
            continue
        var distance = from_position.distance_squared_to(entity.global_position)
        if distance <= best_distance:
            best_distance = distance
            best = entity
    return best

func get_nearest_enemy_command(owner_id):
    var best
    var best_distance = INF
    var own_command = get_nearest_building(owner_id, "command", Vector2.ZERO)
    var origin = own_command.global_position if is_instance_valid(own_command) else Vector2.ZERO
    for building in buildings:
        if is_instance_valid(building) and building.building_id == "command" and are_enemies(owner_id, building.owner_id):
            var distance = origin.distance_squared_to(building.global_position)
            if distance < best_distance:
                best_distance = distance
                best = building
    return best

func get_human_production_summary():
    for building in buildings:
        if is_instance_valid(building) and building.owner_id == 0 and not building.production_queue.is_empty():
            var prefix = "已暂停：" if building.is_front_job_paused() else "生产中："
            return "%s%s  %d%%" % [prefix, building.queue_label(), int(building.queue_progress() * 100.0)]
    return ""

func _process_campaign_objectives():
    if str(match_config.get("kind", "skirmish")) != "campaign":
        return
    if str(match_config.get("mission_id", "")) == "training_02":
        return
    if campaign_stage == 0 and not selected_entities.is_empty():
        var has_unit_selected = false
        for entity in selected_entities:
            if is_instance_valid(entity) and entity.has_method("command_move"):
                has_unit_selected = true
        if has_unit_selected:
            campaign_stage = 1
            EventBus.objective_changed.emit("训练 2/3：越过训练线", "向地图右下方向移动部队，越过发光训练线。右键地面下达移动命令。")
            EventBus.notification_requested.emit("选择训练完成", "info")
    elif campaign_stage == 1:
        var line_x = grid.map_width * grid.tile_px * 0.42
        for unit in units:
            if is_instance_valid(unit) and unit.owner_id == 0 and unit.global_position.x > line_x:
                campaign_stage = 2
                EventBus.objective_changed.emit("训练 3/3：摧毁敌方前哨", "选中战斗单位，右键点击敌方单位或建造中心。摧毁敌方建造中心完成任务。")
                EventBus.notification_requested.emit("移动训练完成，前哨已标记", "info")
                break

func _player_alive(player_id):
    var mode_id = str(match_config.get("mode_id", "standard"))
    if mode_id == "headquarters":
        return has_building(player_id, "command")
    for entity in units + buildings:
        if is_instance_valid(entity) and entity.owner_id == player_id:
            return true
    return false

func _check_victory():
    if game_over:
        return
    var players = match_config.get("players", [])
    if players.is_empty():
        return
    if not _player_alive(0):
        _end_match(false, "我方作战力量已被摧毁")
        return
    var human_team = int(get_player_data(0).get("team", 1))
    var enemy_alive = false
    for player_id in range(1, players.size()):
        if int(get_player_data(player_id).get("team", player_id + 1)) != human_team and _player_alive(player_id):
            enemy_alive = true
            break
    if not enemy_alive:
        _end_match(true, "敌方作战力量已被清除")

func _end_match(won, reason):
    if game_over:
        return
    game_over = true
    var kind = str(match_config.get("kind", "skirmish"))
    SaveManager.record_result(kind, won, str(match_config.get("mission_id", "")))
    EventBus.match_ended.emit(0 if won else -1, reason)
    get_tree().paused = true
    _show_result_overlay(won, reason)

func _toggle_pause():
    if game_over:
        return
    if is_instance_valid(pause_layer):
        _resume_game()
        return
    VoiceManager.stop()
    CursorManager.reset()
    get_tree().paused = true
    pause_layer = _make_modal_layer("游戏已暂停", "继续指挥或返回主菜单。", "继续游戏", _resume_game)

func _resume_game():
    if is_instance_valid(pause_layer):
        pause_layer.queue_free()
    pause_layer = null
    get_tree().paused = false

func _show_result_overlay(won, reason):
    var title = "任务完成" if won else "任务失败"
    var detail = reason + "\n\n本局结果已写入本地档案。"
    pause_layer = _make_modal_layer(title, detail, "返回主菜单", _exit_after_pause)

func _make_modal_layer(title_text, detail_text, primary_text, primary_callable):
    var layer_node = CanvasLayer.new()
    layer_node.layer = 100
    layer_node.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
    add_child(layer_node)
    var shade = ColorRect.new()
    shade.color = Color(0.01, 0.015, 0.02, 0.78)
    shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    shade.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
    layer_node.add_child(shade)
    var panel = PanelContainer.new()
    panel.anchor_left = 0.5
    panel.anchor_right = 0.5
    panel.anchor_top = 0.5
    panel.anchor_bottom = 0.5
    panel.offset_left = -240
    panel.offset_right = 240
    panel.offset_top = -150
    panel.offset_bottom = 150
    panel.add_theme_stylebox_override("panel", UIFactory.panel_style(Color("#111C23"), Color("#66818D"), 6))
    panel.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
    shade.add_child(panel)
    var box = VBoxContainer.new()
    box.alignment = BoxContainer.ALIGNMENT_CENTER
    box.add_theme_constant_override("separation", 18)
    panel.add_child(box)
    var heading = UIFactory.heading(title_text, 30)
    heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    box.add_child(heading)
    var detail = UIFactory.muted_label(detail_text, 15)
    detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    box.add_child(detail)
    var primary = Button.new()
    primary.text = primary_text
    UIFactory.style_button(primary, true)
    primary.pressed.connect(primary_callable)
    box.add_child(primary)
    if not game_over:
        var settings_button = Button.new()
        settings_button.text = "设置"
        UIFactory.style_button(settings_button)
        settings_button.pressed.connect(_show_pause_settings)
        box.add_child(settings_button)
        var exit_button = Button.new()
        exit_button.text = "返回主菜单"
        UIFactory.style_button(exit_button)
        exit_button.pressed.connect(_exit_after_pause)
        box.add_child(exit_button)
    return layer_node

func _show_pause_settings():
    if is_instance_valid(pause_layer):
        pause_layer.queue_free()
    pause_layer = CanvasLayer.new()
    pause_layer.layer = 100
    pause_layer.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
    add_child(pause_layer)
    var settings_screen = SettingsMenu.new()
    settings_screen.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
    settings_screen.back_requested.connect(_return_to_pause_menu)
    pause_layer.add_child(settings_screen)

func _return_to_pause_menu():
    if is_instance_valid(pause_layer):
        pause_layer.queue_free()
    pause_layer = _make_modal_layer("游戏已暂停", "继续指挥或返回主菜单。", "继续游戏", _resume_game)

func _on_settings_applied(_settings):
    for entity in units + buildings:
        if is_instance_valid(entity):
            entity.queue_redraw()
    _clamp_camera()

func _exit_after_pause():
    get_tree().paused = false
    exit_to_menu.emit()

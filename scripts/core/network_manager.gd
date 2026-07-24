extends Node

signal discovery_updated(rooms)
signal lobby_updated(state)
signal connection_status(text)
signal match_received(config)
signal rejected(reason)

const GAME_PORT = 27888
const DISCOVERY_PORT = 27889
const PROTOCOL = "iron_meridian_lan_v1"

var enet_peer: ENetMultiplayerPeer
var udp: PacketPeerUDP
var is_host = false
var room_name = ""
var room_password = ""
var lobby_state = {}
var discovered_rooms = {}
var discovery_timer = 0.0
var advertise_timer = 0.0
var pending_profile = {}

func _ready():
    process_mode = Node.PROCESS_MODE_ALWAYS
    multiplayer.peer_connected.connect(_on_peer_connected)
    multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    multiplayer.connected_to_server.connect(_on_connected)
    multiplayer.connection_failed.connect(func(): connection_status.emit("连接失败"))
    multiplayer.server_disconnected.connect(_on_server_disconnected)

func _process(delta):
    discovery_timer += delta
    advertise_timer += delta
    _poll_udp()
    if is_host and advertise_timer >= 1.0:
        advertise_timer = 0.0
        _ensure_host_udp()
    if not is_host and is_instance_valid(udp) and discovery_timer >= 1.5:
        discovery_timer = 0.0
        _send_discovery()
    _expire_rooms()

func host_room(next_room_name, password, map_id, host_profile):
    shutdown()
    is_host = true
    room_name = next_room_name.strip_edges() if next_room_name.strip_edges() != "" else "局域网房间"
    room_password = password
    var max_players = GameConfig.maps.get(map_id, {}).get("positions", []).size()
    enet_peer = ENetMultiplayerPeer.new()
    var error = enet_peer.create_server(GAME_PORT, max(1, max_players - 1))
    if error != OK:
        connection_status.emit("创建房间失败：" + str(error))
        return false
    multiplayer.multiplayer_peer = enet_peer
    lobby_state = {
        "room_name": room_name,
        "map_id": map_id,
        "password_required": room_password != "",
        "host_id": 1,
        "slots": _make_slots(max_players, host_profile)
    }
    _ensure_host_udp()
    lobby_updated.emit(lobby_state.duplicate(true))
    connection_status.emit("房间已创建，等待玩家加入")
    return true

func _make_slots(count, host_profile):
    var slots = []
    for index in range(count):
        if index == 0:
            slots.append(_slot_from_profile("human", 1, host_profile, index))
        else:
            slots.append({"state":"open", "peer_id":0, "nickname":"开放位置", "faction":"union", "color":_default_color(index), "position":index, "team":index + 1, "difficulty":"normal"})
    return slots

func _slot_from_profile(state, peer_id, profile, index):
    return {
        "state": state,
        "peer_id": peer_id,
        "nickname": str(profile.get("nickname", "玩家")),
        "faction": str(profile.get("faction", "union")),
        "color": str(profile.get("color", _default_color(index))),
        "position": int(profile.get("position", index)),
        "team": int(profile.get("team", index + 1)),
        "difficulty": str(profile.get("difficulty", "normal"))
    }

func join_room(address, password, profile):
    shutdown()
    is_host = false
    pending_profile = profile.duplicate(true)
    pending_profile["password"] = password
    enet_peer = ENetMultiplayerPeer.new()
    var error = enet_peer.create_client(address, GAME_PORT)
    if error != OK:
        connection_status.emit("无法连接：" + str(error))
        return false
    multiplayer.multiplayer_peer = enet_peer
    connection_status.emit("正在连接 " + address)
    return true

func start_discovery():
    if is_host:
        return
    if is_instance_valid(udp):
        udp.close()
    udp = PacketPeerUDP.new()
    var error = udp.bind(0)
    if error != OK:
        connection_status.emit("局域网搜索初始化失败")
        return
    udp.set_broadcast_enabled(true)
    _send_discovery()

func _send_discovery():
    if not is_instance_valid(udp):
        return
    udp.set_dest_address("255.255.255.255", DISCOVERY_PORT)
    udp.put_packet(PROTOCOL.to_utf8_buffer())

func _ensure_host_udp():
    if is_instance_valid(udp):
        return
    udp = PacketPeerUDP.new()
    var error = udp.bind(DISCOVERY_PORT)
    if error != OK:
        connection_status.emit("房间已创建，但局域网广播端口不可用")

func _poll_udp():
    if not is_instance_valid(udp):
        return
    while udp.get_available_packet_count() > 0:
        var packet = udp.get_packet().get_string_from_utf8()
        var sender_ip = udp.get_packet_ip()
        var sender_port = udp.get_packet_port()
        if is_host and packet == PROTOCOL:
            var info = {"protocol":PROTOCOL, "name":room_name, "map_id":str(lobby_state.get("map_id", "twin_rivers")), "players":_human_count(), "capacity":lobby_state.get("slots", []).size(), "password":room_password != ""}
            udp.set_dest_address(sender_ip, sender_port)
            udp.put_packet(JSON.stringify(info).to_utf8_buffer())
        elif not is_host:
            var parsed = JSON.parse_string(packet)
            if parsed is Dictionary and str(parsed.get("protocol", "")) == PROTOCOL:
                parsed["address"] = sender_ip
                parsed["seen_at"] = Time.get_ticks_msec()
                discovered_rooms[sender_ip] = parsed
                discovery_updated.emit(discovered_rooms.values())

func _expire_rooms():
    var now = Time.get_ticks_msec()
    var changed = false
    for address in discovered_rooms.keys():
        if now - int(discovered_rooms[address].get("seen_at", 0)) > 5000:
            discovered_rooms.erase(address)
            changed = true
    if changed:
        discovery_updated.emit(discovered_rooms.values())

func _human_count():
    var count = 0
    for slot in lobby_state.get("slots", []):
        if str(slot.get("state", "")) == "human": count += 1
    return count

func _on_connected():
    connection_status.emit("已连接，正在验证房间")
    submit_profile.rpc_id(1, pending_profile)

func _on_peer_connected(peer_id):
    if is_host:
        connection_status.emit("玩家正在加入：" + str(peer_id))

func _on_peer_disconnected(peer_id):
    if not is_host:
        return
    for index in range(lobby_state.get("slots", []).size()):
        var slot = lobby_state.slots[index]
        if int(slot.get("peer_id", 0)) == peer_id:
            lobby_state.slots[index] = {"state":"open", "peer_id":0, "nickname":"开放位置", "faction":"union", "color":_default_color(index), "position":index, "team":index + 1, "difficulty":"normal"}
    _broadcast_lobby()

func _on_server_disconnected():
    connection_status.emit("与房主断开连接")
    lobby_state = {}
    lobby_updated.emit({})

@rpc("any_peer", "reliable")
func submit_profile(profile):
    if not is_host:
        return
    var peer_id = multiplayer.get_remote_sender_id()
    if str(profile.get("password", "")) != room_password:
        reject_join.rpc_id(peer_id, "房间密码错误")
        return
    var slot_index = _first_open_slot()
    if slot_index < 0:
        reject_join.rpc_id(peer_id, "房间已满")
        return
    lobby_state.slots[slot_index] = _slot_from_profile("human", peer_id, profile, slot_index)
    _broadcast_lobby()

@rpc("authority", "reliable")
func receive_lobby(state):
    lobby_state = state.duplicate(true)
    lobby_updated.emit(lobby_state.duplicate(true))

@rpc("authority", "reliable")
func reject_join(reason):
    rejected.emit(reason)
    connection_status.emit(reason)
    shutdown()

func _first_open_slot():
    for index in range(lobby_state.get("slots", []).size()):
        if str(lobby_state.slots[index].get("state", "")) == "open":
            return index
    return -1

func host_set_slot(index, patch):
    if not is_host or index <= 0 or index >= lobby_state.get("slots", []).size():
        return
    var slot = lobby_state.slots[index]
    for key in patch:
        slot[key] = patch[key]
    if str(slot.get("state", "")) == "closed":
        slot["peer_id"] = 0
        slot["nickname"] = "关闭位置"
    elif str(slot.get("state", "")) == "open":
        slot["peer_id"] = 0
        slot["nickname"] = "开放位置"
    elif str(slot.get("state", "")) == "ai":
        slot["peer_id"] = 0
        slot["nickname"] = "电脑"
    lobby_state.slots[index] = slot
    _broadcast_lobby()

func update_own_slot(patch):
    if is_host:
        _apply_peer_patch(1, patch)
    else:
        request_slot_patch.rpc_id(1, patch)

@rpc("any_peer", "reliable")
func request_slot_patch(patch):
    if is_host:
        _apply_peer_patch(multiplayer.get_remote_sender_id(), patch)

func _apply_peer_patch(peer_id, patch):
    for index in range(lobby_state.get("slots", []).size()):
        var slot = lobby_state.slots[index]
        if int(slot.get("peer_id", 0)) == peer_id:
            for key in ["nickname", "faction", "color", "position"]:
                if patch.has(key): slot[key] = patch[key]
            lobby_state.slots[index] = slot
            _broadcast_lobby()
            return

func host_start_match(base_config):
    if not is_host:
        return
    var players = []
    for slot in lobby_state.get("slots", []):
        var state = str(slot.get("state", "closed"))
        if state not in ["human", "ai"]:
            continue
        players.append({
            "controller":"human" if state == "human" else "ai",
            "nickname":slot.get("nickname", "玩家"),
            "faction":slot.get("faction", "union"),
            "color":slot.get("color", "4FA3FF"),
            "position":slot.get("position", players.size()),
            "team":slot.get("team", players.size() + 1),
            "difficulty":slot.get("difficulty", "normal"),
            "peer_id":slot.get("peer_id", 0)
        })
    base_config["players"] = players
    receive_match.rpc(base_config)

@rpc("authority", "call_local", "reliable")
func receive_match(config):
    match_received.emit(config)

func _broadcast_lobby():
    lobby_updated.emit(lobby_state.duplicate(true))
    receive_lobby.rpc(lobby_state)

func _default_color(index):
    var colors = ["4FA3FF", "E14B4B", "E1B84B", "55C271", "9D6DE3", "E78B3A", "4BD7D1", "D36BA6"]
    return colors[index % colors.size()]

func shutdown():
    if is_instance_valid(udp):
        udp.close()
    udp = null
    if multiplayer.multiplayer_peer:
        multiplayer.multiplayer_peer.close()
    multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
    enet_peer = null
    lobby_state = {}
    discovered_rooms = {}
    is_host = false

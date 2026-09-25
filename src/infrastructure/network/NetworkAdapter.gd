extends Node
class_name NetworkAdapter

signal command_received(command)
signal state_received(state)
signal event_received(event_data)
signal outbound_message(message)
signal connection_changed(connected)
signal protocol_error(reason)
signal snapshot_ack_received(player_id, tick)
signal resync_requested(player_id, reason)
signal peer_authenticated(peer_id, player_id, actor_id)
signal peer_disconnected_authenticated(peer_id, player_id, actor_id)

const NetProtocol = preload("res://src/infrastructure/network/NetProtocol.gd")
const GameCommand = preload("res://src/domain/commands/Command.gd")
const SessionConfig = preload("res://src/infrastructure/network/SessionConfig.gd")

@export var enabled: bool = false
@export_enum("offline", "client", "server") var role: String = "offline"
@export_enum("local", "enet") var transport: String = "local"
@export var host: String = "127.0.0.1"
@export var port: int = 7000
@export var max_clients: int = 10
@export var session_id: String = "local_session"
@export var player_id: String = "player"
@export var protocol_version: String = NetProtocol.PROTOCOL_VERSION
@export var log_traffic: bool = false
@export var loopback_commands: bool = true
@export var loopback_state: bool = false
@export var loopback_events: bool = false
@export var loopback_latency_ms: int = 0
@export var delta_desync_threshold: int = 4
@export var match_token: String = ""
@export var match_token_secret: String = ""
@export var match_id: String = ""
@export var local_actor_id: String = "player"

var _out_seq: int = 0
var _pending_inbound: Array[Dictionary] = []
var _peer: ENetMultiplayerPeer = null
var _is_connected: bool = false
var _owns_peer: bool = false
var _last_snapshot_tick: int = -1
var _acked_tick_by_player: Dictionary = {}
var _pending_resync_by_player: Dictionary = {}
var _auth_by_peer: Dictionary = {}
var _peer_by_player: Dictionary = {}

func _ready() -> void:
	add_to_group("network_adapter")
	_apply_cmdline_overrides()
	set_process(true)
	if not is_online():
		connection_changed.emit(false)
		return
	if transport == "enet":
		_start_enet_transport()
	else:
		_is_connected = true
		connection_changed.emit(true)

func _process(_delta: float) -> void:
	_drain_pending_inbound()

func is_online() -> bool:
	return enabled and role != "offline"

func net_is_connected() -> bool:
	return _is_connected

func send_command(command) -> void:
	if not is_online():
		return
	var payload = NetProtocol.command_to_payload(command)
	var message = _make_message("player_command", payload)
	_emit_outbound(message)

func send_state(state: Dictionary) -> void:
	if not is_online():
		return
	var message = _make_message("state_snapshot", {"state": state})
	_emit_outbound(message)

func send_state_delta(delta_state: Dictionary) -> void:
	if not is_online():
		return
	var message = _make_message("state_delta", {"state": delta_state})
	_emit_outbound(message)

func send_event(event_data: Dictionary) -> void:
	if not is_online():
		return
	var message = _make_message("game_event", {"event": event_data})
	_emit_outbound(message)

func send_lifecycle_event(msg_type: String, payload: Dictionary = {}) -> void:
	if not is_online():
		return
	var message = _make_message(msg_type, payload)
	_emit_outbound(message)

func set_connected(connected: bool) -> void:
	_is_connected = connected
	connection_changed.emit(_is_connected)

func disconnect_with_reason(reason: String = "client_disconnect") -> void:
	if not is_online():
		return
	var message = _make_message("disconnect_reason", {"reason": reason})
	_emit_outbound(message)
	_close_enet_peer()
	set_connected(false)

func push_inbound(message: Dictionary, source_peer_id: int = 0) -> void:
	var result: Dictionary = NetProtocol.validate_message(message, protocol_version)
	if not bool(result.get("ok", false)):
		var reason: String = String(result.get("error", "invalid_message"))
		protocol_error.emit(reason)
		if log_traffic:
			print("[network] drop inbound: %s" % reason)
		if role == "server" and transport == "enet" and source_peer_id > 0:
			_reject_peer(source_peer_id, reason)
		return

	var msg_type: String = String(message.get("msg_type", ""))
	var payload: Dictionary = NetProtocol.denormalize_from_transport(message.get("payload", {}))
	if role == "server" and transport == "enet" and source_peer_id > 0:
		if msg_type == "match_join":
			_authenticate_peer(source_peer_id, message, payload)
			return
		if not _validate_authenticated_sender(source_peer_id, message):
			_reject_peer(source_peer_id, "authentication_required")
			return
	elif role == "client" and msg_type == "match_join_ack":
		if bool(payload.get("accepted", false)):
			set_connected(true)
		else:
			protocol_error.emit(String(payload.get("reason", "authentication_failed")))
		return
	if log_traffic:
		print("[network] inbound %s seq=%d" % [msg_type, int(message.get("seq", -1))])

	match msg_type:
		"player_command":
			var cmd_payload: Dictionary = NetProtocol.payload_to_command_dict(payload)
			var cmd: GameCommand = GameCommand.new()
			cmd.type = int(cmd_payload.get("type", GameCommand.Type.MOVE))
			cmd.actor_id = String(cmd_payload.get("actor_id", ""))
			cmd.payload = cmd_payload.get("payload", {})
			cmd.payload["__net"] = {
				"seq": int(message.get("seq", -1)),
				"timestamp_ms": int(message.get("timestamp_ms", 0)),
				"player_id": String(message.get("player_id", "")),
				"session_id": String(message.get("session_id", "")),
				"peer_id": source_peer_id
			}
			command_received.emit(cmd)
		"state_snapshot", "state_delta":
			var state_payload: Dictionary = payload.get("state", {})
			var tick := int(state_payload.get("tick", -1))
			if msg_type == "state_delta" and _last_snapshot_tick >= 0 and tick > _last_snapshot_tick + max(delta_desync_threshold, 1):
				send_lifecycle_event("resync_request", {
					"reason": "delta_gap",
					"last_tick": _last_snapshot_tick,
					"received_tick": tick
				})
				return
			if tick >= 0:
				_last_snapshot_tick = tick
				if role == "client":
					send_lifecycle_event("state_ack", {"ack_tick": tick})
			state_received.emit(state_payload)
		"state_ack":
			var ack_tick := int(payload.get("ack_tick", -1))
			var ack_player := String(message.get("player_id", ""))
			if ack_tick >= 0 and not ack_player.is_empty():
				_acked_tick_by_player[ack_player] = ack_tick
				snapshot_ack_received.emit(ack_player, ack_tick)
		"resync_request":
			var req_player := String(message.get("player_id", ""))
			var reason := String(payload.get("reason", "requested"))
			if not req_player.is_empty():
				_pending_resync_by_player[req_player] = true
			resync_requested.emit(req_player, reason)
		"game_event", "player_died", "match_exit", "return_to_lobby":
			event_received.emit(payload)
		"disconnect_reason":
			set_connected(false)
		_:
			event_received.emit({
				"msg_type": msg_type,
				"payload": payload
			})

func _make_message(msg_type: String, payload: Dictionary = {}) -> Dictionary:
	var message: Dictionary = NetProtocol.make_message(
		msg_type,
		session_id,
		player_id,
		_out_seq,
		payload,
		protocol_version
	)
	_out_seq += 1
	return message

func _emit_outbound(message: Dictionary) -> void:
	if log_traffic:
		print("[network] outbound %s seq=%d" % [String(message.get("msg_type", "")), int(message.get("seq", -1))])
	outbound_message.emit(message)
	if transport == "enet":
		_send_over_enet(message)
		return
	if _should_loopback(String(message.get("msg_type", ""))):
		_schedule_inbound(message)

func _should_loopback(msg_type: String) -> bool:
	match msg_type:
		"player_command":
			return loopback_commands
		"state_snapshot", "state_delta":
			return loopback_state
		"game_event", "player_died", "match_exit", "return_to_lobby":
			return loopback_events
		_:
			return false

func _schedule_inbound(message: Dictionary) -> void:
	var delay: int = maxi(loopback_latency_ms, 0)
	if delay <= 0:
		push_inbound(message)
		return
	_pending_inbound.append({
		"deliver_at": Time.get_ticks_msec() + delay,
		"message": message
	})

func _drain_pending_inbound() -> void:
	if _pending_inbound.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var remaining: Array[Dictionary] = []
	for item in _pending_inbound:
		var deliver_at: int = int(item.get("deliver_at", 0))
		if deliver_at > now:
			remaining.append(item)
			continue
		push_inbound(item.get("message", {}))
	_pending_inbound = remaining

func _start_enet_transport() -> void:
	if role == "server" and (match_token_secret.is_empty() or match_id.is_empty()):
		protocol_error.emit("server_auth_not_configured" if match_token_secret.is_empty() else "server_match_not_configured")
		enabled = false
		set_connected(false)
		return
	var existing_peer: MultiplayerPeer = multiplayer.multiplayer_peer
	var existing_enet: ENetMultiplayerPeer = existing_peer as ENetMultiplayerPeer
	if existing_enet != null:
		_peer = existing_enet
		_owns_peer = false
		if log_traffic:
			print("[network] using existing ENet peer role=%s host=%s port=%d" % [role, host, port])
		_wire_multiplayer_signals()
		if role == "server":
			set_connected(true)
		else:
			set_connected(false)
		return

	if existing_peer != null:
		if log_traffic:
			print("[network] replacing non-ENet peer with ENet role=%s host=%s port=%d" % [role, host, port])
		multiplayer.multiplayer_peer = null

	_peer = ENetMultiplayerPeer.new()
	_owns_peer = true
	var err: int = ERR_CANT_CREATE
	if log_traffic:
		print("[network] start enet role=%s host=%s port=%d max_clients=%d" % [role, host, port, max_clients])
	if role == "server":
		err = _peer.create_server(port, max_clients)
	else:
		err = _peer.create_client(host, port)
	if err != OK:
		if log_traffic:
			print("[network] enet_start_failed err=%d role=%s host=%s port=%d" % [err, role, host, port])
		protocol_error.emit("enet_start_failed_%d" % err)
		enabled = false
		set_connected(false)
		return
	multiplayer.multiplayer_peer = _peer
	_wire_multiplayer_signals()
	if role == "server":
		set_connected(true)
	else:
		set_connected(false)

func _wire_multiplayer_signals() -> void:
	var on_peer_connected := Callable(self, "_on_peer_connected")
	var on_peer_disconnected := Callable(self, "_on_peer_disconnected")
	var on_connected_to_server := Callable(self, "_on_connected_to_server")
	var on_connection_failed := Callable(self, "_on_connection_failed")
	var on_server_disconnected := Callable(self, "_on_server_disconnected")
	if not multiplayer.peer_connected.is_connected(on_peer_connected):
		multiplayer.peer_connected.connect(on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(on_peer_disconnected):
		multiplayer.peer_disconnected.connect(on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(on_connected_to_server):
		multiplayer.connected_to_server.connect(on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(on_connection_failed):
		multiplayer.connection_failed.connect(on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(on_server_disconnected):
		multiplayer.server_disconnected.connect(on_server_disconnected)

func _unwire_multiplayer_signals() -> void:
	var on_peer_connected := Callable(self, "_on_peer_connected")
	var on_peer_disconnected := Callable(self, "_on_peer_disconnected")
	var on_connected_to_server := Callable(self, "_on_connected_to_server")
	var on_connection_failed := Callable(self, "_on_connection_failed")
	var on_server_disconnected := Callable(self, "_on_server_disconnected")
	if multiplayer.peer_connected.is_connected(on_peer_connected):
		multiplayer.peer_connected.disconnect(on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(on_peer_disconnected)
	if multiplayer.connected_to_server.is_connected(on_connected_to_server):
		multiplayer.connected_to_server.disconnect(on_connected_to_server)
	if multiplayer.connection_failed.is_connected(on_connection_failed):
		multiplayer.connection_failed.disconnect(on_connection_failed)
	if multiplayer.server_disconnected.is_connected(on_server_disconnected):
		multiplayer.server_disconnected.disconnect(on_server_disconnected)

func _send_over_enet(message: Dictionary) -> void:
	if _peer == null:
		return
	var msg_type: String = String(message.get("msg_type", ""))
	var reliable: bool = _is_reliable_message(msg_type)
	if role == "client":
		if reliable:
			rpc_id(1, "_rpc_receive_reliable", message)
		else:
			rpc_id(1, "_rpc_receive_unreliable", message)
		return
	for peer_id in _auth_by_peer.keys():
		if reliable:
			rpc_id(int(peer_id), "_rpc_receive_reliable", message)
		else:
			rpc_id(int(peer_id), "_rpc_receive_unreliable", message)

func _is_reliable_message(msg_type: String) -> bool:
	match msg_type:
		"player_command", "state_delta":
			return false
		_:
			return true

func get_last_acked_tick(player: String) -> int:
	return int(_acked_tick_by_player.get(player, -1))

func consume_resync_requests() -> Array[String]:
	var players: Array[String] = []
	for key in _pending_resync_by_player.keys():
		players.append(String(key))
	_pending_resync_by_player.clear()
	return players

func _on_peer_connected(peer_id: int) -> void:
	if log_traffic:
		print("[network] peer_connected %d" % peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	if log_traffic:
		print("[network] peer_disconnected %d" % peer_id)
	var auth: Dictionary = _auth_by_peer.get(peer_id, {})
	if not auth.is_empty():
		var disconnected_player := String(auth.get("player_id", ""))
		_peer_by_player.erase(disconnected_player)
		_auth_by_peer.erase(peer_id)
		_acked_tick_by_player.erase(disconnected_player)
		_pending_resync_by_player.erase(disconnected_player)
		peer_disconnected_authenticated.emit(peer_id, disconnected_player, String(auth.get("actor_id", "")))

func _on_connected_to_server() -> void:
	set_connected(false)
	var join := _make_message("match_join", {"match_token": match_token, "actor_id": local_actor_id})
	_send_over_enet(join)
	if log_traffic:
		print("[network] connected_to_server")

func _on_connection_failed() -> void:
	set_connected(false)
	protocol_error.emit("connection_failed")

func _on_server_disconnected() -> void:
	set_connected(false)
	protocol_error.emit("server_disconnected")

func _close_enet_peer() -> void:
	if _peer == null:
		return
	if _owns_peer:
		if multiplayer.multiplayer_peer == _peer:
			multiplayer.multiplayer_peer = null
		_peer.close()
	_peer = null
	_owns_peer = false

func _exit_tree() -> void:
	_unwire_multiplayer_signals()
	_close_enet_peer()

func _apply_cmdline_overrides() -> void:
	if SessionConfig.network_enabled:
		enabled = true
		role = SessionConfig.network_role
		transport = SessionConfig.transport
		host = SessionConfig.host
		port = SessionConfig.port
		max_clients = SessionConfig.max_players
		session_id = SessionConfig.session_id
		player_id = SessionConfig.player_id
		local_actor_id = SessionConfig.local_actor_id
		match_token = SessionConfig.match_token
		match_token_secret = SessionConfig.match_token_secret
		match_id = SessionConfig.match_id
		log_traffic = SessionConfig.net_log

	var env_role: String = OS.get_environment("NEON_NETWORK_ROLE")
	if env_role == "offline" or env_role == "client" or env_role == "server":
		role = env_role
		enabled = env_role != "offline"
	var env_transport: String = OS.get_environment("NEON_TRANSPORT")
	if env_transport == "local" or env_transport == "enet":
		transport = env_transport
	var env_host: String = OS.get_environment("NEON_HOST")
	if not env_host.is_empty():
		host = env_host
	var env_port: String = OS.get_environment("NEON_PORT")
	if not env_port.is_empty():
		port = int(env_port)
	var env_max_players: String = OS.get_environment("NEON_MAX_PLAYERS")
	if not env_max_players.is_empty():
		max_clients = max(int(env_max_players), 1)
	var env_session: String = OS.get_environment("NEON_SESSION_ID")
	if not env_session.is_empty():
		session_id = env_session
	var env_player: String = OS.get_environment("NEON_PLAYER_ID")
	if not env_player.is_empty():
		player_id = env_player
	var env_log: String = OS.get_environment("NEON_NET_LOG")
	if env_log == "1" or env_log.to_lower() == "true":
		log_traffic = true
	var env_match_token := OS.get_environment("NEON_MATCH_TOKEN")
	if not env_match_token.is_empty():
		match_token = env_match_token
	var env_match_secret := OS.get_environment("NEON_MATCH_TOKEN_SECRET")
	if not env_match_secret.is_empty():
		match_token_secret = env_match_secret
	var env_match_id := OS.get_environment("NEON_MATCH_ID")
	if not env_match_id.is_empty():
		match_id = env_match_id
	var env_actor_id := OS.get_environment("NEON_ACTOR_ID")
	if not env_actor_id.is_empty():
		local_actor_id = env_actor_id

	for arg in OS.get_cmdline_args():
		if arg == "--server":
			enabled = true
			role = "server"
			transport = "enet"
		elif arg == "--client":
			enabled = true
			role = "client"
		elif arg == "--net-log":
			log_traffic = true
		elif arg.begins_with("--network-role="):
			var value: String = arg.get_slice("=", 1)
			if value == "offline" or value == "client" or value == "server":
				role = value
				enabled = value != "offline"
		elif arg.begins_with("--transport="):
			var transport_value: String = arg.get_slice("=", 1)
			if transport_value == "local" or transport_value == "enet":
				transport = transport_value
		elif arg.begins_with("--host="):
			host = arg.get_slice("=", 1)
		elif arg.begins_with("--port="):
			port = int(arg.get_slice("=", 1))
		elif arg.begins_with("--max-players="):
			max_clients = max(int(arg.get_slice("=", 1)), 1)
		elif arg.begins_with("--session-id="):
			session_id = arg.get_slice("=", 1)
		elif arg.begins_with("--player-id="):
			player_id = arg.get_slice("=", 1)
		elif arg.begins_with("--match-token="):
			match_token = arg.get_slice("=", 1)
		elif arg.begins_with("--actor-id="):
			local_actor_id = arg.get_slice("=", 1)
		elif arg.begins_with("--match-id="):
			match_id = arg.get_slice("=", 1)

func _authenticate_peer(peer_id: int, message: Dictionary, payload: Dictionary) -> void:
	var claimed_player := String(message.get("player_id", "")).strip_edges()
	var claimed_session := String(message.get("session_id", "")).strip_edges()
	var claimed_actor := String(payload.get("actor_id", "")).strip_edges()
	var supplied_token := String(payload.get("match_token", ""))
	if match_token_secret.is_empty():
		_reject_peer(peer_id, "server_auth_not_configured")
		return
	var token_result := _validate_match_token(supplied_token, claimed_session, claimed_player, claimed_actor)
	if not bool(token_result.get("ok", false)):
		_reject_peer(peer_id, "invalid_match_credentials")
		return
	if _peer_by_player.has(claimed_player) or _auth_by_peer.has(peer_id):
		_reject_peer(peer_id, "identity_already_connected")
		return
	var auth := {"player_id": claimed_player, "session_id": claimed_session, "actor_id": claimed_actor}
	_auth_by_peer[peer_id] = auth
	_peer_by_player[claimed_player] = peer_id
	_send_to_peer(peer_id, _make_message("match_join_ack", {"accepted": true, "actor_id": claimed_actor}))
	peer_authenticated.emit(peer_id, claimed_player, claimed_actor)

func _validate_match_token(token: String, claimed_session: String, claimed_player: String, claimed_actor: String) -> Dictionary:
	var parts := token.split(".", false)
	if parts.size() != 2:
		return {"ok": false}
	var encoded_claims := String(parts[0])
	var supplied_signature := _decode_base64url(String(parts[1]))
	var crypto := Crypto.new()
	var expected_signature := crypto.hmac_digest(HashingContext.HASH_SHA256, match_token_secret.to_utf8_buffer(), encoded_claims.to_utf8_buffer())
	if supplied_signature.size() != expected_signature.size() or not _constant_time_equal(supplied_signature, expected_signature):
		return {"ok": false}
	var claims_text := _decode_base64url(encoded_claims).get_string_from_utf8()
	var claims = JSON.parse_string(claims_text)
	if not (claims is Dictionary):
		return {"ok": false}
	if String(claims.get("session_id", "")) != claimed_session \
		or String(claims.get("player_id", "")) != claimed_player \
		or String(claims.get("actor_id", "")) != claimed_actor:
		return {"ok": false}
	if not match_id.is_empty() and String(claims.get("match_id", "")) != match_id:
		return {"ok": false}
	if int(claims.get("expires_at_ms", 0)) < int(Time.get_unix_time_from_system() * 1000.0):
		return {"ok": false}
	return {"ok": true, "claims": claims}

func _decode_base64url(value: String) -> PackedByteArray:
	var normalized := value.replace("-", "+").replace("_", "/")
	while normalized.length() % 4 != 0:
		normalized += "="
	return Marshalls.base64_to_raw(normalized)

func _constant_time_equal(left: PackedByteArray, right: PackedByteArray) -> bool:
	if left.size() != right.size():
		return false
	var difference := 0
	for index in range(left.size()):
		difference |= left[index] ^ right[index]
	return difference == 0

func _validate_authenticated_sender(peer_id: int, message: Dictionary) -> bool:
	var auth: Dictionary = _auth_by_peer.get(peer_id, {})
	if auth.is_empty():
		return false
	if String(message.get("player_id", "")) != String(auth.get("player_id", "")) \
		or String(message.get("session_id", "")) != String(auth.get("session_id", "")):
		return false
	if String(message.get("msg_type", "")) == "player_command":
		var command_payload = message.get("payload", {})
		if not (command_payload is Dictionary) or String(command_payload.get("actor_id", "")) != String(auth.get("actor_id", "")):
			return false
	return true

func _send_to_peer(peer_id: int, message: Dictionary) -> void:
	rpc_id(peer_id, "_rpc_receive_reliable", message)

func _reject_peer(peer_id: int, reason: String) -> void:
	protocol_error.emit(reason)
	_send_to_peer(peer_id, _make_message("match_join_ack", {"accepted": false, "reason": reason}))
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_reliable(message: Dictionary) -> void:
	push_inbound(message, multiplayer.get_remote_sender_id())

@rpc("any_peer", "call_remote", "unreliable")
func _rpc_receive_unreliable(message: Dictionary) -> void:
	push_inbound(message, multiplayer.get_remote_sender_id())

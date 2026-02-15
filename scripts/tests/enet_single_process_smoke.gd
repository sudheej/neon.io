extends SceneTree

const NetworkAdapter = preload("res://src/infrastructure/network/NetworkAdapter.gd")
const GameCommand = preload("res://src/domain/commands/Command.gd")

const HOST: String = "127.0.0.1"
const PORT: int = 7030

var _server_received: bool = false
var _client_connected: bool = false
var _client_received_delta: bool = false
var _server_received_ack: bool = false
var _server_received_resync: bool = false

func _initialize() -> void:
	var root := Node.new()
	root.name = "SmokeRoot"
	get_root().add_child(root)

	var server_root := Node.new()
	server_root.name = "ServerRoot"
	root.add_child(server_root)
	var client_root := Node.new()
	client_root.name = "ClientRoot"
	root.add_child(client_root)

	var server_mp := SceneMultiplayer.new()
	set_multiplayer(server_mp, NodePath("/root/SmokeRoot/ServerRoot"))
	var server_peer := ENetMultiplayerPeer.new()
	var server_err := server_peer.create_server(PORT, 2)
	if server_err != OK:
		push_error("enet_single_process_smoke server create failed: %d" % server_err)
		quit(1)
		return
	server_mp.multiplayer_peer = server_peer

	var client_mp := SceneMultiplayer.new()
	set_multiplayer(client_mp, NodePath("/root/SmokeRoot/ClientRoot"))
	var client_peer := ENetMultiplayerPeer.new()
	var client_err := client_peer.create_client(HOST, PORT)
	if client_err != OK:
		push_error("enet_single_process_smoke client create failed: %d" % client_err)
		quit(1)
		return
	client_mp.multiplayer_peer = client_peer

	var server_adapter := NetworkAdapter.new()
	server_adapter.name = "Adapter"
	server_adapter.enabled = true
	server_adapter.role = "server"
	server_adapter.transport = "enet"
	server_adapter.player_id = "server"
	server_root.add_child(server_adapter)

	var client_adapter := NetworkAdapter.new()
	client_adapter.name = "Adapter"
	client_adapter.enabled = true
	client_adapter.role = "client"
	client_adapter.transport = "enet"
	client_adapter.player_id = "smoke_client"
	client_adapter.session_id = "smoke_session"
	client_root.add_child(client_adapter)

	server_adapter.command_received.connect(_on_server_command_received)
	server_adapter.snapshot_ack_received.connect(_on_server_snapshot_ack_received)
	server_adapter.resync_requested.connect(_on_server_resync_requested)
	client_adapter.connection_changed.connect(_on_client_connection_changed)
	client_adapter.state_received.connect(_on_client_state_received)

	if not await _wait_until_connected(3.0):
		push_error("enet_single_process_smoke client did not connect")
		quit(1)
		return

	for _i in range(6):
		client_adapter.send_command(GameCommand.move("smoke_client_actor", Vector2.RIGHT))
		await create_timer(0.06).timeout

	if not await _wait_for_server_command(3.0):
		push_error("enet_single_process_smoke no command on server")
		quit(1)
		return

	server_adapter.send_state({
		"tick": 1,
		"data": {
			"time": 1.0,
			"actors": [{
				"id": "smoke_client_actor",
				"position": {"x": 0.0, "y": 0.0},
				"health": 40.0,
				"max_health": 40.0,
				"is_ai": false
			}]
		}
	})
	await create_timer(0.08).timeout
	server_adapter.send_state_delta({
		"tick": 2,
		"base_tick": 1,
		"data": {
			"time": 1.1,
			"actors_upsert": [{
				"id": "smoke_client_actor",
				"position": {"x": 2.0, "y": 0.0}
			}]
		}
	})

	if not await _wait_for_client_delta(3.0):
		push_error("enet_single_process_smoke no delta on client")
		quit(1)
		return

	if not await _wait_for_server_ack(3.0):
		push_error("enet_single_process_smoke no state_ack on server")
		quit(1)
		return

	server_adapter.send_state_delta({
		"tick": 20,
		"base_tick": 2,
		"data": {
			"time": 1.2
		}
	})

	if not await _wait_for_server_resync(3.0):
		push_error("enet_single_process_smoke no resync_request on server")
		quit(1)
		return

	print("[enet_single_process_smoke] PASS")
	quit(0)

func _on_server_command_received(command) -> void:
	if command == null:
		return
	if String(command.actor_id) == "smoke_client_actor":
		_server_received = true

func _on_client_connection_changed(connected: bool) -> void:
	if connected:
		_client_connected = true

func _on_client_state_received(state: Dictionary) -> void:
	if int(state.get("tick", -1)) == 2:
		_client_received_delta = true

func _on_server_snapshot_ack_received(player_id: String, tick: int) -> void:
	if player_id == "smoke_client" and tick == 2:
		_server_received_ack = true

func _on_server_resync_requested(player_id: String, reason: String) -> void:
	if player_id == "smoke_client" and reason == "delta_gap":
		_server_received_resync = true

func _wait_until_connected(timeout_sec: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_sec:
		if _client_connected:
			return true
		await create_timer(0.05).timeout
		elapsed += 0.05
	return false

func _wait_for_server_command(timeout_sec: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_sec:
		if _server_received:
			return true
		await create_timer(0.05).timeout
		elapsed += 0.05
	return false

func _wait_for_client_delta(timeout_sec: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_sec:
		if _client_received_delta:
			return true
		await create_timer(0.05).timeout
		elapsed += 0.05
	return false

func _wait_for_server_ack(timeout_sec: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_sec:
		if _server_received_ack:
			return true
		await create_timer(0.05).timeout
		elapsed += 0.05
	return false

func _wait_for_server_resync(timeout_sec: float) -> bool:
	var elapsed := 0.0
	while elapsed < timeout_sec:
		if _server_received_resync:
			return true
		await create_timer(0.05).timeout
		elapsed += 0.05
	return false

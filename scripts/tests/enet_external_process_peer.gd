extends SceneTree

const NetworkAdapter = preload("res://src/infrastructure/network/NetworkAdapter.gd")
const GameCommand = preload("res://src/domain/commands/Command.gd")

const TIMEOUT_SECONDS := 8.0
const TEST_SECRET := "external-process-test-secret-with-32-bytes"
const TEST_MATCH_ID := "external-process-match"

var _adapter: Node
var _role := ""
var _expected_failure := false
var _received_command := false
var _received_snapshot := false
var _received_delta := false
var _received_ack := false
var _finished := false


func _initialize() -> void:
	_role = OS.get_environment("NEON_TEST_ROLE")
	_expected_failure = OS.get_environment("NEON_TEST_EXPECT_FAILURE") == "1"
	if _role != "server" and _role != "client":
		_fail("NEON_TEST_ROLE must be server or client")
		return

	var harness := Node.new()
	harness.name = "ExternalProcessHarness"
	get_root().add_child(harness)

	_adapter = NetworkAdapter.new()
	_adapter.name = "Adapter"
	_adapter.enabled = true
	_adapter.role = _role
	_adapter.transport = "enet"
	_adapter.host = "127.0.0.1"
	_adapter.port = int(OS.get_environment("NEON_PORT"))
	_adapter.session_id = "external_process_session"
	_adapter.player_id = "server" if _role == "server" else "external_client"
	_adapter.match_id = TEST_MATCH_ID
	if _role == "server":
		_adapter.match_token_secret = TEST_SECRET
	else:
		_adapter.local_actor_id = "external_actor"
		_adapter.match_token = _make_test_token()
	_adapter.log_traffic = true

	_adapter.protocol_error.connect(_on_protocol_error)
	_adapter.connection_changed.connect(_on_connection_changed)
	_adapter.command_received.connect(_on_command_received)
	_adapter.state_received.connect(_on_state_received)
	_adapter.snapshot_ack_received.connect(_on_snapshot_ack_received)
	harness.add_child(_adapter)

	if _role == "server":
		print("[enet_external] SERVER_READY port=%d" % _adapter.port)
	else:
		print("[enet_external] CLIENT_START port=%d" % _adapter.port)
	_timeout_after_delay()


func _make_test_token() -> String:
	var claims := {
		"match_id": TEST_MATCH_ID,
		"session_id": "external_process_session",
		"player_id": "external_client",
		"actor_id": "external_actor",
		"expires_at_ms": int(Time.get_unix_time_from_system() * 1000.0) + 60000
	}
	var encoded_claims := Marshalls.raw_to_base64(JSON.stringify(claims).to_utf8_buffer()).replace("+", "-").replace("/", "_").trim_suffix("=")
	var signature := Crypto.new().hmac_digest(HashingContext.HASH_SHA256, TEST_SECRET.to_utf8_buffer(), encoded_claims.to_utf8_buffer())
	var encoded_signature := Marshalls.raw_to_base64(signature).replace("+", "-").replace("/", "_").trim_suffix("=")
	return "%s.%s" % [encoded_claims, encoded_signature]


func _timeout_after_delay() -> void:
	await create_timer(TIMEOUT_SECONDS).timeout
	if not _finished:
		_fail("timed out role=%s" % _role)


func _on_connection_changed(connected: bool) -> void:
	if _role != "client" or not connected:
		return
	print("[enet_external] CLIENT_CONNECTED")
	for index in range(4):
		_adapter.send_command(GameCommand.move("external_actor", Vector2(1.0, float(index))))


func _on_command_received(command) -> void:
	if _role != "server" or command == null or String(command.actor_id) != "external_actor":
		return
	if _received_command:
		return
	_received_command = true
	print("[enet_external] SERVER_COMMAND_RECEIVED")
	_adapter.send_state({
		"tick": 1,
		"data": {
			"time": 1.0,
			"actors": [{
				"id": "external_actor",
				"position": {"x": 10.0, "y": 20.0},
				"health": 40.0,
				"max_health": 40.0,
				"is_ai": false
			}]
		}
	})
	await create_timer(0.1).timeout
	_adapter.send_state_delta({
		"tick": 2,
		"base_tick": 1,
		"data": {
			"time": 1.1,
			"actors_upsert": [{
				"id": "external_actor",
				"position": {"x": 12.0, "y": 20.0}
			}]
		}
	})


func _on_state_received(state: Dictionary) -> void:
	if _role != "client":
		return
	var tick := int(state.get("tick", -1))
	var data = state.get("data", {})
	if not (data is Dictionary):
		_fail("state data was not a dictionary")
		return
	if tick == 1:
		var actors = data.get("actors", [])
		if not (actors is Array) or actors.size() != 1 or String(actors[0].get("id", "")) != "external_actor":
			_fail("snapshot actor payload was invalid")
			return
		_received_snapshot = true
		print("[enet_external] CLIENT_SNAPSHOT_RECEIVED")
	elif tick == 2:
		if not _received_snapshot or int(state.get("base_tick", -1)) != 1:
			_fail("delta arrived without its expected base snapshot")
			return
		var actors_upsert = data.get("actors_upsert", [])
		if not (actors_upsert is Array) or actors_upsert.size() != 1:
			_fail("delta actor payload was invalid")
			return
		_received_delta = true
		print("[enet_external] CLIENT_DELTA_RECEIVED")
		_finish_client_after_ack_delivery()


func _finish_client_after_ack_delivery() -> void:
	await create_timer(0.35).timeout
	if not _received_delta:
		_fail("client did not receive the delta")
		return
	_pass("CLIENT_PASS")


func _on_snapshot_ack_received(player_id: String, tick: int) -> void:
	if _role != "server" or player_id != "external_client" or tick != 2:
		return
	_received_ack = true
	print("[enet_external] SERVER_ACK_RECEIVED")
	await create_timer(0.45).timeout
	if _received_command and _received_ack:
		_pass("SERVER_PASS")


func _on_protocol_error(reason: String) -> void:
	if _expected_failure and (reason == "connection_failed" or reason.begins_with("enet_start_failed_")):
		_pass("EXPECTED_TRANSPORT_FAILURE_PASS")
		return
	if not _finished:
		_fail("protocol error: %s" % reason)


func _pass(marker: String) -> void:
	if _finished:
		return
	_finished = true
	print("[enet_external] %s" % marker)
	quit(0)


func _fail(reason: String) -> void:
	if _finished:
		return
	_finished = true
	push_error("[enet_external] FAIL: %s" % reason)
	quit(1)

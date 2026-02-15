extends Node2D

const SessionConfig = preload("res://src/infrastructure/network/SessionConfig.gd")

const MODES: PackedStringArray = ["offline_ai", "mixed", "human_only"]

@export var lobby_base_url: String = "http://127.0.0.1:8080"
@export var queue_poll_interval: float = 1.0

var _selected_index: int = 0
var _busy: bool = false
var _polling: bool = false
var _poll_timer: float = 0.0
var _status_line: String = "Idle"
var _session_id: String = ""
var _player_id: String = ""

@onready var info_label: Label = $HUD/Info

func _ready() -> void:
	randomize()
	_apply_lobby_url_overrides()
	_selected_index = maxi(MODES.find(SessionConfig.selected_mode), 0)
	_session_id = _build_session_id()
	_player_id = _build_player_id()
	if SessionConfig.requeue_on_lobby_entry and _current_mode() != "offline_ai":
		SessionConfig.requeue_on_lobby_entry = false
		_start_queue_flow()
	else:
		_update_label()

func _process(delta: float) -> void:
	if not _polling or _busy:
		return
	_poll_timer -= delta
	if _poll_timer > 0.0:
		return
	_poll_timer = queue_poll_interval
	_poll_queue_status()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.keycode == KEY_1:
			_select_mode(0)
		elif key_event.keycode == KEY_2:
			_select_mode(1)
		elif key_event.keycode == KEY_3:
			_select_mode(2)
		elif key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER:
			_start_queue_flow()

func _select_mode(index: int) -> void:
	if _busy or _polling:
		return
	_selected_index = clampi(index, 0, MODES.size() - 1)
	_update_label()

func _start_queue_flow() -> void:
	if _busy:
		return
	var mode_name := _current_mode()
	if mode_name == "offline_ai":
		SessionConfig.configure_offline(mode_name)
		SessionConfig.requeue_on_lobby_entry = false
		get_tree().change_scene_to_file("res://scenes/World.tscn")
		return
	_queue_online_mode(mode_name)

func _queue_online_mode(mode_name: String) -> void:
	_busy = true
	_status_line = "Connecting lobby..."
	_update_label()

	var hello_resp := await _hello()
	if not _is_http_ok(hello_resp):
		_set_error("Lobby hello failed: %s" % _request_error_text(hello_resp))
		return

	var auth_resp := await _auth()
	if not _is_http_ok(auth_resp) or not bool(auth_resp.get("ok", false)):
		_set_error("Auth failed: %s" % _request_error_text(auth_resp))
		return

	var join_response := await _post_json("/v1/queue/join", {
		"session_id": _session_id,
		"player_id": _player_id,
		"mode": mode_name
	})
	if join_response.is_empty():
		_set_error("Queue join failed")
		return
	if int(join_response.get("_http_code", 200)) >= 400:
		var retry_ms = int(join_response.get("retry_in_ms", 0))
		if String(join_response.get("error", "")) == "queue_join_cooldown" and retry_ms > 0:
			_set_error("Queue cooldown (%0.1fs)" % (float(retry_ms) / 1000.0))
		else:
			_set_error("Queue join failed")
		return

	_busy = false
	if _handle_queue_response(join_response):
		return
	_status_line = "Queued"
	_polling = true
	_poll_timer = queue_poll_interval
	_update_label()

func _poll_queue_status() -> void:
	if _busy:
		return
	_busy = true
	var mode_name := _current_mode()
	var query := "/v1/queue/status?session_id=%s&mode=%s" % [_session_id, mode_name]
	var payload := await _get_json(query)
	_busy = false
	if payload.is_empty() or int(payload.get("_http_code", 500)) >= 400:
		_status_line = "Queue status error: %s" % _request_error_text(payload)
		_update_label()
		return
	_handle_queue_response(payload)

func _hello() -> Dictionary:
	return await _post_json("/v1/hello", {
		"session_id": _session_id,
		"player_id": _player_id
	})

func _auth() -> Dictionary:
	return await _post_json("/v1/auth", {
		"session_id": _session_id,
		"player_id": _player_id
	})

func _handle_queue_response(payload: Dictionary) -> bool:
	if String(payload.get("msg_type", "")) == "match_assigned":
		_polling = false
		_join_assigned_match(payload)
		return true
	var position := int(payload.get("position", 0))
	var qsize := int(payload.get("queue_size", 0))
	var eta_bucket := String(payload.get("eta_bucket", ""))
	if eta_bucket.is_empty():
		_status_line = "Queued: pos=%d size=%d" % [position, qsize]
	else:
		_status_line = "Queued: pos=%d size=%d eta=%s" % [position, qsize, eta_bucket]
	_update_label()
	return false

func _join_assigned_match(payload: Dictionary) -> void:
	var endpoint := String(payload.get("endpoint", "127.0.0.1:7000"))
	var host := endpoint
	var port := 7000
	if endpoint.contains(":"):
		host = endpoint.get_slice(":", 0)
		port = int(endpoint.get_slice(":", 1))
	SessionConfig.configure_online_client(
		_current_mode(),
		host,
		port,
		_session_id,
		_player_id,
		String(payload.get("match_id", "")),
		String(payload.get("match_token", ""))
	)
	SessionConfig.local_actor_id = String(payload.get("actor_id", payload.get("local_actor_id", "player")))
	SessionConfig.requeue_on_lobby_entry = false
	get_tree().change_scene_to_file("res://scenes/World.tscn")

func _post_json(path: String, payload: Dictionary) -> Dictionary:
	return await _request_json(path, HTTPClient.METHOD_POST, JSON.stringify(payload))

func _get_json(path: String) -> Dictionary:
	return await _request_json(path, HTTPClient.METHOD_GET, "")

func _request_json(path: String, method: HTTPClient.Method, body: String) -> Dictionary:
	var req := HTTPRequest.new()
	add_child(req)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := req.request(lobby_base_url + path, headers, method, body)
	if err != OK:
		req.queue_free()
		return {
			"_http_code": 0,
			"_request_error": "request_start_%d" % err
		}
	var result: Array = await req.request_completed
	req.queue_free()
	if result.size() < 4:
		return {
			"_http_code": 0,
			"_request_error": "invalid_http_response"
		}
	var request_result := int(result[0])
	var code := int(result[1])
	var body_bytes: PackedByteArray = result[3]
	var parsed: Dictionary = {}
	if not body_bytes.is_empty():
		var json_val = JSON.parse_string(body_bytes.get_string_from_utf8())
		if json_val is Dictionary:
			parsed = json_val
	parsed["_request_result"] = request_result
	parsed["_http_code"] = code
	if request_result != HTTPRequest.RESULT_SUCCESS and not parsed.has("_request_error"):
		parsed["_request_error"] = _http_request_result_name(request_result)
	return parsed

func _apply_lobby_url_overrides() -> void:
	var env_url := OS.get_environment("NEON_LOBBY_URL")
	if not env_url.is_empty():
		lobby_base_url = env_url
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--lobby-url="):
			lobby_base_url = arg.get_slice("=", 1)

func _is_http_ok(data: Dictionary) -> bool:
	var code := int(data.get("_http_code", 0))
	return code >= 200 and code < 300

func _request_error_text(payload: Dictionary) -> String:
	if payload.is_empty():
		return "empty response"
	var request_error := String(payload.get("_request_error", ""))
	if not request_error.is_empty():
		return request_error
	var code := int(payload.get("_http_code", 0))
	if code > 0:
		var server_error := String(payload.get("error", ""))
		if not server_error.is_empty():
			return "http_%d (%s)" % [code, server_error]
		return "http_%d" % code
	return "request_failed"

func _http_request_result_name(result_code: int) -> String:
	match result_code:
		HTTPRequest.RESULT_SUCCESS:
			return "success"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "cant_resolve"
		HTTPRequest.RESULT_CANT_CONNECT:
			return "cant_connect"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "connection_error"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "tls_handshake_error"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "no_response"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "body_size_limit_exceeded"
		HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED:
			return "body_decompress_failed"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "request_failed"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
			return "download_file_cant_open"
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "download_file_write_error"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "redirect_limit_reached"
		HTTPRequest.RESULT_TIMEOUT:
			return "timeout"
		_:
			return "request_result_%d" % result_code

func _current_mode() -> String:
	return MODES[_selected_index]

func _set_error(message: String) -> void:
	_busy = false
	_polling = false
	_status_line = message
	_update_label()

func _build_session_id() -> String:
	if not SessionConfig.session_id.is_empty() and SessionConfig.session_id != "local_session":
		return SessionConfig.session_id
	return "sess_%d_%d" % [Time.get_unix_time_from_system(), randi_range(1000, 9999)]

func _build_player_id() -> String:
	if not SessionConfig.player_id.is_empty() and SessionConfig.player_id != "player":
		return SessionConfig.player_id
	return "player_%d" % randi_range(10000, 99999)

func _update_label() -> void:
	SessionConfig.selected_mode = _current_mode()
	if info_label == null:
		return
	info_label.text = "LOBBY\nMode: %s\n[1] offline_ai  [2] mixed  [3] human_only\nEnter: queue/start\n%s" % [
		SessionConfig.selected_mode,
		_status_line
	]

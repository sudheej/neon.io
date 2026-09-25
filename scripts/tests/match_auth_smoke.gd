extends SceneTree

const NetworkAdapter = preload("res://src/infrastructure/network/NetworkAdapter.gd")

func _initialize() -> void:
	var adapter := NetworkAdapter.new()
	adapter.match_token_secret = "test-secret"
	adapter.match_id = "m1"
	var valid := _token("s1", "p1", "m1", "a1", int(Time.get_unix_time_from_system() * 1000.0) + 60000)
	if not bool(adapter.call("_validate_match_token", valid, "s1", "p1", "a1").get("ok", false)):
		return _fail("valid signed token rejected")
	if bool(adapter.call("_validate_match_token", valid, "s1", "p2", "a1").get("ok", false)):
		return _fail("player claim substitution accepted")
	if bool(adapter.call("_validate_match_token", valid, "s1", "p1", "other").get("ok", false)):
		return _fail("actor claim substitution accepted")
	if bool(adapter.call("_validate_match_token", valid + "x", "s1", "p1", "a1").get("ok", false)):
		return _fail("invalid signature accepted")
	var expired := _token("s1", "p1", "m1", "a1", 1)
	if bool(adapter.call("_validate_match_token", expired, "s1", "p1", "a1").get("ok", false)):
		return _fail("expired token accepted")
	adapter.set("_auth_by_peer", {7: {"player_id": "p1", "session_id": "s1", "actor_id": "a1"}})
	var command := {"msg_type": "player_command", "player_id": "p1", "session_id": "s1", "payload": {"actor_id": "a1"}}
	if not bool(adapter.call("_validate_authenticated_sender", 7, command)):
		return _fail("bound peer identity rejected")
	command["payload"]["actor_id"] = "a2"
	if bool(adapter.call("_validate_authenticated_sender", 7, command)):
		return _fail("peer actor spoof accepted")
	print("[match_auth_smoke] PASS")
	adapter.free()
	quit(0)

func _token(session: String, player: String, target_match: String, actor: String, expiry: int) -> String:
	var claims := JSON.stringify({"actor_id": actor, "expires_at_ms": expiry, "match_id": target_match, "player_id": player, "session_id": session})
	var encoded := _b64url(claims.to_utf8_buffer())
	var signature := Crypto.new().hmac_digest(HashingContext.HASH_SHA256, "test-secret".to_utf8_buffer(), encoded.to_utf8_buffer())
	return "%s.%s" % [encoded, _b64url(signature)]

func _b64url(value: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(value).replace("+", "-").replace("/", "_").trim_suffix("=")

func _fail(reason: String) -> void:
	push_error("match_auth_smoke failed: %s" % reason)
	quit(1)

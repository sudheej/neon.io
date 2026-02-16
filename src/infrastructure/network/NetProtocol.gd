extends RefCounted
class_name NetProtocol

const PROTOCOL_VERSION: String = "net.v1"

const MESSAGE_TYPES: PackedStringArray = [
	"hello",
	"auth",
	"queue_join",
	"queue_leave",
	"queue_status",
	"match_assigned",
	"match_join",
	"match_join_ack",
	"player_command",
	"state_snapshot",
	"state_delta",
	"state_ack",
	"resync_request",
	"game_event",
	"player_died",
	"match_exit",
	"return_to_lobby",
	"heartbeat",
	"disconnect_reason",
	"error"
]

const REQUIRED_FIELDS: PackedStringArray = [
	"msg_type",
	"protocol_version",
	"session_id",
	"player_id",
	"timestamp_ms",
	"seq"
]

static func now_ms() -> int:
	return Time.get_ticks_msec()

static func is_valid_msg_type(msg_type: String) -> bool:
	return MESSAGE_TYPES.has(msg_type)

static func make_message(
	msg_type: String,
	session_id: String,
	player_id: String,
	seq: int,
	payload: Dictionary = {},
	protocol_version: String = PROTOCOL_VERSION
) -> Dictionary:
	return {
		"msg_type": msg_type,
		"protocol_version": protocol_version,
		"session_id": session_id,
		"player_id": player_id,
		"timestamp_ms": now_ms(),
		"seq": max(seq, 0),
		"payload": normalize_for_transport(payload)
	}

static func validate_message(message: Dictionary, expected_protocol: String = PROTOCOL_VERSION) -> Dictionary:
	if message.is_empty():
		return {"ok": false, "error": "empty_message"}
	for field_name in REQUIRED_FIELDS:
		if not message.has(field_name):
			return {"ok": false, "error": "missing_%s" % field_name}

	var msg_type := String(message.get("msg_type", ""))
	if not is_valid_msg_type(msg_type):
		return {"ok": false, "error": "unknown_msg_type"}

	var protocol_version := String(message.get("protocol_version", ""))
	if protocol_version != expected_protocol:
		return {"ok": false, "error": "protocol_mismatch"}

	if typeof(message.get("payload", {})) != TYPE_DICTIONARY:
		return {"ok": false, "error": "payload_not_dictionary"}

	return {"ok": true}

static func command_to_payload(command) -> Dictionary:
	if command == null:
		return {}
	if command is Dictionary:
		var data := command as Dictionary
		return normalize_for_transport({
			"type": int(data.get("type", 0)),
			"actor_id": String(data.get("actor_id", "")),
			"payload": normalize_for_transport(data.get("payload", {}))
		})
	if command.has_method("to_dict"):
		return normalize_for_transport(command.to_dict())
	if command.has_method("get"):
		return normalize_for_transport({
			"type": int(command.type),
			"actor_id": String(command.actor_id),
			"payload": command.payload
		})
	return {}

static func payload_to_command_dict(payload: Dictionary) -> Dictionary:
	return {
		"type": int(payload.get("type", 0)),
		"actor_id": String(payload.get("actor_id", "")),
		"payload": denormalize_from_transport(payload.get("payload", {}))
	}

static func normalize_for_transport(value):
	var value_type := typeof(value)
	match value_type:
		TYPE_VECTOR2:
			return {"x": value.x, "y": value.y}
		TYPE_VECTOR2I:
			return {"x": value.x, "y": value.y}
		TYPE_DICTIONARY:
			var out: Dictionary = {}
			for key in value.keys():
				out[key] = normalize_for_transport(value[key])
			return out
		TYPE_ARRAY:
			var out_arr: Array = []
			for item in value:
				out_arr.append(normalize_for_transport(item))
			return out_arr
		_:
			return value

static func denormalize_from_transport(value):
	if typeof(value) == TYPE_DICTIONARY:
		var dict_val := value as Dictionary
		var keys := dict_val.keys()
		if keys.size() == 2 and dict_val.has("x") and dict_val.has("y"):
			var x = dict_val.get("x")
			var y = dict_val.get("y")
			if typeof(x) == TYPE_INT and typeof(y) == TYPE_INT:
				return Vector2i(int(x), int(y))
			if _is_number(x) and _is_number(y):
				return Vector2(float(x), float(y))
		var out: Dictionary = {}
		for key in keys:
			out[key] = denormalize_from_transport(dict_val[key])
		return out
	if typeof(value) == TYPE_ARRAY:
		var out_arr: Array = []
		for item in value:
			out_arr.append(denormalize_from_transport(item))
		return out_arr
	return value

static func _is_number(value) -> bool:
	var t := typeof(value)
	return t == TYPE_FLOAT or t == TYPE_INT

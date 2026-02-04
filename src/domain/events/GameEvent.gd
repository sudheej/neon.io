extends Resource
class_name GameEvent

@export var event_type: String = ""
@export var actor_id: String = ""
@export var payload: Dictionary = {}
@export var timestamp: float = 0.0

static func create(type_name: String, actor: String = "", data: Dictionary = {}) -> GameEvent:
	var evt = (load("res://src/domain/events/GameEvent.gd") as Script).new()
	evt.event_type = type_name
	evt.actor_id = actor
	evt.payload = data
	evt.timestamp = Time.get_ticks_msec() / 1000.0
	return evt

func to_dict() -> Dictionary:
	return {
		"event_type": event_type,
		"actor_id": actor_id,
		"payload": payload,
		"timestamp": timestamp
	}

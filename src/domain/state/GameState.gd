extends Resource
class_name GameState

@export var tick: int = 0
@export var data: Dictionary = {}

static func build(snapshot: Dictionary, tick_value: int) -> GameState:
	var state = (load("res://src/domain/state/GameState.gd") as Script).new()
	state.data = snapshot
	state.tick = tick_value
	return state

func to_dict() -> Dictionary:
	return {"tick": tick, "data": data}

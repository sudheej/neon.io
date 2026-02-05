extends Resource
class_name GameCommand

enum Type {
	MOVE,
	TOGGLE_EXPAND,
	PLACE_CELL,
	SELECT_WEAPON,
	SELECT_NEXT_SLOT,
	SELECT_PREV_SLOT,
	TOGGLE_RANGE,
	RESTART
}

@export var type: int = Type.MOVE
@export var actor_id: String = ""
@export var payload: Dictionary = {}

static func move(actor: String, dir: Vector2) -> GameCommand:
	var cmd = (load("res://src/domain/commands/Command.gd") as Script).new()
	cmd.type = Type.MOVE
	cmd.actor_id = actor
	cmd.payload = {"dir": dir}
	return cmd

static func toggle_expand(actor: String) -> GameCommand:
	var cmd = (load("res://src/domain/commands/Command.gd") as Script).new()
	cmd.type = Type.TOGGLE_EXPAND
	cmd.actor_id = actor
	return cmd

static func place_cell(actor: String, grid_pos: Vector2i) -> GameCommand:
	var cmd = (load("res://src/domain/commands/Command.gd") as Script).new()
	cmd.type = Type.PLACE_CELL
	cmd.actor_id = actor
	cmd.payload = {"grid_pos": grid_pos}
	return cmd

static func select_weapon(actor: String, weapon_type: int) -> GameCommand:
	var cmd = (load("res://src/domain/commands/Command.gd") as Script).new()
	cmd.type = Type.SELECT_WEAPON
	cmd.actor_id = actor
	cmd.payload = {"weapon_type": weapon_type}
	return cmd

static func select_next_slot(actor: String) -> GameCommand:
	var cmd = (load("res://src/domain/commands/Command.gd") as Script).new()
	cmd.type = Type.SELECT_NEXT_SLOT
	cmd.actor_id = actor
	return cmd

static func select_prev_slot(actor: String) -> GameCommand:
	var cmd = (load("res://src/domain/commands/Command.gd") as Script).new()
	cmd.type = Type.SELECT_PREV_SLOT
	cmd.actor_id = actor
	return cmd

static func toggle_range(actor: String) -> GameCommand:
	var cmd = (load("res://src/domain/commands/Command.gd") as Script).new()
	cmd.type = Type.TOGGLE_RANGE
	cmd.actor_id = actor
	return cmd

static func restart(actor: String = "") -> GameCommand:
	var cmd = (load("res://src/domain/commands/Command.gd") as Script).new()
	cmd.type = Type.RESTART
	cmd.actor_id = actor
	return cmd

func to_dict() -> Dictionary:
	return {
		"type": type,
		"actor_id": actor_id,
		"payload": payload
	}

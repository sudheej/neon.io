extends Node
class_name GameWorld

const GameCommand = preload("res://src/domain/commands/Command.gd")
const GameEvent = preload("res://src/domain/events/GameEvent.gd")
const GameState = preload("res://src/domain/state/GameState.gd")
const CommandQueue = preload("res://src/input/CommandQueue.gd")

signal event_emitted(event)
signal state_emitted(state)

@export var command_queue_path: NodePath
@export var world_path: NodePath
@export var snapshot_interval: float = 0.2

var _queue = null
var _world: Node = null
var _tick: int = 0
var _snapshot_timer: float = 0.0

func _ready() -> void:
	add_to_group("game_world")
	_queue = get_node_or_null(command_queue_path)
	_world = get_node_or_null(world_path)
	if _world == null:
		_world = get_parent()
	_set_input_disabled()
	_connect_player_events()

func _process(delta: float) -> void:
	_snapshot_timer = maxf(_snapshot_timer - delta, 0.0)
	if _snapshot_timer <= 0.0:
		_snapshot_timer = snapshot_interval
		_emit_snapshot()

func _physics_process(_delta: float) -> void:
	_apply_commands()

func submit_command(command) -> void:
	if _queue == null:
		return
	_queue.enqueue(command)

func get_command_queue():
	return _queue

func _apply_commands() -> void:
	if _queue == null:
		return
	var commands = _queue.drain()
	if commands.is_empty():
		return
	for command in commands:
		_apply_command(command)

func _apply_command(command) -> void:
	if command == null:
		return
	if not command.has_method("get"):
		return
	var cmd_type = command.type
	var actor_id = command.actor_id
	var actor = _resolve_actor(actor_id)
	match cmd_type:
		GameCommand.Type.MOVE:
			if actor != null and actor.has_method("set_move_command"):
				actor.set_move_command(command.payload.get("dir", Vector2.ZERO))
		GameCommand.Type.TOGGLE_EXPAND:
			if actor != null and actor.has_method("toggle_expand_mode"):
				actor.toggle_expand_mode()
		GameCommand.Type.PLACE_CELL:
			if actor != null and actor.has_method("try_place_cell"):
				var grid_pos = command.payload.get("grid_pos", null)
				if grid_pos != null:
					actor.try_place_cell(grid_pos)
		GameCommand.Type.SET_EXPAND_HOLD:
			if actor != null and actor.has_method("set_expand_hold"):
				var enabled = bool(command.payload.get("enabled", false))
				actor.set_expand_hold(enabled)
		GameCommand.Type.EXPAND_DIRECTION:
			if actor != null and actor.has_method("try_expand_direction"):
				var dir = command.payload.get("dir", Vector2i.ZERO)
				actor.try_expand_direction(dir)
		GameCommand.Type.SELECT_WEAPON:
			if actor != null and actor.has_method("select_weapon_and_buy"):
				var weapon_type = int(command.payload.get("weapon_type", 0))
				actor.select_weapon_and_buy(weapon_type)
		GameCommand.Type.SELECT_NEXT_SLOT:
			if actor != null and actor.has_method("select_next_slot"):
				actor.select_next_slot()
		GameCommand.Type.SELECT_PREV_SLOT:
			if actor != null and actor.has_method("select_prev_slot"):
				actor.select_prev_slot()
		GameCommand.Type.TOGGLE_RANGE:
			if actor != null and actor.has_method("toggle_range"):
				actor.toggle_range()
		GameCommand.Type.RESTART:
			_request_restart()
		_:
			pass

	emit_signal("event_emitted", GameEvent.create("command_applied", actor_id, command.to_dict()))

func _resolve_actor(actor_id: String) -> Node:
	if actor_id == "" or actor_id == "player":
		return get_tree().get_first_node_in_group("player")
	var actors = get_tree().get_nodes_in_group("combatants")
	for actor in actors:
		if actor == null:
			continue
		var id_val = actor.get("actor_id")
		if id_val != null and String(id_val) == actor_id:
			return actor
	return null

func _emit_snapshot() -> void:
	_tick += 1
	var snapshot = _build_snapshot()
	var state = GameState.build(snapshot, _tick)
	emit_signal("state_emitted", state)
	var agent_bridge = _find_agent_bridge()
	if agent_bridge != null and agent_bridge.has_method("send_state"):
		agent_bridge.send_state(state.to_dict())
	var network = _find_network_adapter()
	if network != null and network.has_method("send_state"):
		network.send_state(state.to_dict())

func _build_snapshot() -> Dictionary:
	var data: Dictionary = {}
	data["time"] = Time.get_ticks_msec() / 1000.0
	data["actors"] = []
	var actors = get_tree().get_nodes_in_group("combatants")
	for actor in actors:
		var node = actor as Node2D
		if node == null:
			continue
		var pos = node.global_position
		var actor_data: Dictionary = {
			"id": String(node.get("actor_id")),
			"position": {"x": pos.x, "y": pos.y},
			"health": node.get("health"),
			"max_health": node.get("max_health"),
			"is_ai": node.get("is_ai")
		}
		data["actors"].append(actor_data)
	return data

func _request_restart() -> void:
	if _world != null and _world.has_method("request_restart"):
		_world.request_restart()
	else:
		get_tree().reload_current_scene()

func _set_input_disabled() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("set_input_enabled"):
		player.set_input_enabled(false)
	if _world != null and _world.has_method("set"):
		_world.set("input_enabled", false)

func _connect_player_events() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player != null and player.has_signal("died"):
		player.died.connect(func(victim):
			emit_signal("event_emitted", GameEvent.create("player_died", "player", {"victim": victim}))
		)

func _find_agent_bridge() -> Node:
	var nodes = get_tree().get_nodes_in_group("agent_bridge")
	if nodes.is_empty():
		return null
	return nodes[0]

func _find_network_adapter() -> Node:
	var nodes = get_tree().get_nodes_in_group("network_adapter")
	if nodes.is_empty():
		return null
	return nodes[0]

extends Node
class_name GameWorld

const GameCommand = preload("res://src/domain/commands/Command.gd")
const GameEvent = preload("res://src/domain/events/GameEvent.gd")
const GameState = preload("res://src/domain/state/GameState.gd")
const CommandQueue = preload("res://src/input/CommandQueue.gd")

signal event_emitted(event)
signal state_emitted(state)
signal actor_registered(actor_id, actor)
signal actor_unregistered(actor_id)

@export var command_queue_path: NodePath
@export var world_path: NodePath
@export var snapshot_interval: float = 0.2
@export var enable_state_delta: bool = true
@export var full_snapshot_every_ticks: int = 5
@export var enforce_authority_checks: bool = true
@export var max_commands_per_second_per_actor: int = 30
@export var max_future_command_ms: int = 250

var _queue = null
var _world: Node = null
var _network: Node = null
var _tick: int = 0
var _snapshot_timer: float = 0.0
var _actor_registry: Dictionary = {}
var _owner_by_actor: Dictionary = {}
var _last_seq_by_actor: Dictionary = {}
var _rate_window_by_actor: Dictionary = {}
var _acked_tick_by_player: Dictionary = {}
var _last_network_snapshot_data: Dictionary = {}
var _last_network_snapshot_tick: int = -1
var _force_full_snapshot_once: bool = true

func _ready() -> void:
	add_to_group("game_world")
	_queue = get_node_or_null(command_queue_path)
	_world = get_node_or_null(world_path)
	if _world == null:
		_world = get_parent()
	_set_input_disabled()
	_register_existing_combatants()
	_connect_player_events()
	_connect_network()

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

func register_actor(actor_id: String, actor: Node, owner_player_id: String = "") -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	var resolved_actor_id := actor_id
	if resolved_actor_id.is_empty():
		resolved_actor_id = String(actor.get("actor_id"))
	if resolved_actor_id.is_empty():
		return false
	_actor_registry[resolved_actor_id] = weakref(actor)
	if not owner_player_id.is_empty():
		_owner_by_actor[resolved_actor_id] = owner_player_id
	actor_registered.emit(resolved_actor_id, actor)
	return true

func unregister_actor(actor_id: String) -> void:
	if actor_id.is_empty():
		return
	_actor_registry.erase(actor_id)
	_owner_by_actor.erase(actor_id)
	_last_seq_by_actor.erase(actor_id)
	_rate_window_by_actor.erase(actor_id)
	actor_unregistered.emit(actor_id)

func register_combatant(actor: Node, owner_player_id: String = "") -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	return register_actor(String(actor.get("actor_id")), actor, owner_player_id)

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
	if not _validate_command(command):
		return
	var cmd_type = command.type
	var actor_id = command.actor_id
	var actor = _resolve_actor(actor_id)
	if actor == null:
		actor = _maybe_spawn_network_actor(command)
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

func _validate_command(command) -> bool:
	if not enforce_authority_checks:
		return true
	var payload = command.payload if command.payload is Dictionary else {}
	if not payload.has("__net"):
		return true
	var net_meta = payload.get("__net")
	if not (net_meta is Dictionary):
		return true
	var actor_id := String(command.actor_id)
	if actor_id.is_empty():
		return false
	var player_id := String(net_meta.get("player_id", ""))
	if player_id.is_empty():
		return false
	if not _validate_actor_owner(actor_id, player_id):
		return false
	if not _validate_timestamp_ms(int(net_meta.get("timestamp_ms", 0))):
		return false
	if not _validate_sequence(actor_id, int(net_meta.get("seq", -1))):
		return false
	if not _validate_rate_limit(actor_id):
		return false
	return true

func _validate_actor_owner(actor_id: String, player_id: String) -> bool:
	if not _owner_by_actor.has(actor_id):
		_owner_by_actor[actor_id] = player_id
		return true
	return String(_owner_by_actor[actor_id]) == player_id

func _validate_rate_limit(actor_id: String) -> bool:
	var now_ms: int = Time.get_ticks_msec()
	var bucket: Dictionary = _rate_window_by_actor.get(actor_id, {
		"window_start_ms": now_ms,
		"count": 0
	})
	var window_start_ms: int = int(bucket.get("window_start_ms", now_ms))
	var count: int = int(bucket.get("count", 0))
	if now_ms - window_start_ms >= 1000:
		window_start_ms = now_ms
		count = 0
	count += 1
	bucket["window_start_ms"] = window_start_ms
	bucket["count"] = count
	_rate_window_by_actor[actor_id] = bucket
	return count <= max(max_commands_per_second_per_actor, 1)

func _validate_sequence(actor_id: String, seq: int) -> bool:
	if seq < 0:
		return false
	var last_seq: int = int(_last_seq_by_actor.get(actor_id, -1))
	if seq <= last_seq:
		return false
	_last_seq_by_actor[actor_id] = seq
	return true

func _validate_timestamp_ms(timestamp_ms: int) -> bool:
	if timestamp_ms <= 0:
		return false
	var now_ms: int = Time.get_ticks_msec()
	if timestamp_ms > now_ms + max(max_future_command_ms, 0):
		return false
	return true

func _resolve_actor(actor_id: String) -> Node:
	if _actor_registry.has(actor_id):
		var actor_ref = _actor_registry.get(actor_id)
		if actor_ref is WeakRef:
			var node = (actor_ref as WeakRef).get_ref()
			if node != null and is_instance_valid(node):
				return node
		_actor_registry.erase(actor_id)
	if actor_id == "" or actor_id == "player":
		return get_tree().get_first_node_in_group("player")
	var actors = get_tree().get_nodes_in_group("combatants")
	for actor in actors:
		if actor == null:
			continue
		var id_val = actor.get("actor_id")
		if id_val != null and String(id_val) == actor_id:
			register_actor(actor_id, actor)
			return actor
	return null

func _register_existing_combatants() -> void:
	for actor in get_tree().get_nodes_in_group("combatants"):
		register_combatant(actor)

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
		var state_dict: Dictionary = state.to_dict()
		var should_send_full := _should_send_full_snapshot()
		if should_send_full or not network.has_method("send_state_delta"):
			network.send_state(state_dict)
		else:
			var delta_state := _build_state_delta(
				_last_network_snapshot_data,
				snapshot,
				_last_network_snapshot_tick,
				_tick
			)
			if delta_state.is_empty():
				network.send_state(state_dict)
			else:
				network.send_state_delta(delta_state)
		_last_network_snapshot_data = snapshot.duplicate(true)
		_last_network_snapshot_tick = _tick
		_force_full_snapshot_once = false

func get_last_acked_tick(player_id: String) -> int:
	if player_id.is_empty():
		return -1
	return int(_acked_tick_by_player.get(player_id, -1))

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
			"is_ai": node.get("is_ai"),
			"xp": node.get("xp")
		}
		var shape = node.get_node_or_null("PlayerShape")
		if shape != null:
			var cells_raw = shape.get("cells")
			if cells_raw is Dictionary:
				var packed_cells: Array = []
				for key in (cells_raw as Dictionary).keys():
					var grid_pos = key
					if grid_pos is Vector2i:
						var cell := grid_pos as Vector2i
						packed_cells.append({"x": cell.x, "y": cell.y})
				actor_data["cells"] = packed_cells
		var weapon_system = node.get_node_or_null("WeaponSystem")
		if weapon_system != null:
			if weapon_system.has_method("get_selected_weapon_type"):
				actor_data["selected_weapon"] = int(weapon_system.call("get_selected_weapon_type"))
			if weapon_system.has_method("get_armed_cell"):
				actor_data["armed_cell"] = weapon_system.call("get_armed_cell")
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

func _connect_network() -> void:
	_network = _find_network_adapter()
	if _network == null:
		return
	if _network.has_signal("command_received"):
		_network.connect("command_received", Callable(self, "_on_network_command"))
	if _network.has_signal("event_received"):
		_network.connect("event_received", Callable(self, "_on_network_event"))
	if _network.has_signal("snapshot_ack_received"):
		_network.connect("snapshot_ack_received", Callable(self, "_on_snapshot_ack_received"))
	if _network.has_signal("resync_requested"):
		_network.connect("resync_requested", Callable(self, "_on_resync_requested"))
	if self.has_signal("event_emitted"):
		event_emitted.connect(_on_event_emitted)

func _on_network_command(command) -> void:
	if command == null:
		return
	submit_command(command)

func _on_event_emitted(event_data) -> void:
	if _network == null or not is_instance_valid(_network):
		return
	if not _network.has_method("send_event"):
		return
	var event_dict: Dictionary = {}
	if event_data is Dictionary:
		event_dict = event_data
	elif event_data != null and event_data.has_method("to_dict"):
		event_dict = event_data.to_dict()
	_network.send_event(event_dict)

func _on_network_event(event_payload: Dictionary) -> void:
	var msg_type := String(event_payload.get("msg_type", ""))
	var payload_raw = event_payload.get("payload", {})
	var payload: Dictionary = payload_raw if payload_raw is Dictionary else {}
	if msg_type == "state_ack":
		var player_id := String(event_payload.get("player_id", ""))
		var ack_tick := int(payload.get("ack_tick", -1))
		if not player_id.is_empty() and ack_tick >= 0:
			_acked_tick_by_player[player_id] = ack_tick
	elif msg_type == "resync_request":
		_force_full_snapshot_once = true
		_emit_snapshot()

func _on_snapshot_ack_received(player_id: String, tick: int) -> void:
	if player_id.is_empty() or tick < 0:
		return
	_acked_tick_by_player[player_id] = tick

func _on_resync_requested(_player_id: String, _reason: String) -> void:
	_force_full_snapshot_once = true
	_emit_snapshot()

func _should_send_full_snapshot() -> bool:
	if not enable_state_delta:
		return true
	if _force_full_snapshot_once:
		return true
	if _last_network_snapshot_tick < 0:
		return true
	if full_snapshot_every_ticks <= 1:
		return true
	return (_tick % full_snapshot_every_ticks) == 0

func _build_state_delta(
	previous_snapshot: Dictionary,
	current_snapshot: Dictionary,
	base_tick: int,
	current_tick: int
) -> Dictionary:
	if previous_snapshot.is_empty() or base_tick < 0:
		return {}
	var previous_actors: Dictionary = _actors_by_id(previous_snapshot.get("actors", []))
	var current_actors: Dictionary = _actors_by_id(current_snapshot.get("actors", []))
	var current_ids: Array[String] = []
	for actor_id in current_actors.keys():
		current_ids.append(String(actor_id))
	current_ids.sort()
	var previous_ids: Array[String] = []
	for actor_id in previous_actors.keys():
		previous_ids.append(String(actor_id))
	previous_ids.sort()

	var upserts: Array[Dictionary] = []
	for actor_id in current_ids:
		var curr_actor: Dictionary = current_actors.get(actor_id, {})
		if not previous_actors.has(actor_id):
			upserts.append(curr_actor.duplicate(true))
			continue
		var prev_actor: Dictionary = previous_actors.get(actor_id, {})
		var actor_delta: Dictionary = {"id": actor_id}
		for field_name in ["position", "health", "max_health", "is_ai", "xp", "cells", "selected_weapon", "armed_cell"]:
			if not _values_equal(curr_actor.get(field_name), prev_actor.get(field_name)):
				actor_delta[field_name] = curr_actor.get(field_name)
		if actor_delta.size() > 1:
			upserts.append(actor_delta)

	var removes: Array[String] = []
	for actor_id in previous_ids:
		if not current_actors.has(actor_id):
			removes.append(actor_id)

	var delta_data: Dictionary = {
		"time": current_snapshot.get("time", 0.0)
	}
	if not upserts.is_empty():
		delta_data["actors_upsert"] = upserts
	if not removes.is_empty():
		delta_data["actors_remove"] = removes

	return {
		"tick": current_tick,
		"base_tick": base_tick,
		"data": delta_data
	}

func _actors_by_id(raw_actors) -> Dictionary:
	var out: Dictionary = {}
	if raw_actors is Array:
		for entry in raw_actors:
			if not (entry is Dictionary):
				continue
			var actor_data: Dictionary = entry
			var actor_id := String(actor_data.get("id", ""))
			if actor_id.is_empty():
				continue
			out[actor_id] = actor_data
	return out

func _values_equal(a, b) -> bool:
	var type_a := typeof(a)
	var type_b := typeof(b)
	if type_a != type_b:
		return false
	match type_a:
		TYPE_FLOAT:
			return is_equal_approx(float(a), float(b))
		TYPE_DICTIONARY:
			var dict_a: Dictionary = a
			var dict_b: Dictionary = b
			if dict_a.size() != dict_b.size():
				return false
			for key in dict_a.keys():
				if not dict_b.has(key):
					return false
				if not _values_equal(dict_a.get(key), dict_b.get(key)):
					return false
			return true
		TYPE_ARRAY:
			var arr_a: Array = a
			var arr_b: Array = b
			if arr_a.size() != arr_b.size():
				return false
			for i in arr_a.size():
				if not _values_equal(arr_a[i], arr_b[i]):
					return false
			return true
		_:
			return a == b

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

func _maybe_spawn_network_actor(command) -> Node:
	if command == null:
		return null
	if _world == null or not _world.has_method("spawn_network_human_actor"):
		return null
	if _network == null or not is_instance_valid(_network):
		_network = _find_network_adapter()
	if _network == null:
		return null
	if String(_network.get("role")) != "server":
		return null
	var payload = command.payload if command.payload is Dictionary else {}
	var net_meta = payload.get("__net", {})
	if not (net_meta is Dictionary):
		return null
	var actor_id := String(command.actor_id)
	var player_id := String(net_meta.get("player_id", ""))
	if actor_id.is_empty() or player_id.is_empty():
		return null
	var spawned = _world.call("spawn_network_human_actor", actor_id, player_id)
	if spawned != null and is_instance_valid(spawned):
		register_actor(actor_id, spawned, player_id)
		return spawned
	return null

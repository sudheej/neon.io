extends "res://src/input/InputSource.gd"
class_name HumanInputSource

const GameCommand = preload("res://src/domain/commands/Command.gd")
const WeaponSlot = preload("res://src/domain/weapons/WeaponSlot.gd")

@export var actor_path: NodePath

var _actor: Node = null

func _ready() -> void:
	super._ready()
	_resolve_actor()
	set_process_unhandled_input(true)
	set_physics_process(true)

func _process(_delta: float) -> void:
	if _actor == null or not is_instance_valid(_actor):
		_resolve_actor()

func _physics_process(_delta: float) -> void:
	var move = _get_move_vector()
	if move.length() > 0.0 or _actor != null:
		emit_command(GameCommand.move(actor_id, move))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("expand_mode"):
		emit_command(GameCommand.toggle_expand(actor_id))
	if event.is_action_pressed("select_next_slot"):
		emit_command(GameCommand.select_next_slot(actor_id))
	if event.is_action_pressed("select_prev_slot"):
		emit_command(GameCommand.select_prev_slot(actor_id))
	if event.is_action_pressed("toggle_range"):
		emit_command(GameCommand.toggle_range(actor_id))
	if event.is_action_pressed("weapon_laser"):
		emit_command(GameCommand.select_weapon(actor_id, WeaponSlot.WeaponType.LASER))
	if event.is_action_pressed("weapon_stun"):
		emit_command(GameCommand.select_weapon(actor_id, WeaponSlot.WeaponType.STUN))
	if event.is_action_pressed("weapon_homing"):
		emit_command(GameCommand.select_weapon(actor_id, WeaponSlot.WeaponType.HOMING))
	if event.is_action_pressed("weapon_spread"):
		emit_command(GameCommand.select_weapon(actor_id, WeaponSlot.WeaponType.SPREAD))
	if event.is_action_pressed("restart_game"):
		emit_command(GameCommand.restart(actor_id))

	if event.is_action_pressed("expand_place"):
		if _actor != null and _actor.get("expand_mode"):
			var grid_pos = _get_mouse_grid_pos()
			if grid_pos != null:
				emit_command(GameCommand.place_cell(actor_id, grid_pos))

func _get_move_vector() -> Vector2:
	var x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	return Vector2(x, y)

func _resolve_actor() -> void:
	if actor_path != NodePath(""):
		_actor = get_node_or_null(actor_path)
		return
	_actor = get_tree().get_first_node_in_group("player")

func _get_mouse_grid_pos() -> Variant:
	if _actor == null or not is_instance_valid(_actor):
		return null
	if not _actor.has_method("local_to_grid"):
		return null
	if not _actor.has_method("get_global_mouse_position"):
		return null
	var local = _actor.to_local(_actor.get_global_mouse_position())
	return _actor.local_to_grid(local)

extends "res://src/input/InputSource.gd"
class_name HumanInputSource

const GameCommand = preload("res://src/domain/commands/Command.gd")
const WeaponSlot = preload("res://src/domain/weapons/WeaponSlot.gd")
const MOVE_SEND_INTERVAL: float = 0.05
const IDLE_SEND_INTERVAL: float = 0.15
const MOVE_CHANGE_EPS: float = 0.0001

@export var actor_path: NodePath

var _actor: Node = null
var _expand_hold: bool = false
var _move_send_timer: float = 0.0
var _last_sent_move: Vector2 = Vector2(9999.0, 9999.0)

func _ready() -> void:
	super._ready()
	_resolve_actor()
	set_process_unhandled_input(true)
	set_physics_process(true)

func _process(_delta: float) -> void:
	if _actor == null or not is_instance_valid(_actor):
		_resolve_actor()

func _physics_process(_delta: float) -> void:
	_update_expand_hold()
	if _expand_hold:
		_emit_expand_direction()
	var move = _get_move_vector()
	if _expand_hold:
		move = Vector2.ZERO
	var moving := move.length_squared() > MOVE_CHANGE_EPS
	var interval := MOVE_SEND_INTERVAL if moving else IDLE_SEND_INTERVAL
	_move_send_timer -= _delta
	var changed := move.distance_squared_to(_last_sent_move) > MOVE_CHANGE_EPS
	if changed or _move_send_timer <= 0.0:
		emit_command(GameCommand.move(actor_id, move))
		_last_sent_move = move
		_move_send_timer = interval

func _unhandled_input(event: InputEvent) -> void:
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

func _update_expand_hold() -> void:
	var holding = Input.is_key_pressed(KEY_SHIFT)
	if holding == _expand_hold:
		return
	_expand_hold = holding
	emit_command(GameCommand.set_expand_hold(actor_id, _expand_hold))

func _emit_expand_direction() -> void:
	if Input.is_action_just_pressed("move_up"):
		emit_command(GameCommand.expand_direction(actor_id, Vector2i.UP))
	if Input.is_action_just_pressed("move_down"):
		emit_command(GameCommand.expand_direction(actor_id, Vector2i.DOWN))
	if Input.is_action_just_pressed("move_left"):
		emit_command(GameCommand.expand_direction(actor_id, Vector2i.LEFT))
	if Input.is_action_just_pressed("move_right"):
		emit_command(GameCommand.expand_direction(actor_id, Vector2i.RIGHT))

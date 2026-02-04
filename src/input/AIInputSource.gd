extends "res://src/input/InputSource.gd"
class_name AIInputSource

const GameCommand = preload("res://src/domain/commands/Command.gd")
const WeaponSlot = preload("res://src/domain/weapons/WeaponSlot.gd")

const SEEK_RANGE: float = 420.0
const TOO_CLOSE: float = 90.0
const DODGE_RADIUS: float = 120.0
const SEPARATION_RADIUS: float = 60.0
const RAMP_TIME: float = 120.0

var player: Node2D = null
var current_target: Node2D = null
var target_timer: float = 0.0
var profile: int = 0

enum AIProfile { BALANCED, LASER, STUNNER, HOMING, SPREADER }

func _ready() -> void:
	super._ready()
	player = get_parent() as Node2D
	if player != null and player.has_method("set_ai_enabled"):
		player.set_ai_enabled(true)
	if player != null:
		var id_val = player.get("actor_id")
		if id_val != null:
			actor_id = String(id_val)
	profile = randi() % 5

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var targets = get_tree().get_nodes_in_group("combatants")
	_update_target(player, targets, delta)
	var move = _compute_seek_vector(player, targets)
	move += _compute_separation_vector(player, targets)
	move += _compute_dodge_vector(player) * 0.6
	move *= _difficulty_scale()
	emit_command(GameCommand.move(actor_id, move))
	_maybe_pick_weapon(player, targets, delta)
	_set_preferred_target(player)

func _compute_seek_vector(owner: Node2D, targets: Array) -> Vector2:
	if current_target == null or not is_instance_valid(current_target):
		return Vector2.ZERO
	var to_target = (current_target.global_position - owner.global_position)
	var best_dist = to_target.length()
	if best_dist < TOO_CLOSE:
		var lateral = Vector2(-to_target.y, to_target.x).normalized()
		return (-to_target.normalized() + lateral * 0.6).normalized()
	return to_target.normalized()

func _compute_dodge_vector(owner: Node2D) -> Vector2:
	var dodge = Vector2.ZERO
	var projectiles = get_tree().get_nodes_in_group("projectiles")
	for p in projectiles:
		var node = p as Node2D
		if node == null:
			continue
		var to_me = owner.global_position - node.global_position
		var dist = to_me.length()
		if dist < 0.001 or dist > DODGE_RADIUS:
			continue
		dodge += to_me.normalized() * (1.0 - dist / DODGE_RADIUS)
	return dodge

func _compute_separation_vector(owner: Node2D, targets: Array) -> Vector2:
	var sep = Vector2.ZERO
	for t in targets:
		var node = t as Node2D
		if node == null or node == owner:
			continue
		var to_me = owner.global_position - node.global_position
		var dist = to_me.length()
		if dist < 0.001 or dist > SEPARATION_RADIUS:
			continue
		sep += to_me.normalized() * (1.0 - dist / SEPARATION_RADIUS)
	return sep

func _update_target(owner: Node2D, targets: Array, delta: float) -> void:
	target_timer -= delta
	if current_target != null and is_instance_valid(current_target) and target_timer > 0.0:
		return
	current_target = null
	var best_score = -1.0
	for t in targets:
		var node = t as Node2D
		if node == null or node == owner:
			continue
		var d = owner.global_position.distance_to(node.global_position)
		if d > SEEK_RANGE:
			continue
		var score = 1.0 / max(d, 1.0)
		if node.is_in_group("player"):
			score *= 0.7
		if score > best_score:
			best_score = score
			current_target = node
	target_timer = randf_range(0.8, 1.6)

func _maybe_pick_weapon(owner: Node2D, targets: Array, _delta: float) -> void:
	if not owner.has_node("WeaponSystem"):
		return
	var system = owner.get_node("WeaponSystem")
	if system == null:
		return
	var best_dist = SEEK_RANGE
	for t in targets:
		var node = t as Node2D
		if node == null or node == owner:
			continue
		var d = owner.global_position.distance_to(node.global_position)
		if d < best_dist:
			best_dist = d
	var weapon_type = system.get_selected_weapon_type()
	match profile:
		AIProfile.LASER:
			weapon_type = WeaponSlot.WeaponType.LASER
		AIProfile.STUNNER:
			if best_dist < 180.0:
				weapon_type = WeaponSlot.WeaponType.STUN
			else:
				weapon_type = WeaponSlot.WeaponType.LASER
		AIProfile.HOMING:
			if best_dist < 300.0:
				weapon_type = WeaponSlot.WeaponType.HOMING
			else:
				weapon_type = WeaponSlot.WeaponType.LASER
		AIProfile.SPREADER:
			if best_dist < 220.0:
				weapon_type = WeaponSlot.WeaponType.SPREAD
			else:
				weapon_type = WeaponSlot.WeaponType.LASER
		_:
			if best_dist < 140.0:
				weapon_type = WeaponSlot.WeaponType.STUN
			elif best_dist < 230.0:
				weapon_type = WeaponSlot.WeaponType.SPREAD
			elif best_dist < 300.0:
				weapon_type = WeaponSlot.WeaponType.HOMING
			else:
				weapon_type = WeaponSlot.WeaponType.LASER
	if system.get_weapon_ammo(weapon_type) <= 0:
		emit_command(GameCommand.select_weapon(actor_id, weapon_type))
	else:
		emit_command(GameCommand.select_weapon(actor_id, weapon_type))

func _set_preferred_target(owner: Node2D) -> void:
	if current_target == null or not is_instance_valid(current_target):
		return
	if not owner.has_node("WeaponSystem"):
		return
	var system = owner.get_node("WeaponSystem")
	if system == null:
		return
	system.set_preferred_target(current_target)

func _difficulty_scale() -> float:
	var world = get_tree().get_first_node_in_group("world")
	if world == null:
		return 0.5
	var elapsed = world.get("elapsed")
	if elapsed == null:
		return 0.5
	var t = clamp(float(elapsed) / RAMP_TIME, 0.0, 1.0)
	return lerpf(0.25, 0.7, t)

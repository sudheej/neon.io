extends "res://src/input/InputSource.gd"
class_name AIInputSource

const GameCommand = preload("res://src/domain/commands/Command.gd")
const WeaponSlot = preload("res://src/domain/weapons/WeaponSlot.gd")

const SEEK_RANGE: float = 420.0
const ORB_SEEK_RANGE: float = 320.0
const ORB_COMMIT_RANGE: float = 110.0
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
	var orb_target = _find_best_orb(player, targets)
	var move = _compute_seek_vector(player, targets)
	move += _compute_orb_seek_vector(player, orb_target, targets)
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

func _compute_orb_seek_vector(owner: Node2D, orb_target: Node2D, targets: Array) -> Vector2:
	if orb_target == null or not is_instance_valid(orb_target):
		return Vector2.ZERO
	var to_orb = orb_target.global_position - owner.global_position
	var dist = to_orb.length()
	if dist <= 0.001:
		return Vector2.ZERO
	var pressure = _enemy_pressure(owner, targets)
	var weight = 0.35 + pressure * 0.15
	if dist <= ORB_COMMIT_RANGE:
		weight = 1.0
	return to_orb.normalized() * weight

func _find_best_orb(owner: Node2D, targets: Array) -> Node2D:
	var orbs = get_tree().get_nodes_in_group("boost_orbs")
	if orbs.is_empty():
		return null
	var best: Node2D = null
	var best_score = -INF
	for o in orbs:
		var orb = o as Node2D
		if orb == null or not is_instance_valid(orb):
			continue
		if orb.has_method("is_pickable") and not bool(orb.is_pickable()):
			continue
		var dist = owner.global_position.distance_to(orb.global_position)
		if dist > ORB_SEEK_RANGE:
			continue
		var score = _score_orb(owner, orb, dist, targets)
		if score > best_score:
			best_score = score
			best = orb
	return best

func _score_orb(owner: Node2D, orb: Node2D, dist: float, targets: Array) -> float:
	if not orb.has_method("get_boost_type") or not orb.has_method("get_amount"):
		return -INF
	var boost_type = int(orb.get_boost_type())
	var amount = maxf(float(orb.get_amount()), 0.0)
	if amount <= 0.0:
		return -INF
	var proximity = 1.0 / max(dist, 18.0)
	var desirability = 0.0
	match boost_type:
		0: # XP
			var credits = float(owner.get("xp"))
			desirability = lerpf(1.35, 0.6, clampf(credits / 140.0, 0.0, 1.0))
		1: # AMMO
			desirability = _ammo_orb_desirability(owner, orb)
		2: # HEALTH
			var hp = float(owner.get("health"))
			var max_hp = maxf(float(owner.get("max_health")), 0.001)
			var missing_ratio = clampf((max_hp - hp) / max_hp, 0.0, 1.0)
			desirability = 0.4 + missing_ratio * 2.6
	var pressure = _enemy_pressure(owner, targets)
	if boost_type == 2:
		desirability += pressure * 0.9
	elif pressure > 0.7:
		desirability *= 0.75
	return amount * proximity * desirability

func _ammo_orb_desirability(owner: Node2D, orb: Node2D) -> float:
	if not owner.has_node("WeaponSystem"):
		return 0.0
	if not orb.has_method("get_weapon_type"):
		return 0.0
	var system = owner.get_node("WeaponSystem")
	var weapon_type = int(orb.get_weapon_type())
	if not system.has_method("get_weapon_ammo") or not system.has_method("get_weapon_capacity"):
		return 0.0
	var ammo = int(system.get_weapon_ammo(weapon_type))
	var cap = max(1, int(system.get_weapon_capacity(weapon_type)))
	var need = clampf(float(cap - ammo) / float(cap), 0.0, 1.0)
	if need <= 0.0:
		return 0.2
	return 0.35 + need * (1.8 + _profile_weapon_bias(weapon_type))

func _profile_weapon_bias(weapon_type: int) -> float:
	match profile:
		AIProfile.LASER:
			return 0.9 if weapon_type == WeaponSlot.WeaponType.LASER else 0.1
		AIProfile.STUNNER:
			return 0.9 if weapon_type == WeaponSlot.WeaponType.STUN else 0.15
		AIProfile.HOMING:
			return 0.9 if weapon_type == WeaponSlot.WeaponType.HOMING else 0.2
		AIProfile.SPREADER:
			return 0.9 if weapon_type == WeaponSlot.WeaponType.SPREAD else 0.2
		_:
			return 0.45 if weapon_type == WeaponSlot.WeaponType.SPREAD else 0.3

func _enemy_pressure(owner: Node2D, targets: Array) -> float:
	var closest = SEEK_RANGE
	for t in targets:
		var node = t as Node2D
		if node == null or node == owner:
			continue
		var d = owner.global_position.distance_to(node.global_position)
		if d < closest:
			closest = d
	return clampf(1.0 - (closest / SEEK_RANGE), 0.0, 1.0)

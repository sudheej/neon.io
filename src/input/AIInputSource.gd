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
const EXPAND_COST: float = 60.0
const EXPAND_BASE_INTERVAL: float = 1.9
const EXPAND_MIN_INTERVAL: float = 0.45
const EXPAND_REPOSITION_INTERVAL: float = 0.32
const EXPAND_DECISION_INTERVAL: float = 0.55
const EXPAND_EVAL_WINDOW: float = 3.2
const EXPAND_FAIL_WINDOW: float = 0.65
const EXPAND_STARTUP_EXPLORE_MIN: float = 3.2
const EXPAND_STARTUP_EXPLORE_MAX: float = 6.5
const EXPAND_STALL_FORCE_GROWTH_TIME: float = 3.5
const EXPAND_GROWTH_LOCK_ATTEMPTS: int = 2
const EXPAND_REPOSITION_BACKTRACK_MEMORY: float = 1.1
const XP_ORB_EXPAND_LOOKAHEAD_RANGE: float = 250.0
const XP_ORB_EXPAND_BONUS_CAP: float = 28.0
const CARDINAL_DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const RETREAT_HEALTH_ENTER: float = 0.38
const RETREAT_HEALTH_EXIT: float = 0.72
const RETREAT_PRESSURE_ENTER: float = 0.58
const RETREAT_PRESSURE_EXIT: float = 0.42
const RETREAT_MIN_TIME: float = 2.4
const RETREAT_MAX_TIME: float = 4.6
const RETREAT_REENGAGE_COOLDOWN: float = 2.2

static var _shared_expand_memory: Dictionary = {}

var player: Node2D = null
var current_target: Node2D = null
var target_timer: float = 0.0
var profile: int = 0
var expand_cooldown: float = 0.0
var expand_decision_timer: float = 0.0
var explore_before_expand_timer: float = 0.0
var preferred_axis: Vector2 = Vector2.RIGHT
var aggressive_expander: bool = false
var expansion_drive: float = 1.0
var pending_expand_context: String = ""
var pending_expand_dir: Vector2i = Vector2i.ZERO
var pending_expand_timer: float = 0.0
var pending_expand_before_hp: float = 0.0
var pending_expand_before_max_hp: float = 1.0
var pending_expand_before_xp: float = 0.0
var pending_expand_before_pressure: float = 0.0
var pending_expand_before_cells: int = 1
var pending_expand_requires_growth: bool = false
var growth_lock_attempts_remaining: int = 0
var no_growth_timer: float = 0.0
var last_observed_cell_count: int = 1
var last_reposition_from: Vector2i = Vector2i.ZERO
var last_reposition_to: Vector2i = Vector2i.ZERO
var last_reposition_timer: float = 0.0
var retreat_mode: bool = false
var retreat_timer: float = 0.0
var retreat_cooldown: float = 0.0

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
	aggressive_expander = _roll_aggressive_expander()
	expansion_drive = randf_range(0.85, 1.2)
	explore_before_expand_timer = randf_range(EXPAND_STARTUP_EXPLORE_MIN, EXPAND_STARTUP_EXPLORE_MAX)
	if aggressive_expander:
		explore_before_expand_timer *= 0.62
	var angle_seed := randf_range(0.0, TAU)
	preferred_axis = Vector2.RIGHT.rotated(angle_seed)

func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var targets = get_tree().get_nodes_in_group("combatants")
	var pressure = _enemy_pressure(player, targets)
	_update_target(player, targets, delta)
	var orb_target = _find_best_orb(player, targets)
	_update_retreat_state(player, pressure, delta)
	var move = Vector2.ZERO
	if retreat_mode:
		move += _compute_retreat_vector(player, targets)
	else:
		move += _compute_seek_vector(player, targets)
	var orb_weight = 1.35 if retreat_mode else 1.0
	move += _compute_orb_seek_vector(player, orb_target, targets) * orb_weight
	move += _compute_separation_vector(player, targets)
	move += _compute_dodge_vector(player) * 0.6
	move *= _difficulty_scale()
	emit_command(GameCommand.move(actor_id, move))
	_maybe_pick_weapon(player, targets, delta)
	_set_preferred_target(player)
	_maybe_expand(player, targets, orb_target, delta)

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

func _update_retreat_state(owner: Node2D, pressure: float, delta: float) -> void:
	retreat_cooldown = maxf(retreat_cooldown - delta, 0.0)
	if retreat_mode:
		retreat_timer = maxf(retreat_timer - delta, 0.0)
		var hp_ratio = _health_ratio(owner)
		if hp_ratio >= RETREAT_HEALTH_EXIT and pressure <= RETREAT_PRESSURE_EXIT and retreat_timer <= 0.0:
			retreat_mode = false
			retreat_cooldown = RETREAT_REENGAGE_COOLDOWN
		return
	if retreat_cooldown > 0.0:
		return
	var health_ratio = _health_ratio(owner)
	if health_ratio <= RETREAT_HEALTH_ENTER and pressure >= RETREAT_PRESSURE_ENTER:
		retreat_mode = true
		retreat_timer = randf_range(RETREAT_MIN_TIME, RETREAT_MAX_TIME)

func _compute_retreat_vector(owner: Node2D, targets: Array) -> Vector2:
	var nearest: Node2D = null
	var nearest_dist = INF
	var center = Vector2.ZERO
	var count = 0
	for t in targets:
		var node = t as Node2D
		if node == null or node == owner:
			continue
		var d = owner.global_position.distance_to(node.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = node
		if d <= SEEK_RANGE:
			center += node.global_position
			count += 1
	var retreat = Vector2.ZERO
	if nearest != null:
		retreat += (owner.global_position - nearest.global_position).normalized() * 0.75
	if count > 0:
		var avg_pos = center / float(count)
		retreat += (owner.global_position - avg_pos).normalized() * 0.5
	if retreat.length_squared() <= 0.0001:
		retreat = preferred_axis
	return retreat.normalized()

func _health_ratio(owner: Node2D) -> float:
	var hp = _read_stat(owner, "health", 0.0)
	var max_hp = maxf(_read_stat(owner, "max_health", 1.0), 0.001)
	return clampf(hp / max_hp, 0.0, 1.0)

func _maybe_expand(owner: Node2D, targets: Array, orb_target: Node2D, delta: float) -> void:
	_update_expand_learning(owner, targets, delta)
	explore_before_expand_timer = maxf(explore_before_expand_timer - delta, 0.0)
	expand_decision_timer = maxf(expand_decision_timer - delta, 0.0)
	expand_cooldown = maxf(expand_cooldown - delta, 0.0)
	last_reposition_timer = maxf(last_reposition_timer - delta, 0.0)
	if expand_cooldown > 0.0:
		return
	if expand_decision_timer > 0.0:
		return
	expand_decision_timer = EXPAND_DECISION_INTERVAL * randf_range(0.8, 1.35)
	var shape = owner.get_node_or_null("PlayerShape")
	if shape == null:
		return
	var cells_data = shape.get("cells")
	if not (cells_data is Dictionary):
		return
	var cells: Dictionary = cells_data
	if cells.is_empty():
		return
	if not owner.has_method("get_active_cell_grid_pos"):
		return
	var active = owner.get_active_cell_grid_pos()
	if not cells.has(active):
		for key in cells.keys():
			if key is Vector2i:
				active = key as Vector2i
				break
	var open_dirs: Array[Vector2i] = []
	var occupied_dirs: Array[Vector2i] = []
	for dir in CARDINAL_DIRS:
		var neighbor = active + dir
		if cells.has(neighbor):
			occupied_dirs.append(dir)
		else:
			open_dirs.append(dir)
	if open_dirs.is_empty() and occupied_dirs.is_empty():
		return
	var pressure = _enemy_pressure(owner, targets)
	var cell_count = cells.size()
	if cell_count > last_observed_cell_count:
		no_growth_timer = 0.0
		growth_lock_attempts_remaining = 0
	elif cell_count == last_observed_cell_count:
		no_growth_timer += delta
	else:
		no_growth_timer = 0.0
	last_observed_cell_count = cell_count
	var xp_orb_signal = _nearby_xp_orb_signal(owner)
	if explore_before_expand_timer > 0.0 and not _can_break_explore_window(owner, pressure, xp_orb_signal):
		return
	var desire = _expand_desire(owner, cell_count, pressure, orb_target, open_dirs.size(), xp_orb_signal)
	var force_growth = _should_force_growth(owner, pressure, open_dirs.size())
	var should_grow = not open_dirs.is_empty() and (force_growth or randf() <= desire)
	var candidate_dirs = open_dirs if should_grow else occupied_dirs
	if candidate_dirs.is_empty():
		if not should_grow and not open_dirs.is_empty():
			candidate_dirs = open_dirs
			should_grow = true
		else:
			return
	var context = _build_expand_context(owner, cell_count, pressure, orb_target)
	var best_dir = _pick_best_expand_dir(owner, active, cells, candidate_dirs, pressure, orb_target, context, should_grow)
	if best_dir == Vector2i.ZERO:
		return
	emit_command(GameCommand.expand_direction(actor_id, best_dir))
	if should_grow:
		if growth_lock_attempts_remaining > 0:
			growth_lock_attempts_remaining -= 1
		_arm_expand_evaluation(owner, cell_count, pressure, context, best_dir)
	else:
		last_reposition_from = active
		last_reposition_to = active + best_dir
		last_reposition_timer = EXPAND_REPOSITION_BACKTRACK_MEMORY
	expand_cooldown = _expand_cooldown_seconds(owner, cell_count, pressure, should_grow)

func _expand_desire(owner: Node2D, cell_count: int, pressure: float, orb_target: Node2D, open_dir_count: int, xp_orb_signal: float) -> float:
	if open_dir_count <= 0:
		return 0.0
	var xp_now = _read_stat(owner, "xp", 0.0)
	if xp_now < EXPAND_COST:
		return 0.0
	var elapsed = _get_world_elapsed()
	var budget = _target_cell_budget(elapsed, pressure)
	var missing = max(0, budget - cell_count)
	var reserve = EXPAND_COST * lerpf(0.85, 1.7, pressure)
	if aggressive_expander:
		reserve *= 0.78
	reserve *= lerpf(1.0, 0.65, xp_orb_signal)
	var free_credits = maxf(xp_now - EXPAND_COST - reserve, 0.0)
	var credits_factor = clampf(free_credits / 180.0, 0.0, 1.0)
	if free_credits <= 0.0:
		credits_factor = 0.22 if xp_orb_signal >= 0.25 else 0.12
	var pressure_factor = lerpf(0.5, 1.1, 1.0 - pressure)
	if profile == AIProfile.SPREADER:
		pressure_factor = lerpf(0.65, 1.05, 1.0 - pressure)
	elif profile == AIProfile.STUNNER:
		pressure_factor = lerpf(0.7, 1.0, 1.0 - pressure)
	var desire = (0.12 + 0.17 * float(missing)) * _profile_expand_tendency()
	desire *= lerpf(0.6, 1.24, credits_factor)
	desire *= pressure_factor
	desire *= expansion_drive
	desire += xp_orb_signal * (0.16 if aggressive_expander else 0.11)
	if aggressive_expander and xp_now >= EXPAND_COST * 1.15:
		desire += 0.06
	if elapsed < 18.0 and cell_count <= 1 and not aggressive_expander:
		desire *= 0.45
	if orb_target != null and is_instance_valid(orb_target):
		var orb_dist = owner.global_position.distance_to(orb_target.global_position)
		if orb_dist < ORB_COMMIT_RANGE:
			desire *= 0.7
	if cell_count > budget:
		desire *= 0.18
	return clampf(desire, 0.0, 0.78)

func _should_force_growth(owner: Node2D, pressure: float, open_dir_count: int) -> bool:
	if open_dir_count <= 0:
		return false
	var xp_now = _read_stat(owner, "xp", 0.0)
	if xp_now < EXPAND_COST:
		growth_lock_attempts_remaining = 0
		return false
	if growth_lock_attempts_remaining > 0:
		return true
	if no_growth_timer >= EXPAND_STALL_FORCE_GROWTH_TIME and pressure < 0.93:
		growth_lock_attempts_remaining = EXPAND_GROWTH_LOCK_ATTEMPTS
		return true
	return false

func _expand_cooldown_seconds(owner: Node2D, cell_count: int, pressure: float, grew: bool) -> float:
	if not grew:
		return EXPAND_REPOSITION_INTERVAL
	var xp_now = _read_stat(owner, "xp", 0.0)
	var credit_drag = clampf((EXPAND_COST - xp_now) / EXPAND_COST, 0.0, 1.0)
	var cell_drag = clampf(float(cell_count - 1) / 8.0, 0.0, 1.0)
	var pressure_drag = clampf(pressure, 0.0, 1.0)
	var cd = EXPAND_BASE_INTERVAL + cell_drag * 1.45 + pressure_drag * 0.65 + credit_drag * 0.9
	return maxf(cd * _profile_expand_cooldown_scale(), EXPAND_MIN_INTERVAL)

func _profile_expand_tendency() -> float:
	match profile:
		AIProfile.LASER:
			return 0.62
		AIProfile.STUNNER:
			return 0.48
		AIProfile.HOMING:
			return 0.4
		AIProfile.SPREADER:
			return 0.72
		_:
			return 0.55

func _profile_expand_cooldown_scale() -> float:
	match profile:
		AIProfile.LASER:
			return 0.9
		AIProfile.STUNNER:
			return 1.1
		AIProfile.HOMING:
			return 1.2
		AIProfile.SPREADER:
			return 0.85
		_:
			return 1.0

func _target_cell_budget(elapsed: float, pressure: float) -> int:
	var base = 1 + int(floor(maxf(elapsed - 22.0, 0.0) / 52.0))
	match profile:
		AIProfile.LASER:
			base += 1
		AIProfile.SPREADER:
			base += 1
		AIProfile.HOMING:
			base -= 1
		_:
			pass
	if aggressive_expander and elapsed > 10.0:
		base += 1
	if pressure > 0.75:
		base += 1
	return clamp(base, 1, 10)

func _roll_aggressive_expander() -> bool:
	match profile:
		AIProfile.SPREADER:
			return randf() < 0.75
		AIProfile.LASER:
			return randf() < 0.55
		AIProfile.STUNNER:
			return randf() < 0.28
		AIProfile.HOMING:
			return randf() < 0.2
		_:
			return randf() < 0.4

func _can_break_explore_window(owner: Node2D, pressure: float, xp_orb_signal: float) -> bool:
	var xp_now = _read_stat(owner, "xp", 0.0)
	if pressure > 0.87 and xp_now >= EXPAND_COST * 1.2:
		return true
	if aggressive_expander and xp_orb_signal > 0.45 and xp_now >= EXPAND_COST:
		return true
	return false

func _nearby_xp_orb_signal(owner: Node2D) -> float:
	var total = 0.0
	for entity in get_tree().get_nodes_in_group("boost_orbs"):
		var orb = entity as Node2D
		if orb == null or not is_instance_valid(orb):
			continue
		if orb.has_method("is_pickable") and not bool(orb.is_pickable()):
			continue
		if not orb.has_method("get_boost_type") or int(orb.get_boost_type()) != 0:
			continue
		if not orb.has_method("get_amount"):
			continue
		var dist = owner.global_position.distance_to(orb.global_position)
		if dist > XP_ORB_EXPAND_LOOKAHEAD_RANGE:
			continue
		var amount = maxf(float(orb.get_amount()), 0.0)
		var proximity = 1.0 - clampf(dist / XP_ORB_EXPAND_LOOKAHEAD_RANGE, 0.0, 1.0)
		total += amount * (0.4 + proximity * 0.6)
	return clampf(total / XP_ORB_EXPAND_BONUS_CAP, 0.0, 1.0)

func _build_expand_context(owner: Node2D, cell_count: int, pressure: float, orb_target: Node2D) -> String:
	var pressure_bucket = int(floor(clampf(pressure, 0.0, 0.999) * 3.0))
	var size_bucket = clamp(cell_count / 3, 0, 3)
	var mode = "combat"
	if orb_target != null and is_instance_valid(orb_target):
		var orb_dist = owner.global_position.distance_to(orb_target.global_position)
		if orb_dist < ORB_COMMIT_RANGE * 1.4:
			mode = "orb"
	if pressure > 0.7:
		mode = "defense"
	return "%d|%d|%d|%s" % [profile, pressure_bucket, size_bucket, mode]

func _pick_best_expand_dir(
	owner: Node2D,
	active: Vector2i,
	cells: Dictionary,
	candidate_dirs: Array[Vector2i],
	pressure: float,
	orb_target: Node2D,
	context: String,
	growth_mode: bool
) -> Vector2i:
	var best = Vector2i.ZERO
	var best_score = -INF
	var nearest_enemy = _nearest_enemy(owner)
	for dir in candidate_dirs:
		var score = _score_expand_dir(owner, active, cells, dir, pressure, orb_target, context, growth_mode, nearest_enemy)
		if score > best_score:
			best_score = score
			best = dir
	return best

func _score_expand_dir(
	owner: Node2D,
	active: Vector2i,
	cells: Dictionary,
	dir: Vector2i,
	pressure: float,
	orb_target: Node2D,
	context: String,
	growth_mode: bool,
	nearest_enemy: Node2D
) -> float:
	var score = 0.0
	var dir_v = Vector2(dir.x, dir.y).normalized()
	score += dir_v.dot(preferred_axis) * 0.16
	score += _shared_dir_score(context, dir) * 0.45
	if current_target != null and is_instance_valid(current_target):
		var to_target = (current_target.global_position - owner.global_position).normalized()
		var align = dir_v.dot(to_target)
		score += _profile_target_dir_weight(align)
	if nearest_enemy != null:
		var away_enemy = (owner.global_position - nearest_enemy.global_position).normalized()
		score += dir_v.dot(away_enemy) * pressure * 0.42
	if orb_target != null and is_instance_valid(orb_target):
		var to_orb = (orb_target.global_position - owner.global_position).normalized()
		score += dir_v.dot(to_orb) * 0.22
	if growth_mode:
		score += _frontier_growth_score(active + dir, cells, dir)
	else:
		score += 0.12
		if last_reposition_timer > 0.0:
			var candidate_target = active + dir
			if active == last_reposition_to and candidate_target == last_reposition_from:
				score -= 0.58
			elif candidate_target == last_reposition_from:
				score -= 0.22
	score += randf_range(-0.05, 0.05)
	return score

func _profile_target_dir_weight(align: float) -> float:
	match profile:
		AIProfile.LASER:
			return align * 0.5
		AIProfile.STUNNER:
			return align * 0.32
		AIProfile.HOMING:
			return (1.0 - absf(align)) * 0.3
		AIProfile.SPREADER:
			return align * 0.55
		_:
			return align * 0.38

func _frontier_growth_score(target_cell: Vector2i, cells: Dictionary, dir: Vector2i) -> float:
	var open_neighbors = 0
	for neighbor_dir in CARDINAL_DIRS:
		if not cells.has(target_cell + neighbor_dir):
			open_neighbors += 1
	var center = _cells_center(cells)
	var out_vec = (Vector2(target_cell) - center).normalized()
	var dir_v = Vector2(dir.x, dir.y).normalized()
	var outness = out_vec.dot(dir_v)
	return float(open_neighbors) * 0.11 + outness * 0.24

func _cells_center(cells: Dictionary) -> Vector2:
	if cells.is_empty():
		return Vector2.ZERO
	var sum = Vector2.ZERO
	var count = 0
	for key in cells.keys():
		if key is Vector2i:
			sum += Vector2(key)
			count += 1
	if count <= 0:
		return Vector2.ZERO
	return sum / float(count)

func _nearest_enemy(owner: Node2D) -> Node2D:
	var best: Node2D = null
	var best_dist = INF
	for entity in get_tree().get_nodes_in_group("combatants"):
		var node = entity as Node2D
		if node == null or node == owner:
			continue
		var d = owner.global_position.distance_to(node.global_position)
		if d < best_dist:
			best_dist = d
			best = node
	return best

func _arm_expand_evaluation(owner: Node2D, cell_count: int, pressure: float, context: String, dir: Vector2i) -> void:
	pending_expand_context = context
	pending_expand_dir = dir
	pending_expand_timer = EXPAND_EVAL_WINDOW
	pending_expand_before_hp = _read_stat(owner, "health", 0.0)
	pending_expand_before_max_hp = maxf(_read_stat(owner, "max_health", 1.0), 1.0)
	pending_expand_before_xp = _read_stat(owner, "xp", 0.0)
	pending_expand_before_pressure = pressure
	pending_expand_before_cells = cell_count
	pending_expand_requires_growth = true

func _update_expand_learning(owner: Node2D, targets: Array, delta: float) -> void:
	if pending_expand_context.is_empty():
		return
	pending_expand_timer = maxf(pending_expand_timer - delta, 0.0)
	var current_cells = _cell_count(owner)
	if pending_expand_requires_growth and current_cells <= pending_expand_before_cells and pending_expand_timer <= (EXPAND_EVAL_WINDOW - EXPAND_FAIL_WINDOW):
		_update_shared_expand_score(pending_expand_context, pending_expand_dir, -0.22)
		if growth_lock_attempts_remaining <= 0:
			growth_lock_attempts_remaining = 1
		_clear_pending_expand_eval()
		return
	if pending_expand_timer > 0.0:
		return
	var hp = _read_stat(owner, "health", 0.0)
	var xp = _read_stat(owner, "xp", 0.0)
	var pressure_now = _enemy_pressure(owner, targets)
	var hp_delta = (hp - pending_expand_before_hp) / pending_expand_before_max_hp
	var xp_delta = (xp - pending_expand_before_xp) / 45.0
	var pressure_relief = pending_expand_before_pressure - pressure_now
	var growth_bonus = 0.11 if current_cells > pending_expand_before_cells else -0.1
	if current_cells > pending_expand_before_cells:
		growth_lock_attempts_remaining = 0
		no_growth_timer = 0.0
	var score = hp_delta * 1.0 + xp_delta * 0.4 + pressure_relief * 0.55 + growth_bonus
	_update_shared_expand_score(pending_expand_context, pending_expand_dir, clampf(score, -0.35, 0.35))
	_clear_pending_expand_eval()

func _clear_pending_expand_eval() -> void:
	pending_expand_context = ""
	pending_expand_dir = Vector2i.ZERO
	pending_expand_timer = 0.0
	pending_expand_requires_growth = false

func _shared_dir_score(context: String, dir: Vector2i) -> float:
	var key = "%s|%d,%d" % [context, dir.x, dir.y]
	return float(_shared_expand_memory.get(key, 0.0))

func _update_shared_expand_score(context: String, dir: Vector2i, sample: float) -> void:
	var key = "%s|%d,%d" % [context, dir.x, dir.y]
	var old = float(_shared_expand_memory.get(key, 0.0))
	_shared_expand_memory[key] = clampf(lerpf(old, sample, 0.23), -1.0, 1.0)

func _read_stat(owner: Node, property_name: String, fallback: float) -> float:
	var v = owner.get(property_name)
	if v == null:
		return fallback
	return float(v)

func _cell_count(owner: Node) -> int:
	var shape = owner.get_node_or_null("PlayerShape")
	if shape == null:
		return 1
	var cells_data = shape.get("cells")
	if not (cells_data is Dictionary):
		return 1
	return max(1, (cells_data as Dictionary).size())

func _get_world_elapsed() -> float:
	var world = get_tree().get_first_node_in_group("world")
	if world == null:
		return 0.0
	return _read_stat(world, "elapsed", 0.0)

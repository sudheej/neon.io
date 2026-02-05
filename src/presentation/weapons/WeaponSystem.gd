extends Node

const WeaponSlot = preload("res://src/domain/weapons/WeaponSlot.gd")
const PlayerShapeScript = preload("res://src/presentation/player/PlayerShape.gd")

const FIRE_COOLDOWN: float = 0.35
const STUN_COST: float = 0.0
const HOMING_COST: float = 0.0
const SPREAD_COST: float = 0.0
const LASER_PACK_COST: float = 4.0
const STUN_PACK_COST: float = 8.0
const HOMING_PACK_COST: float = 12.0
const SPREAD_PACK_COST: float = 6.0
const LASER_PACK_AMMO: int = 10
const STUN_PACK_AMMO: int = 5
const HOMING_PACK_AMMO: int = 3
const SPREAD_PACK_AMMO: int = 6
const LASER_CAPACITY: int = 40
const STUN_CAPACITY: int = 20
const HOMING_CAPACITY: int = 15
const SPREAD_CAPACITY: int = 24
const LASER_DAMAGE: float = 4.0
const SPREAD_PRIMARY_MULT: float = 0.75
const SPREAD_SECONDARY_MULT: float = 0.5
const SPREAD_RADIUS: float = 140.0
const HOMING_MAX_ACTIVE_PER_CELL: int = 1

var player: Node2D
var shape: Node

var slots: Array = []
var selected_index: int = 0
var slot_cooldowns: Dictionary = {}
var slot_blocked: Dictionary = {}
var slot_targets: Dictionary = {}
var armed_cell: Vector2i = Vector2i.ZERO
var has_armed_cell: bool = false
var selected_weapon_type: int = WeaponSlot.WeaponType.LASER
var weapon_costs: Dictionary = {
	WeaponSlot.WeaponType.LASER: 0.0,
	WeaponSlot.WeaponType.STUN: STUN_COST,
	WeaponSlot.WeaponType.HOMING: HOMING_COST,
	WeaponSlot.WeaponType.SPREAD: SPREAD_COST
}
var weapon_cooldowns: Dictionary = {
	WeaponSlot.WeaponType.LASER: 0.55,
	WeaponSlot.WeaponType.STUN: 0.42,
	WeaponSlot.WeaponType.HOMING: 0.3,
	WeaponSlot.WeaponType.SPREAD: 0.65
}
var weapon_ammo: Dictionary = {
	WeaponSlot.WeaponType.LASER: 20,
	WeaponSlot.WeaponType.STUN: 0,
	WeaponSlot.WeaponType.HOMING: 15,
	WeaponSlot.WeaponType.SPREAD: 0
}
var auto_reload: bool = true
var preferred_target: Node2D = null

func _ready() -> void:
	player = get_parent() as Node2D
	shape = player.get_node_or_null("PlayerShape")
	_rebuild_slots()
	_apply_weapon_to_all_slots(selected_weapon_type)
	_auto_buy_starting_pack(WeaponSlot.WeaponType.STUN)
	_auto_buy_starting_pack(WeaponSlot.WeaponType.SPREAD)

func _rebuild_slots() -> void:
	slots.clear()
	slot_cooldowns.clear()
	slot_blocked.clear()
	slot_targets.clear()
	if shape == null:
		return
	for grid_pos in shape.cells.keys():
		var slot_data: Dictionary = shape.cells[grid_pos]["slots"]
		var dir = PlayerShapeScript.DIRS[0]
		var weapon_type = slot_data.get(dir, {"weapon": selected_weapon_type}).get("weapon", selected_weapon_type)
		var slot = WeaponSlot.new(grid_pos, dir, weapon_type)
		slots.append(slot)
		slot_cooldowns[slot] = 0.0
		slot_blocked[slot] = false
	_set_default_armed_cell()
	_sync_selection_to_armed_cell()

func on_shape_changed() -> void:
	_rebuild_slots()
	selected_index = clampi(selected_index, 0, max(slots.size() - 1, 0))
	_sync_selection_to_armed_cell()

func select_next_slot() -> void:
	if slots.is_empty():
		return
	selected_index = (selected_index + 1) % slots.size()
	armed_cell = slots[selected_index].grid_pos
	has_armed_cell = true

func select_prev_slot() -> void:
	if slots.is_empty():
		return
	selected_index = (selected_index - 1 + slots.size()) % slots.size()
	armed_cell = slots[selected_index].grid_pos
	has_armed_cell = true

func get_selected_slot():
	if slots.is_empty():
		return null
	return slots[selected_index]

func get_selected_weapon_type() -> int:
	return selected_weapon_type

func get_weapon_cost(weapon_type: int) -> float:
	return weapon_costs.get(weapon_type, 0.0)

func get_weapon_pack_cost(weapon_type: int) -> float:
	match weapon_type:
		WeaponSlot.WeaponType.LASER:
			return LASER_PACK_COST
		WeaponSlot.WeaponType.STUN:
			return STUN_PACK_COST
		WeaponSlot.WeaponType.HOMING:
			return HOMING_PACK_COST
		WeaponSlot.WeaponType.SPREAD:
			return SPREAD_PACK_COST
		_:
			return 0.0

func get_weapon_pack_ammo(weapon_type: int) -> int:
	match weapon_type:
		WeaponSlot.WeaponType.LASER:
			return LASER_PACK_AMMO
		WeaponSlot.WeaponType.STUN:
			return STUN_PACK_AMMO
		WeaponSlot.WeaponType.HOMING:
			return HOMING_PACK_AMMO
		WeaponSlot.WeaponType.SPREAD:
			return SPREAD_PACK_AMMO
		_:
			return 0

func get_weapon_ammo(weapon_type: int) -> int:
	return weapon_ammo.get(weapon_type, 0)

func get_weapon_capacity(weapon_type: int) -> int:
	match weapon_type:
		WeaponSlot.WeaponType.LASER:
			return LASER_CAPACITY
		WeaponSlot.WeaponType.STUN:
			return STUN_CAPACITY
		WeaponSlot.WeaponType.HOMING:
			return HOMING_CAPACITY
		WeaponSlot.WeaponType.SPREAD:
			return SPREAD_CAPACITY
		_:
			return 0

func get_weapon_label(weapon_type: int) -> String:
	match weapon_type:
		WeaponSlot.WeaponType.LASER:
			return "Laser"
		WeaponSlot.WeaponType.STUN:
			return "Stun"
		WeaponSlot.WeaponType.HOMING:
			return "Homing"
		WeaponSlot.WeaponType.SPREAD:
			return "Spread"
		_:
			return "Unknown"

func try_set_selected_weapon(weapon_type: int) -> bool:
	var slot = get_selected_slot()
	if slot == null:
		return false
	if selected_weapon_type == weapon_type:
		return true
	var cost = get_weapon_cost(weapon_type)
	if cost > 0.0:
		if player == null or not player.has_method("spend_xp"):
			return false
		if not player.spend_xp(cost):
			return false
	selected_weapon_type = weapon_type
	_apply_weapon_to_all_slots(weapon_type)
	return true

func select_weapon_and_buy(weapon_type: int) -> void:
	var slot = get_selected_slot()
	if slot == null:
		return
	var pack_cost = get_weapon_pack_cost(weapon_type)
	var pack_amount = get_weapon_pack_ammo(weapon_type)
	if get_weapon_ammo(weapon_type) > 0:
		selected_weapon_type = weapon_type
		_apply_weapon_to_all_slots(weapon_type)
		return
	if pack_cost <= 0.0 or pack_amount <= 0:
		return
	if player == null or not player.has_method("spend_xp"):
		return
	if player.spend_xp(pack_cost):
		weapon_ammo[weapon_type] = get_weapon_ammo(weapon_type) + pack_amount
		selected_weapon_type = weapon_type
		_apply_weapon_to_all_slots(weapon_type)

func set_armed_cell(grid_pos: Vector2i) -> void:
	armed_cell = grid_pos
	has_armed_cell = true
	_sync_selection_to_armed_cell()

func sync_armed_cell_to_selection() -> void:
	var slot = get_selected_slot()
	if slot == null:
		return
	armed_cell = slot.grid_pos
	has_armed_cell = true

func get_armed_cell() -> Vector2i:
	return armed_cell

func get_slot_world_origin(slot) -> Vector2:
	var local_pos = shape.grid_to_local(slot.grid_pos)
	return player.global_position + local_pos

func process_weapons(delta: float, enemies: Array[Node]) -> void:
	if slots.is_empty() or shape == null:
		return
	var used_targets: Dictionary = {}
	for slot in slots:
		slot_cooldowns[slot] = maxf(slot_cooldowns[slot] - delta, 0.0)
		var origin = get_slot_world_origin(slot)
		var blocked = false
		slot_blocked[slot] = blocked
		if blocked:
			continue
		if slot_cooldowns[slot] > 0.0:
			continue
		var weapon_type = selected_weapon_type
		slot.weapon_type = weapon_type
		if weapon_type == WeaponSlot.WeaponType.HOMING:
			var max_active = max(1, slots.size() * HOMING_MAX_ACTIVE_PER_CELL)
			if _count_homing_missiles_for_player() >= max_active:
				continue
		if get_weapon_ammo(weapon_type) <= 0:
			if auto_reload and _try_auto_reload(weapon_type):
				pass
			else:
				continue

		var target = _find_target_for_slot(slot, origin, slot.range, enemies, used_targets)
		if target == null:
			continue
		used_targets[target] = true
		_fire_at_target(slot, origin, target, enemies)
		_consume_ammo(weapon_type, 1)
		slot_cooldowns[slot] = weapon_cooldowns.get(weapon_type, FIRE_COOLDOWN)

func is_slot_blocked(slot) -> bool:
	return slot_blocked.get(slot, false)

func _apply_weapon_to_all_slots(weapon_type: int) -> void:
	for slot in slots:
		slot.weapon_type = weapon_type
	if shape == null:
		return
	for grid_pos in shape.cells.keys():
		var slot_data: Dictionary = shape.cells[grid_pos]["slots"]
		for dir in PlayerShapeScript.DIRS:
			if slot_data.has(dir):
				slot_data[dir]["weapon"] = weapon_type

func _find_target_for_slot(slot, origin: Vector2, max_range: float, enemies: Array[Node], used_targets: Dictionary) -> Node2D:
	var in_range = _collect_enemies_in_range(origin, max_range, enemies)
	if in_range.is_empty():
		return null
	var prev_target = slot_targets.get(slot, null)
	if prev_target != null and is_instance_valid(prev_target) and in_range.has(prev_target):
		var alternatives: Array[Node2D] = []
		for enemy in in_range:
			if used_targets.has(enemy):
				continue
			if enemy == prev_target:
				continue
			alternatives.append(enemy)
		if not alternatives.is_empty():
			var pick = _find_nearest_in_list(origin, alternatives)
			slot_targets[slot] = pick
			return pick
		if not used_targets.has(prev_target):
			slot_targets[slot] = prev_target
			return prev_target
	var available: Array[Node2D] = []
	for enemy in in_range:
		if used_targets.has(enemy):
			continue
		available.append(enemy)
	if not available.is_empty():
		var pick_any = _find_nearest_in_list(origin, available)
		slot_targets[slot] = pick_any
		return pick_any
	var fallback = _find_nearest_in_list(origin, in_range)
	slot_targets[slot] = fallback
	return fallback

func _collect_enemies_in_range(origin: Vector2, max_range: float, enemies: Array[Node]) -> Array[Node2D]:
	var list: Array[Node2D] = []
	for enemy in enemies:
		var enemy_node = enemy as Node2D
		if enemy_node == null:
			continue
		if origin.distance_to(enemy_node.global_position) <= max_range:
			list.append(enemy_node)
	return list

func _find_nearest_in_list(origin: Vector2, enemies: Array[Node2D]) -> Node2D:
	var best_dist = INF
	var best_enemy: Node2D = null
	for enemy in enemies:
		var dist = origin.distance_to(enemy.global_position)
		if dist <= best_dist:
			best_dist = dist
			best_enemy = enemy
	return best_enemy

func _count_homing_missiles_for_player() -> int:
	if player == null or not is_instance_valid(player):
		return 0
	var count = 0
	for missile in get_tree().get_nodes_in_group("homing_missiles"):
		if missile == null:
			continue
		var source = missile.get("source")
		if source == player:
			count += 1
	return count

func _find_nearest_enemy_in_range(origin: Vector2, max_range: float, enemies: Array[Node]) -> Node2D:
	var best_dist = max_range
	var best_enemy: Node2D = null
	for enemy in enemies:
		var enemy_node = enemy as Node2D
		if enemy_node == null:
			continue
		var dist = origin.distance_to(enemy_node.global_position)
		if dist <= best_dist:
			best_dist = dist
			best_enemy = enemy_node
	return best_enemy

func _find_target_in_range(origin: Vector2, max_range: float, enemies: Array[Node]) -> Node2D:
	if preferred_target != null and is_instance_valid(preferred_target):
		if enemies.has(preferred_target):
			var dist = origin.distance_to(preferred_target.global_position)
			if dist <= max_range:
				return preferred_target
	return _find_nearest_enemy_in_range(origin, max_range, enemies)

func set_preferred_target(target: Node2D) -> void:
	preferred_target = target

func _fire_at_target(slot, origin: Vector2, target: Node2D, enemies: Array[Node]) -> void:
	var world = get_tree().get_first_node_in_group("world") as Node
	if world == null:
		return

	var local_pos = shape.grid_to_local(slot.grid_pos)
	var damage = LASER_DAMAGE
	var stun_duration = 0.0
	if slot.weapon_type == WeaponSlot.WeaponType.STUN:
		stun_duration = 0.65
		damage = 3.0
	elif slot.weapon_type == WeaponSlot.WeaponType.HOMING:
		damage = 7.0
	elif slot.weapon_type == WeaponSlot.WeaponType.SPREAD:
		damage = LASER_DAMAGE * SPREAD_PRIMARY_MULT

	if slot.weapon_type == WeaponSlot.WeaponType.HOMING:
		var homing = preload("res://src/presentation/weapons/projectiles/HomingShot.gd").new()
		homing.global_position = origin
		homing.setup(origin, target, damage, player, slot.weapon_type)
		world.add_child(homing)
	else:
		var laser = preload("res://src/presentation/weapons/projectiles/LaserShot.gd").new()
		laser.global_position = Vector2.ZERO
		if slot.weapon_type == WeaponSlot.WeaponType.STUN:
			laser.setup(
				origin,
				target.global_position,
				player,
				local_pos,
				target,
				Color(0.2, 1.0, 0.4, 0.6),
				Color(0.6, 1.0, 0.7, 0.9)
			)
		elif slot.weapon_type == WeaponSlot.WeaponType.SPREAD:
			laser.setup(
				origin,
				target.global_position,
				player,
				local_pos,
				target,
				Color(0.75, 0.4, 1.0, 0.6),
				Color(0.9, 0.65, 1.0, 0.9),
				3.0,
				1.2,
				0.25,
				0.8
			)
		else:
			laser.setup(origin, target.global_position, player, local_pos, target)
		world.add_child(laser)

	if slot.weapon_type == WeaponSlot.WeaponType.SPREAD:
		_spawn_spread_bursts(world, target.global_position, target, enemies)

	if slot.weapon_type != WeaponSlot.WeaponType.HOMING:
		if target.has_method("apply_damage"):
			target.apply_damage(damage, stun_duration, player, slot.weapon_type)

func _spawn_spread_bursts(world: Node, impact_pos: Vector2, primary_target: Node2D, enemies: Array[Node]) -> void:
	var secondary_damage = LASER_DAMAGE * SPREAD_SECONDARY_MULT
	var targets = _find_spread_targets(impact_pos, SPREAD_RADIUS, enemies, primary_target)
	if targets.is_empty():
		return
	for target in targets:
		var beam = preload("res://src/presentation/weapons/projectiles/LaserShot.gd").new()
		beam.global_position = Vector2.ZERO
		beam.setup(
			impact_pos,
			target.global_position,
			null,
			Vector2.ZERO,
			target,
			Color(0.7, 0.35, 1.0, 0.5),
			Color(0.85, 0.55, 1.0, 0.8),
			1.6,
			0.7,
			0.35,
			1.2
		)
		world.add_child(beam)
		if target.has_method("apply_damage"):
			target.apply_damage(secondary_damage, 0.0, player, WeaponSlot.WeaponType.SPREAD)

func _find_spread_targets(origin: Vector2, max_range: float, enemies: Array[Node], primary_target: Node2D) -> Array[Node2D]:
	var targets: Array[Node2D] = []
	for enemy in enemies:
		var node = enemy as Node2D
		if node == null or node == primary_target:
			continue
		var dist = origin.distance_to(node.global_position)
		if dist <= max_range:
			targets.append(node)
	return targets

func _set_slot_weapon(slot, weapon_type: int) -> void:
	slot.weapon_type = weapon_type
	if shape == null:
		return
	if not shape.cells.has(slot.grid_pos):
		return
	var slot_data: Dictionary = shape.cells[slot.grid_pos]["slots"]
	for dir in PlayerShapeScript.DIRS:
		if slot_data.has(dir):
			slot_data[dir]["weapon"] = weapon_type

func _consume_ammo(weapon_type: int, amount: int) -> void:
	var current = get_weapon_ammo(weapon_type)
	weapon_ammo[weapon_type] = max(current - amount, 0)

func _try_auto_reload(weapon_type: int) -> bool:
	var pack_cost = get_weapon_pack_cost(weapon_type)
	var pack_amount = get_weapon_pack_ammo(weapon_type)
	if pack_cost <= 0.0 or pack_amount <= 0:
		return false
	if player == null or not player.has_method("spend_xp"):
		return false
	if not player.spend_xp(pack_cost):
		return false
	weapon_ammo[weapon_type] = get_weapon_ammo(weapon_type) + pack_amount
	return true

func _auto_buy_starting_pack(weapon_type: int) -> void:
	if get_weapon_ammo(weapon_type) > 0:
		return
	_try_auto_reload(weapon_type)

func _set_default_armed_cell() -> void:
	if shape == null:
		return
	if shape.cells.is_empty():
		return
	if has_armed_cell and shape.cells.has(armed_cell):
		return
	armed_cell = _get_top_left_cell()
	has_armed_cell = true

func _get_top_left_cell() -> Vector2i:
	var best: Vector2i = Vector2i.ZERO
	var has_best: bool = false
	for key in shape.cells.keys():
		var grid_pos: Vector2i = key
		if not has_best:
			best = grid_pos
			has_best = true
		elif grid_pos.y < best.y or (grid_pos.y == best.y and grid_pos.x < best.x):
			best = grid_pos
	return best

func _sync_selection_to_armed_cell() -> void:
	if slots.is_empty():
		return
	for i in range(slots.size()):
		if slots[i].grid_pos == armed_cell:
			selected_index = i
			return

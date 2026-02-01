extends Node
class_name WeaponSystem

const WeaponSlot = preload("res://scripts/weapons/WeaponSlot.gd")
const PlayerShapeScript = preload("res://scripts/player/PlayerShape.gd")

const FIRE_COOLDOWN: float = 0.35
const STUN_COST: float = 0.0
const HOMING_COST: float = 0.0
const LASER_PACK_COST: float = 4.0
const STUN_PACK_COST: float = 8.0
const HOMING_PACK_COST: float = 12.0
const LASER_PACK_AMMO: int = 10
const STUN_PACK_AMMO: int = 5
const HOMING_PACK_AMMO: int = 3
const LASER_CAPACITY: int = 40
const STUN_CAPACITY: int = 20
const HOMING_CAPACITY: int = 15

var player: Node2D
var shape: Node

var slots: Array[WeaponSlot] = []
var selected_index: int = 0
var slot_cooldowns: Dictionary = {}
var slot_blocked: Dictionary = {}
var armed_cell: Vector2i = Vector2i.ZERO
var has_armed_cell: bool = false
var weapon_costs: Dictionary = {
	WeaponSlot.WeaponType.LASER: 0.0,
	WeaponSlot.WeaponType.STUN: STUN_COST,
	WeaponSlot.WeaponType.HOMING: HOMING_COST
}
var weapon_cooldowns: Dictionary = {
	WeaponSlot.WeaponType.LASER: 0.55,
	WeaponSlot.WeaponType.STUN: 0.42,
	WeaponSlot.WeaponType.HOMING: 0.3
}
var weapon_ammo: Dictionary = {
	WeaponSlot.WeaponType.LASER: 20,
	WeaponSlot.WeaponType.STUN: 0,
	WeaponSlot.WeaponType.HOMING: 15
}
var auto_reload: bool = true
var preferred_target: Node2D = null

func _ready() -> void:
	player = get_parent() as Node2D
	shape = player.get_node_or_null("PlayerShape")
	_rebuild_slots()

func _rebuild_slots() -> void:
	slots.clear()
	slot_cooldowns.clear()
	slot_blocked.clear()
	if shape == null:
		return
	for grid_pos in shape.cells.keys():
		var slot_data: Dictionary = shape.cells[grid_pos]["slots"]
		for dir in PlayerShapeScript.DIRS:
			var weapon_type = slot_data[dir]["weapon"]
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

func select_prev_slot() -> void:
	if slots.is_empty():
		return
	selected_index = (selected_index - 1 + slots.size()) % slots.size()

func get_selected_slot() -> WeaponSlot:
	if slots.is_empty():
		return null
	return slots[selected_index]

func get_selected_weapon_type() -> int:
	var slot = get_selected_slot()
	if slot == null:
		return WeaponSlot.WeaponType.LASER
	return slot.weapon_type

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
		_:
			return "Unknown"

func try_set_selected_weapon(weapon_type: int) -> bool:
	var slot = get_selected_slot()
	if slot == null:
		return false
	if slot.weapon_type == weapon_type:
		return true
	var cost = get_weapon_cost(weapon_type)
	if cost > 0.0:
		if player == null or not player.has_method("spend_xp"):
			return false
		if not player.spend_xp(cost):
			return false
	_set_slot_weapon(slot, weapon_type)
	return true

func select_weapon_and_buy(weapon_type: int) -> void:
	var slot = get_selected_slot()
	if slot == null:
		return
	var pack_cost = get_weapon_pack_cost(weapon_type)
	var pack_amount = get_weapon_pack_ammo(weapon_type)
	if get_weapon_ammo(weapon_type) > 0:
		_set_slot_weapon(slot, weapon_type)
		return
	if pack_cost <= 0.0 or pack_amount <= 0:
		return
	if player == null or not player.has_method("spend_xp"):
		return
	if player.spend_xp(pack_cost):
		weapon_ammo[weapon_type] = get_weapon_ammo(weapon_type) + pack_amount
		_set_slot_weapon(slot, weapon_type)

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

func get_slot_world_origin(slot: WeaponSlot) -> Vector2:
	var local_pos = shape.grid_to_local(slot.grid_pos)
	return player.global_position + local_pos

func process_weapons(delta: float, enemies: Array[Node]) -> void:
	if slots.is_empty() or shape == null:
		return

	var slot = get_selected_slot()
	if slot == null:
		return
	slot_cooldowns[slot] = maxf(slot_cooldowns[slot] - delta, 0.0)
	var origin = get_slot_world_origin(slot)
	var blocked = false
	slot_blocked[slot] = blocked
	if blocked:
		return
	if slot_cooldowns[slot] > 0.0:
		return
	var weapon_type = slot.weapon_type
	if weapon_type == WeaponSlot.WeaponType.HOMING:
		if get_tree().get_nodes_in_group("homing_missiles").size() > 0:
			return
	if get_weapon_ammo(weapon_type) <= 0:
		if auto_reload and _try_auto_reload(weapon_type):
			pass
		else:
			return

	var target = _find_target_in_range(origin, slot.range, enemies)
	if target == null:
		return

	_fire_at_target(slot, origin, target)
	_consume_ammo(weapon_type, 1)
	slot_cooldowns[slot] = weapon_cooldowns.get(weapon_type, FIRE_COOLDOWN)

func is_slot_blocked(slot: WeaponSlot) -> bool:
	return slot_blocked.get(slot, false)

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

func _fire_at_target(slot: WeaponSlot, origin: Vector2, target: Node2D) -> void:
	var world = get_tree().get_first_node_in_group("world") as Node
	if world == null:
		return

	var local_pos = shape.grid_to_local(slot.grid_pos)
	var damage = 4.0
	var stun_duration = 0.0
	if slot.weapon_type == WeaponSlot.WeaponType.STUN:
		stun_duration = 0.65
		damage = 3.0
	elif slot.weapon_type == WeaponSlot.WeaponType.HOMING:
		damage = 7.0

	if slot.weapon_type == WeaponSlot.WeaponType.HOMING:
		var homing = preload("res://scripts/weapons/projectiles/HomingShot.gd").new()
		homing.global_position = origin
		homing.setup(origin, target, damage, player, slot.weapon_type)
		world.add_child(homing)
	else:
		var laser = preload("res://scripts/weapons/projectiles/LaserShot.gd").new()
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
		else:
			laser.setup(origin, target.global_position, player, local_pos, target)
		world.add_child(laser)

	if slot.weapon_type != WeaponSlot.WeaponType.HOMING:
		if target.has_method("apply_damage"):
			target.apply_damage(damage, stun_duration, player, slot.weapon_type)

func _set_slot_weapon(slot: WeaponSlot, weapon_type: int) -> void:
	slot.weapon_type = weapon_type
	if shape == null:
		return
	if not shape.cells.has(slot.grid_pos):
		return
	var slot_data: Dictionary = shape.cells[slot.grid_pos]["slots"]
	if slot_data.has(slot.dir):
		slot_data[slot.dir]["weapon"] = weapon_type

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

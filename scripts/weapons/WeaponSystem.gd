extends Node
class_name WeaponSystem

const WeaponSlot = preload("res://scripts/weapons/WeaponSlot.gd")
const PlayerShapeScript = preload("res://scripts/player/PlayerShape.gd")

const FIRE_COOLDOWN: float = 0.35

var player: Node2D
var shape: Node

var slots: Array[WeaponSlot] = []
var selected_index: int = 0
var slot_cooldowns: Dictionary = {}
var slot_blocked: Dictionary = {}
var armed_cell: Vector2i = Vector2i.ZERO
var has_armed_cell: bool = false

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
			var slot := WeaponSlot.new(grid_pos, dir, weapon_type)
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

func set_armed_cell(grid_pos: Vector2i) -> void:
	armed_cell = grid_pos
	has_armed_cell = true
	_sync_selection_to_armed_cell()

func sync_armed_cell_to_selection() -> void:
	var slot := get_selected_slot()
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

	var slot := get_selected_slot()
	if slot == null:
		return
	slot_cooldowns[slot] = maxf(slot_cooldowns[slot] - delta, 0.0)
	var origin := get_slot_world_origin(slot)
	var blocked := false
	slot_blocked[slot] = blocked
	if blocked:
		return
	if slot_cooldowns[slot] > 0.0:
		return

	var target := _find_nearest_enemy_in_range(origin, slot.range, enemies)
	if target == null:
		return

	_fire_at_target(slot, origin, target)
	slot_cooldowns[slot] = FIRE_COOLDOWN

func is_slot_blocked(slot: WeaponSlot) -> bool:
	return slot_blocked.get(slot, false)

func _find_nearest_enemy_in_range(origin: Vector2, max_range: float, enemies: Array[Node]) -> Node2D:
	var best_dist := max_range
	var best_enemy: Node2D = null
	for enemy in enemies:
		var enemy_node := enemy as Node2D
		if enemy_node == null:
			continue
		var dist := origin.distance_to(enemy_node.global_position)
		if dist <= best_dist:
			best_dist = dist
			best_enemy = enemy_node
	return best_enemy

func _fire_at_target(slot: WeaponSlot, origin: Vector2, target: Node2D) -> void:
	var world := get_tree().get_first_node_in_group("world") as Node
	if world == null:
		return

	var laser := preload("res://scripts/weapons/projectiles/LaserShot.gd").new()
	laser.global_position = Vector2.ZERO
	var local_pos = shape.grid_to_local(slot.grid_pos)
	laser.setup(origin, target.global_position, player, local_pos, target)
	world.add_child(laser)

	var damage := 5.0
	var stun_duration := 0.0
	if slot.weapon_type == WeaponSlot.WeaponType.STUN:
		stun_duration = 0.6
		damage = 3.0

	if target.has_method("apply_damage"):
		target.apply_damage(damage, stun_duration)

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

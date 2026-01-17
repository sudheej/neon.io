extends Node
class_name PlayerShape

const WeaponSlot = preload("res://scripts/weapons/WeaponSlot.gd")

const CELL_SIZE: float = 32.0

# Dictionary keys are Vector2i grid positions.
# Each value stores simple per-cell data, including weapon slots.
var cells: Dictionary = {}

# Direction order for consistent slot generation.
const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

func _ready() -> void:
	if cells.is_empty():
		add_cell(Vector2i.ZERO)

func grid_to_local(p: Vector2i) -> Vector2:
	return Vector2(p.x, p.y) * CELL_SIZE

func local_to_grid(v: Vector2) -> Vector2i:
	return Vector2i(roundi(v.x / CELL_SIZE), roundi(v.y / CELL_SIZE))

func add_cell(grid_pos: Vector2i) -> bool:
	if cells.has(grid_pos):
		return false
	var slot_data: Dictionary = {}
	for dir in DIRS:
		slot_data[dir] = {"weapon": WeaponSlot.WeaponType.LASER, "level": 1}
	cells[grid_pos] = {"slots": slot_data}
	return true

func remove_cell(grid_pos: Vector2i) -> void:
	cells.erase(grid_pos)

func get_world_rects_of_cells() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var parent_node := get_parent() as Node2D
	if parent_node == null:
		return rects
	for grid_pos in cells.keys():
		var local_pos := grid_to_local(grid_pos)
		var world_pos := parent_node.global_position + local_pos
		rects.append(Rect2(world_pos - Vector2.ONE * (CELL_SIZE * 0.5), Vector2.ONE * CELL_SIZE))
	return rects

func ray_intersects_own_cells(origin: Vector2, dir: Vector2, max_dist: float) -> bool:
	if dir.length() < 0.001:
		return false
	var ray_dir := dir.normalized()
	var ray_origin := origin + ray_dir * 0.01
	for rect in get_world_rects_of_cells():
		if _ray_intersects_rect(ray_origin, ray_dir, max_dist, rect):
			return true
	return false

func _ray_intersects_rect(origin: Vector2, dir: Vector2, max_dist: float, rect: Rect2) -> bool:
	var t_min := -INF
	var t_max := INF
	var min_corner := rect.position
	var max_corner := rect.position + rect.size

	# X slab
	if absf(dir.x) < 0.0001:
		if origin.x < min_corner.x or origin.x > max_corner.x:
			return false
	else:
		var tx1 := (min_corner.x - origin.x) / dir.x
		var tx2 := (max_corner.x - origin.x) / dir.x
		if tx1 > tx2:
			var tmp := tx1
			tx1 = tx2
			tx2 = tmp
		t_min = maxf(t_min, tx1)
		t_max = minf(t_max, tx2)

	# Y slab
	if absf(dir.y) < 0.0001:
		if origin.y < min_corner.y or origin.y > max_corner.y:
			return false
	else:
		var ty1 := (min_corner.y - origin.y) / dir.y
		var ty2 := (max_corner.y - origin.y) / dir.y
		if ty1 > ty2:
			var tmp2 := ty1
			ty1 = ty2
			ty2 = tmp2
		t_min = maxf(t_min, ty1)
		t_max = minf(t_max, ty2)

	if t_max < 0.0:
		return false
	if t_min > t_max:
		return false
	return t_min <= max_dist

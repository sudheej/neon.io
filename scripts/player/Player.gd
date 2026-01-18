extends Node2D
class_name Player

const PlayerShapeScript = preload("res://scripts/player/PlayerShape.gd")
const WeaponSlot = preload("res://scripts/weapons/WeaponSlot.gd")

const MOVE_SPEED: float = 180.0
const ACCEL: float = 12.0
const EXPAND_COST: float = 6.0
var velocity: Vector2 = Vector2.ZERO
var xp: float = 300.0
var expand_mode: bool = false
var show_range: bool = false
var range_phase: float = 0.0

var move_command: Vector2 = Vector2.ZERO
var expand_command: bool = false
var place_command: Vector2i = Vector2i(99999, 99999)

var pulse_timer: float = 0.0
var pulses: Array[Dictionary] = []

@onready var shape = $PlayerShape
@onready var weapon_system = $WeaponSystem

func _ready() -> void:
	add_to_group("player")

func _process(delta: float) -> void:
	pulse_timer -= delta
	if pulse_timer <= 0.0:
		_spawn_pulse()
		pulse_timer = randf_range(0.15, 0.35)
	range_phase = fmod(range_phase + delta * 0.6, TAU)

	for i in range(pulses.size() - 1, -1, -1):
		pulses[i]["time"] -= delta
		if pulses[i]["time"] <= 0.0:
			pulses.remove_at(i)

	queue_redraw()

func _physics_process(delta: float) -> void:
	_update_commands()
	var target_vel = move_command.normalized() * MOVE_SPEED
	velocity = velocity.lerp(target_vel, 1.0 - pow(0.001, delta * ACCEL))
	global_position += velocity * delta

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("expand_mode"):
		expand_mode = !expand_mode
		expand_command = expand_mode
		queue_redraw()
	if event.is_action_pressed("select_next_slot"):
		weapon_system.select_next_slot()
		weapon_system.sync_armed_cell_to_selection()
		queue_redraw()
	if event.is_action_pressed("select_prev_slot"):
		weapon_system.select_prev_slot()
		weapon_system.sync_armed_cell_to_selection()
		queue_redraw()
	if event.is_action_pressed("toggle_range"):
		show_range = !show_range
		queue_redraw()
	if event.is_action_pressed("weapon_laser"):
		weapon_system.select_weapon_and_buy(WeaponSlot.WeaponType.LASER)
		queue_redraw()
	if event.is_action_pressed("weapon_stun"):
		weapon_system.select_weapon_and_buy(WeaponSlot.WeaponType.STUN)
		queue_redraw()
	if event.is_action_pressed("weapon_homing"):
		weapon_system.select_weapon_and_buy(WeaponSlot.WeaponType.HOMING)
		queue_redraw()

	if expand_mode and event.is_action_pressed("expand_place"):
		var grid_pos = local_to_grid(to_local(get_global_mouse_position()))
		place_command = grid_pos
		_try_place_cell(grid_pos)

func _update_commands() -> void:
	var x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	move_command = Vector2(x, y)

func add_xp(amount: float) -> void:
	xp += amount

func spend_xp(amount: float) -> bool:
	if xp < amount:
		return false
	xp -= amount
	return true

func local_to_grid(v: Vector2) -> Vector2i:
	return shape.local_to_grid(v)

func _try_place_cell(grid_pos: Vector2i) -> void:
	if xp < EXPAND_COST:
		return
	var valid = _get_valid_expand_cells().has(grid_pos)
	if not valid:
		return
	if shape.add_cell(grid_pos):
		xp -= EXPAND_COST
		weapon_system.on_shape_changed()
		queue_redraw()

func _get_valid_expand_cells() -> Array[Vector2i]:
	var valid: Array[Vector2i] = []
	var seen: Dictionary = {}
	for cell in shape.cells.keys():
		for dir in PlayerShapeScript.DIRS:
			var neighbor = cell + dir
			if shape.cells.has(neighbor):
				continue
			if seen.has(neighbor):
				continue
			seen[neighbor] = true
			valid.append(neighbor)
	return valid

func _draw() -> void:
	_draw_cells()
	if expand_mode:
		_draw_expand_ghosts()
	_draw_selected_slot_range()

func _draw_cells() -> void:
	var outline := Color(0.92, 0.96, 1.0, 0.9)
	var outline_active := Color(0.96, 1.0, 1.0, 1.0)
	var inner := Color(0.92, 0.96, 1.0, 0.25)
	var armed_cell: Vector2i = weapon_system.get_armed_cell()
	for grid_pos in shape.cells.keys():
		var local_pos = shape.grid_to_local(grid_pos)
		var half = PlayerShapeScript.CELL_SIZE * 0.5
		var rect = Rect2(local_pos - Vector2.ONE * half, Vector2.ONE * PlayerShapeScript.CELL_SIZE)
		var border_color := outline_active if grid_pos == armed_cell else outline
		var border_width := 2.0 if grid_pos == armed_cell else 1.2
		draw_rect(rect, border_color, false, border_width)
		draw_line(rect.position + Vector2(half, 0.0), rect.position + Vector2(half, rect.size.y), inner, 1.0)
		draw_line(rect.position + Vector2(0.0, half), rect.position + Vector2(rect.size.x, half), inner, 1.0)

		_draw_pulse_edges(rect)

func _draw_pulse_edges(rect: Rect2) -> void:
	for pulse in pulses:
		if pulse["grid_pos"] != shape.local_to_grid(rect.position + rect.size * 0.5):
			continue
		var t = pulse["time"] / pulse["life"]
		var color = Color(0.8, 0.95, 1.0, 0.6 * t)
		var p1 = rect.position
		var p2 = rect.position + Vector2(rect.size.x, 0.0)
		var p3 = rect.position + rect.size
		var p4 = rect.position + Vector2(0.0, rect.size.y)
		match pulse["dir"]:
			"N":
				draw_line(p1, p2, color, 2.0)
			"E":
				draw_line(p2, p3, color, 2.0)
			"S":
				draw_line(p4, p3, color, 2.0)
			"W":
				draw_line(p1, p4, color, 2.0)

func _draw_expand_ghosts() -> void:
	var color := Color(0.4, 0.9, 1.0, 0.35)
	for grid_pos in _get_valid_expand_cells():
		var local_pos = shape.grid_to_local(grid_pos)
		var half = PlayerShapeScript.CELL_SIZE * 0.5
		var rect = Rect2(local_pos - Vector2.ONE * half, Vector2.ONE * PlayerShapeScript.CELL_SIZE)
		_draw_dashed_rect(rect, color)

func _draw_dashed_rect(rect: Rect2, color: Color) -> void:
	var dash := 6.0
	var gap := 4.0
	_draw_dashed_line(rect.position, rect.position + Vector2(rect.size.x, 0.0), color, dash, gap)
	_draw_dashed_line(rect.position + Vector2(rect.size.x, 0.0), rect.position + rect.size, color, dash, gap)
	_draw_dashed_line(rect.position + rect.size, rect.position + Vector2(0.0, rect.size.y), color, dash, gap)
	_draw_dashed_line(rect.position + Vector2(0.0, rect.size.y), rect.position, color, dash, gap)

func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, dash: float, gap: float) -> void:
	var total = from.distance_to(to)
	var dir = (to - from).normalized()
	var dist = 0.0
	while dist < total:
		var seg_len = minf(dash, total - dist)
		var start = from + dir * dist
		var end = start + dir * seg_len
		draw_line(start, end, color, 1.2)
		dist += dash + gap

func _draw_selected_slot_range() -> void:
	if not show_range:
		return
	var slot = weapon_system.get_selected_slot()
	if slot == null:
		return
	var origin = weapon_system.get_slot_world_origin(slot)
	var local_origin = to_local(origin)
	var blocked = weapon_system.is_slot_blocked(slot)
	var glow = Color(0.6, 0.2, 0.2, 0.35) if blocked else Color(0.2, 0.9, 1.0, 0.25)
	var core = Color(0.9, 0.4, 0.4, 0.6) if blocked else Color(0.4, 1.0, 1.0, 0.75)
	_draw_dotted_ring(local_origin, slot.range, glow, 3.0, range_phase, 0.08, 0.12)
	_draw_dotted_ring(local_origin, slot.range, core, 1.4, range_phase + 0.3, 0.06, 0.12)

func _draw_ring(center: Vector2, radius: float, color: Color, width: float) -> void:
	draw_arc(center, radius, 0.0, TAU, 96, color, width)

func _draw_dotted_ring(
	center: Vector2,
	radius: float,
	color: Color,
	width: float,
	phase: float,
	dash_angle: float,
	gap_angle: float
) -> void:
	var angle := phase
	while angle < TAU + phase:
		var a0 := angle
		var a1 := minf(angle + dash_angle, TAU + phase)
		var p0 := center + Vector2(cos(a0), sin(a0)) * radius
		var p1 := center + Vector2(cos(a1), sin(a1)) * radius
		draw_line(p0, p1, color, width)
		angle += dash_angle + gap_angle

func _spawn_pulse() -> void:
	if shape.cells.is_empty():
		return
	var keys = shape.cells.keys()
	var grid_pos = keys[randi() % keys.size()]
	var dirs = ["N", "E", "S", "W"]
	pulses.append({"grid_pos": grid_pos, "dir": dirs[randi() % dirs.size()], "time": 0.2, "life": 0.2})

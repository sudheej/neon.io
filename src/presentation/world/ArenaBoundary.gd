extends Node2D

@export var half_size: Vector2 = Vector2(2300.0, 1520.0)
@export var wall_thickness: float = 46.0
@export var pulse_speed: float = 1.7
@export var base_color: Color = Color(0.2, 0.85, 1.0, 0.72)
@export var glow_color: Color = Color(0.2, 0.95, 1.0, 0.28)
@export var outer_dark_color: Color = Color(0.0, 0.0, 0.0, 0.44)
@export var outer_dark_width: float = 180.0
@export var shrink_enabled: bool = true
@export var shrink_start_time: float = 42.0
@export var shrink_rate: Vector2 = Vector2(3.2, 2.2)
@export var min_half_size: Vector2 = Vector2(980.0, 640.0)

var _pulse_t: float = 0.0
var _base_half_size: Vector2 = Vector2.ZERO
var _current_half_size: Vector2 = Vector2.ZERO

var _top_wall: StaticBody2D = null
var _bottom_wall: StaticBody2D = null
var _left_wall: StaticBody2D = null
var _right_wall: StaticBody2D = null

var _top_shape: RectangleShape2D = null
var _bottom_shape: RectangleShape2D = null
var _left_shape: RectangleShape2D = null
var _right_shape: RectangleShape2D = null

func _ready() -> void:
	add_to_group("arena_boundary")
	_base_half_size = half_size
	_current_half_size = half_size
	_rebuild_collision_walls()
	_sync_wall_shapes()

func _process(delta: float) -> void:
	_pulse_t = fmod(_pulse_t + delta * pulse_speed, TAU)
	_update_shrink()
	queue_redraw()

func clamp_point(point: Vector2, radius: float = 0.0) -> Vector2:
	var local = to_local(point)
	var rx = maxf(0.0, radius)
	var ry = maxf(0.0, radius)
	local.x = clampf(local.x, -_current_half_size.x + rx, _current_half_size.x - rx)
	local.y = clampf(local.y, -_current_half_size.y + ry, _current_half_size.y - ry)
	return to_global(local)

func clamp_point_extents(point: Vector2, left: float, right: float, top: float, bottom: float) -> Vector2:
	var local = to_local(point)
	local.x = _clamp_axis_with_extents(local.x, _current_half_size.x, left, right)
	local.y = _clamp_axis_with_extents(local.y, _current_half_size.y, top, bottom)
	return to_global(local)

func get_inner_rect_global() -> Rect2:
	var top_left = to_global(-_current_half_size)
	return Rect2(top_left, _current_half_size * 2.0)

func _draw() -> void:
	var rect = Rect2(-_current_half_size, _current_half_size * 2.0)
	_draw_outer_darkness(rect)
	var pulse = 0.5 + 0.5 * sin(_pulse_t)
	var width_outer = 3.0 + pulse * 1.6
	var width_inner = 1.6 + pulse * 0.9
	draw_rect(rect.grow(9.0 + pulse * 8.0), Color(glow_color.r, glow_color.g, glow_color.b, glow_color.a * (0.35 + pulse * 0.3)), false, width_outer)
	draw_rect(rect.grow(4.0 + pulse * 3.0), Color(glow_color.r, glow_color.g, glow_color.b, glow_color.a * (0.45 + pulse * 0.35)), false, width_inner)
	draw_rect(rect, base_color, false, 2.4 + pulse * 0.9)

func _draw_outer_darkness(rect: Rect2) -> void:
	var pad = maxf(0.0, outer_dark_width)
	if pad <= 0.0 or outer_dark_color.a <= 0.0:
		return
	var min_x = rect.position.x
	var min_y = rect.position.y
	var max_x = rect.position.x + rect.size.x
	var max_y = rect.position.y + rect.size.y
	draw_rect(Rect2(min_x - pad, min_y - pad, rect.size.x + pad * 2.0, pad), outer_dark_color, true)
	draw_rect(Rect2(min_x - pad, max_y, rect.size.x + pad * 2.0, pad), outer_dark_color, true)
	draw_rect(Rect2(min_x - pad, min_y, pad, rect.size.y), outer_dark_color, true)
	draw_rect(Rect2(max_x, min_y, pad, rect.size.y), outer_dark_color, true)

func _clamp_axis_with_extents(axis_pos: float, half_extent: float, min_extent: float, max_extent: float) -> float:
	var min_margin = maxf(0.0, min_extent)
	var max_margin = maxf(0.0, max_extent)
	var min_pos = -half_extent + min_margin
	var max_pos = half_extent - max_margin
	if min_pos > max_pos:
		return (min_pos + max_pos) * 0.5
	return clampf(axis_pos, min_pos, max_pos)

func _rebuild_collision_walls() -> void:
	for child in get_children():
		if child is StaticBody2D:
			child.queue_free()
	_top_wall = _add_wall("TopWall")
	_bottom_wall = _add_wall("BottomWall")
	_left_wall = _add_wall("LeftWall")
	_right_wall = _add_wall("RightWall")
	_top_shape = _top_wall.get_child(0).shape as RectangleShape2D
	_bottom_shape = _bottom_wall.get_child(0).shape as RectangleShape2D
	_left_shape = _left_wall.get_child(0).shape as RectangleShape2D
	_right_shape = _right_wall.get_child(0).shape as RectangleShape2D

func _add_wall(wall_name: String) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = wall_name
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	shape.shape = rect
	body.add_child(shape)
	add_child(body)
	return body

func _sync_wall_shapes() -> void:
	if _top_wall == null or _bottom_wall == null or _left_wall == null or _right_wall == null:
		return
	var t = maxf(wall_thickness, 8.0)
	var span = _current_half_size * 2.0
	_top_wall.position = Vector2(0.0, -_current_half_size.y - t * 0.5)
	_bottom_wall.position = Vector2(0.0, _current_half_size.y + t * 0.5)
	_left_wall.position = Vector2(-_current_half_size.x - t * 0.5, 0.0)
	_right_wall.position = Vector2(_current_half_size.x + t * 0.5, 0.0)
	_top_shape.size = Vector2(span.x + t * 2.0, t)
	_bottom_shape.size = Vector2(span.x + t * 2.0, t)
	_left_shape.size = Vector2(t, span.y + t * 2.0)
	_right_shape.size = Vector2(t, span.y + t * 2.0)

func _update_shrink() -> void:
	if not shrink_enabled:
		return
	var world = get_tree().get_first_node_in_group("world")
	if world == null:
		return
	var elapsed = float(world.get("elapsed"))
	if elapsed < shrink_start_time:
		return
	var dt = elapsed - shrink_start_time
	var target = _base_half_size - (shrink_rate * dt)
	target.x = maxf(target.x, min_half_size.x)
	target.y = maxf(target.y, min_half_size.y)
	if target.distance_to(_current_half_size) <= 0.01:
		return
	_current_half_size = target
	_sync_wall_shapes()

extends Node2D
class_name LaserShot

const LIFE: float = 0.12
const LaserShader = preload("res://scripts/weapons/projectiles/LaserGlow.gdshader")

var start_pos: Vector2
var end_pos: Vector2
var time_left: float = LIFE
var origin_node: Node2D = null
var target_node: Node2D = null
var origin_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	var mat = ShaderMaterial.new()
	mat.shader = LaserShader
	material = mat
	add_to_group("projectiles")

func setup(
	p_start: Vector2,
	p_end: Vector2,
	p_origin_node: Node2D = null,
	p_origin_offset: Vector2 = Vector2.ZERO,
	p_target_node: Node2D = null
) -> void:
	start_pos = p_start
	end_pos = p_end
	origin_node = p_origin_node
	origin_offset = p_origin_offset
	target_node = p_target_node
	global_position = start_pos
	queue_redraw()

func _process(delta: float) -> void:
	time_left -= delta
	if time_left <= 0.0:
		queue_free()
	else:
		if origin_node != null and is_instance_valid(origin_node):
			start_pos = origin_node.global_position + origin_offset
			global_position = start_pos
		if target_node != null and is_instance_valid(target_node):
			end_pos = target_node.global_position
		queue_redraw()

func _draw() -> void:
	if time_left <= 0.0:
		return
	var t := time_left / LIFE
	var color := Color(0.4, 1.0, 1.0, 0.6 * t)
	var core := Color(0.8, 1.0, 1.0, 0.9 * t)
	draw_line(Vector2.ZERO, to_local(end_pos), color, 3.0)
	draw_line(Vector2.ZERO, to_local(end_pos), core, 1.0)

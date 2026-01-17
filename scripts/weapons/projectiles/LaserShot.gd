extends Node2D
class_name LaserShot

const LIFE: float = 0.12

var start_pos: Vector2
var end_pos: Vector2
var time_left: float = LIFE

func setup(p_start: Vector2, p_end: Vector2) -> void:
	start_pos = p_start
	end_pos = p_end
	queue_redraw()

func _process(delta: float) -> void:
	time_left -= delta
	if time_left <= 0.0:
		queue_free()
	else:
		queue_redraw()

func _draw() -> void:
	if time_left <= 0.0:
		return
	var t := time_left / LIFE
	var color := Color(0.4, 1.0, 1.0, 0.6 * t)
	var core := Color(0.8, 1.0, 1.0, 0.9 * t)
	draw_line(to_local(start_pos), to_local(end_pos), color, 3.0)
	draw_line(to_local(start_pos), to_local(end_pos), core, 1.0)

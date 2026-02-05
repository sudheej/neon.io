extends Node2D

const CELL_SIZE: float = 32.0
const MAJOR_STEP: int = 5

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var vp_size := get_viewport_rect().size
	var top_left := cam.global_position - vp_size * 0.5
	var bottom_right := cam.global_position + vp_size * 0.5

	var bg_rect := Rect2(top_left, vp_size)
	draw_rect(bg_rect, Color(0.03, 0.05, 0.1, 1.0), true)

	var start_x: float = floor(top_left.x / CELL_SIZE) * CELL_SIZE
	var end_x: float = bottom_right.x
	var start_y: float = floor(top_left.y / CELL_SIZE) * CELL_SIZE
	var end_y: float = bottom_right.y

	var minor := Color(0.1, 0.2, 0.35, 0.35)
	var major := Color(0.2, 0.5, 0.8, 0.55)

	var x: float = start_x
	while x <= end_x:
		var is_major := int(roundi(x / CELL_SIZE)) % MAJOR_STEP == 0
		var color := major if is_major else minor
		var width := 1.4 if is_major else 1.0
		draw_line(Vector2(x, top_left.y), Vector2(x, bottom_right.y), color, width)
		x += CELL_SIZE

	var y: float = start_y
	while y <= end_y:
		var is_major_y := int(roundi(y / CELL_SIZE)) % MAJOR_STEP == 0
		var color_y := major if is_major_y else minor
		var width_y := 1.4 if is_major_y else 1.0
		draw_line(Vector2(top_left.x, y), Vector2(bottom_right.x, y), color_y, width_y)
		y += CELL_SIZE

	_draw_corner_ticks(start_x, start_y, end_x, end_y)

func _draw_corner_ticks(start_x: float, start_y: float, end_x: float, end_y: float) -> void:
	var tick := 6.0
	var color := Color(0.2, 0.7, 0.9, 0.25)
	var x: float = start_x
	while x <= end_x:
		if int(roundi(x / CELL_SIZE)) % MAJOR_STEP == 0:
			var y: float = start_y
			while y <= end_y:
				if int(roundi(y / CELL_SIZE)) % MAJOR_STEP == 0:
					draw_line(Vector2(x, y), Vector2(x + tick, y), color, 1.0)
					draw_line(Vector2(x, y), Vector2(x, y + tick), color, 1.0)
				y += CELL_SIZE * MAJOR_STEP
		x += CELL_SIZE * MAJOR_STEP

extends Node2D

const WIDTH: float = 26.0
const HEIGHT: float = 4.0
const OFFSET_Y: float = -24.0
const LERP_SPEED: float = 6.0
const DROP_LERP_MULT: float = 2.4
const RISE_LERP_MULT: float = 0.9

var display_ratio: float = 1.0

func _process(_delta: float) -> void:
	var parent = get_parent()
	if parent != null and parent.has_method("get"):
		var max_health = parent.get("max_health")
		var health = parent.get("health")
		if max_health != null and health != null and float(max_health) > 0.0:
			var target_ratio = clamp(float(health) / float(max_health), 0.0, 1.0)
			var lerp_speed := LERP_SPEED
			var is_ai = parent.get("is_ai")
			if is_ai != null and not bool(is_ai):
				lerp_speed *= 0.9
			if target_ratio < display_ratio:
				lerp_speed *= DROP_LERP_MULT
			else:
				lerp_speed *= RISE_LERP_MULT
			display_ratio = lerpf(display_ratio, target_ratio, 1.0 - pow(0.001, _delta * lerp_speed))
	queue_redraw()

func _draw() -> void:
	var parent = get_parent()
	if parent == null:
		return
	if not parent.has_method("get"):
		return
	var max_health = parent.get("max_health")
	var health = parent.get("health")
	var flash = parent.get("damage_flash")
	if max_health == null or health == null:
		return
	var ratio = display_ratio
	var pos = Vector2(-WIDTH * 0.5, OFFSET_Y)
	var bg = Color(0.05, 0.1, 0.15, 0.8)
	var fg = Color(0.2, 0.9, 0.4, 0.9)
	var hit = Color(1.0, 0.4, 0.2, 0.9)
	draw_rect(Rect2(pos, Vector2(WIDTH, HEIGHT)), bg, true)
	var bar_color = hit if float(flash) > 0.0 else fg
	draw_rect(Rect2(pos, Vector2(WIDTH * ratio, HEIGHT)), bar_color, true)

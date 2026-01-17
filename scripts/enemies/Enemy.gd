extends Node2D
class_name Enemy

const SIZE: float = 20.0

var health: float = 20.0
var base_speed: float = 60.0
var current_speed: float = 60.0
var wander_dir: Vector2 = Vector2.RIGHT
var wander_time: float = 0.0
var stun_time: float = 0.0

func _ready() -> void:
	add_to_group("enemies")
	_randomize_dir()

func _process(delta: float) -> void:
	wander_time -= delta
	if wander_time <= 0.0:
		_randomize_dir()

	if stun_time > 0.0:
		stun_time -= delta
		current_speed = base_speed * 0.4
	else:
		current_speed = base_speed

	global_position += wander_dir * current_speed * delta
	queue_redraw()

func _randomize_dir() -> void:
	wander_dir = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	wander_time = randf_range(1.0, 2.2)

func apply_damage(amount: float, stun_duration: float) -> void:
	health -= amount
	if stun_duration > 0.0:
		stun_time = maxf(stun_time, stun_duration)
	if health <= 0.0:
		queue_free()

func _draw() -> void:
	var half := SIZE * 0.5
	var rect := Rect2(Vector2(-half, -half), Vector2.ONE * SIZE)
	draw_rect(rect, Color(0.1, 0.9, 0.6, 0.1), true)
	draw_rect(rect, Color(0.1, 0.9, 0.6, 0.8), false, 1.2)

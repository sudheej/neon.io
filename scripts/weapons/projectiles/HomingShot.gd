extends Node2D
class_name HomingShot

const LIFE: float = 4.0
const SPEED_START: float = 90.0
const SPEED_MAX: float = 520.0
const ACCEL: float = 520.0
const HIT_RADIUS: float = 6.0
const GlowShader = preload("res://scripts/weapons/projectiles/LaserGlow.gdshader")

var target: Node2D = null
var time_left: float = LIFE
var velocity: Vector2 = Vector2.ZERO
var trail: Array[Vector2] = []
const TRAIL_POINTS: int = 10
var damage: float = 0.0
var source: Node = null

func _ready() -> void:
	var mat = ShaderMaterial.new()
	mat.shader = GlowShader
	material = mat
	add_to_group("homing_missiles")
	add_to_group("projectiles")

func setup(start_pos: Vector2, target_node: Node2D, damage_amount: float, source_node: Node = null) -> void:
	global_position = start_pos
	target = target_node
	damage = damage_amount
	source = source_node
	queue_redraw()

func _process(delta: float) -> void:
	time_left -= delta
	if time_left <= 0.0:
		queue_free()
		return
	if target != null and is_instance_valid(target):
		var dir = (target.global_position - global_position)
		var dist = dir.length()
		if dist <= HIT_RADIUS:
			if target.has_method("apply_damage"):
				if source != null and is_instance_valid(source):
					target.apply_damage(damage, 0.0, source)
				else:
					target.apply_damage(damage, 0.0, null)
			queue_free()
			return
		var desired = dir.normalized()
		var speed = velocity.length()
		speed = minf(speed + ACCEL * delta, SPEED_MAX)
		if speed < SPEED_START:
			speed = SPEED_START
		velocity = velocity.lerp(desired * speed, 0.25)
	else:
		var speed = velocity.length()
		speed = minf(speed + ACCEL * delta, SPEED_MAX)
		if speed < SPEED_START:
			speed = SPEED_START
		if velocity.length() < 0.001:
			velocity = Vector2.RIGHT * speed
		else:
			velocity = velocity.normalized() * speed
	var step = minf(velocity.length() * delta, 1000.0)
	global_position += velocity.normalized() * step
	trail.append(global_position)
	if trail.size() > TRAIL_POINTS:
		trail.remove_at(0)
	queue_redraw()

func _draw() -> void:
	var t = time_left / LIFE
	var core = Color(1.0, 0.6, 0.15, 0.9 * t)
	var glow = Color(1.0, 0.5, 0.1, 0.55 * t)
	for i in range(1, trail.size()):
		var p0 = to_local(trail[i - 1])
		var p1 = to_local(trail[i])
		var w = lerpf(1.0, 3.0, float(i) / float(TRAIL_POINTS))
		draw_line(p0, p1, glow, w)
	draw_circle(Vector2.ZERO, 6.0, glow)
	draw_circle(Vector2.ZERO, 3.2, core)

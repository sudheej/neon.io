extends Node2D
class_name Enemy

const SIZE: float = 20.0
const XP_ON_KILL: float = 5.0
const SPAWN_DURATION: float = 0.3
const DEATH_DURATION: float = 0.4

var health: float = 20.0
var base_speed: float = 60.0
var current_speed: float = 60.0
var wander_dir: Vector2 = Vector2.RIGHT
var wander_time: float = 0.0
var stun_time: float = 0.0
var spawn_timer: float = 0.0
var death_timer: float = 0.0
var is_dying: bool = false

func _ready() -> void:
	add_to_group("enemies")
	_randomize_dir()
	spawn_timer = SPAWN_DURATION
	modulate.a = 0.0

func _process(delta: float) -> void:
	if is_dying:
		_update_death_fx(delta)
		queue_redraw()
		return
	if spawn_timer > 0.0:
		spawn_timer = maxf(spawn_timer - delta, 0.0)
		var t := _get_spawn_t()
		modulate.a = t
	else:
		modulate.a = 1.0
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

func apply_damage(amount: float, stun_duration: float, _source: Node = null, _weapon_type: int = -1) -> void:
	health -= amount
	if stun_duration > 0.0:
		stun_time = maxf(stun_time, stun_duration)
	if health <= 0.0 and not is_dying:
		_grant_xp()
		_start_death()

func _grant_xp() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("add_xp"):
		player.add_xp(XP_ON_KILL)

func _draw() -> void:
	var half := SIZE * 0.5
	var rect := Rect2(Vector2(-half, -half), Vector2.ONE * SIZE)
	draw_rect(rect, Color(0.1, 0.9, 0.6, 0.1), true)
	draw_rect(rect, Color(0.1, 0.9, 0.6, 0.8), false, 1.2)
	_draw_death_fx()
	_draw_spawn_fx()

func _get_spawn_t() -> float:
	if SPAWN_DURATION <= 0.0:
		return 1.0
	var raw := 1.0 - (spawn_timer / SPAWN_DURATION)
	var clamped := clampf(raw, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)

func _draw_spawn_fx() -> void:
	if spawn_timer <= 0.0:
		return
	var t := _get_spawn_t()
	var expand := lerpf(1.8, 1.0, t)
	var glow := Color(0.2, 1.0, 0.7, 0.6 * (1.0 - t))
	var half := SIZE * 0.5 * expand
	var rect := Rect2(Vector2(-half, -half), Vector2.ONE * SIZE * expand)
	draw_rect(rect, glow, false, 2.0)

func _start_death() -> void:
	is_dying = true
	death_timer = DEATH_DURATION

func _update_death_fx(delta: float) -> void:
	if death_timer <= 0.0:
		queue_free()
		return
	death_timer = maxf(death_timer - delta, 0.0)
	var t := _get_death_t()
	modulate.a = t
	scale = Vector2.ONE * lerpf(1.0, 0.3, 1.0 - t)
	if death_timer <= 0.0:
		queue_free()

func _get_death_t() -> float:
	if DEATH_DURATION <= 0.0:
		return 0.0
	var raw := death_timer / DEATH_DURATION
	return clampf(raw, 0.0, 1.0)

func _draw_death_fx() -> void:
	if not is_dying:
		return
	var t := _get_death_t()
	var flash := Color(1.0, 0.6, 0.2, 0.85 * (1.0 - t))
	var expand := lerpf(1.0, 1.9, 1.0 - t)
	var half := SIZE * 0.5 * expand
	var rect := Rect2(Vector2(-half, -half), Vector2.ONE * SIZE * expand)
	draw_rect(rect, flash, false, 2.2)

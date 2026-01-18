extends Node2D
class_name World

const WeaponSlot = preload("res://scripts/weapons/WeaponSlot.gd")

const ENEMY_COUNT: int = 10
const ENEMY_SPAWN_RADIUS: float = 260.0
const MAX_ENEMIES: int = 16
const SPAWN_INTERVAL: float = 1.8

var spawn_timer: float = 0.0

@onready var player = $Player
@onready var enemies_root = $Enemies
@onready var camera = $Camera2D
@onready var hud_label: Label = $HUD/Info
@onready var weapon_legend: Label = $HUD/WeaponLegend

func _ready() -> void:
	add_to_group("world")
	_randomize_enemies()
	spawn_timer = SPAWN_INTERVAL

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart_game"):
		get_tree().reload_current_scene()

func _process(delta: float) -> void:
	camera.global_position = player.global_position
	var enemies: Array[Node] = _get_enemy_list()
	player.weapon_system.process_weapons(delta, enemies)
	_update_hud(enemies)
	_update_weapon_legend()
	_maybe_spawn_enemy(delta, enemies.size())

func _get_enemy_list() -> Array[Node]:
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemies")
	enemies.sort_custom(func(a, b): return a.get_instance_id() < b.get_instance_id())
	return enemies

func _randomize_enemies() -> void:
	for i in range(ENEMY_COUNT):
		_spawn_enemy()

func _spawn_enemy() -> void:
	var enemy_scene := preload("res://scenes/Enemy.tscn")
	var enemy := enemy_scene.instantiate() as Node2D
	var angle := randf_range(0.0, TAU)
	var radius := randf_range(120.0, ENEMY_SPAWN_RADIUS)
	enemy.global_position = player.global_position + Vector2(cos(angle), sin(angle)) * radius
	enemies_root.add_child(enemy)

func _maybe_spawn_enemy(delta: float, enemy_count: int) -> void:
	spawn_timer -= delta
	if spawn_timer > 0.0:
		return
	spawn_timer = SPAWN_INTERVAL
	if enemy_count >= MAX_ENEMIES:
		return
	_spawn_enemy()

func _update_hud(enemies: Array[Node]) -> void:
	if hud_label == null:
		return
	hud_label.text = "Credits: %.1f\nEnemies: %d\n[R] Restart" % [player.xp, enemies.size()]

func _update_weapon_legend() -> void:
	if weapon_legend == null:
		return
	var weapon_type = player.weapon_system.get_selected_weapon_type()
	var laser_cost = player.weapon_system.get_weapon_pack_cost(WeaponSlot.WeaponType.LASER)
	var stun_cost = player.weapon_system.get_weapon_pack_cost(WeaponSlot.WeaponType.STUN)
	var homing_cost = player.weapon_system.get_weapon_pack_cost(WeaponSlot.WeaponType.HOMING)
	var laser_ammo = player.weapon_system.get_weapon_ammo(WeaponSlot.WeaponType.LASER)
	var stun_ammo = player.weapon_system.get_weapon_ammo(WeaponSlot.WeaponType.STUN)
	var homing_ammo = player.weapon_system.get_weapon_ammo(WeaponSlot.WeaponType.HOMING)
	var laser_pack = player.weapon_system.get_weapon_pack_ammo(WeaponSlot.WeaponType.LASER)
	var stun_pack = player.weapon_system.get_weapon_pack_ammo(WeaponSlot.WeaponType.STUN)
	var homing_pack = player.weapon_system.get_weapon_pack_ammo(WeaponSlot.WeaponType.HOMING)
	weapon_legend.text = "%s 1 Laser  Ammo:%d  (+%d/%.0f)\n%s 2 Stun   Ammo:%d  (+%d/%.0f)\n%s 3 Homing Ammo:%d  (+%d/%.0f)" % [
		">" if weapon_type == WeaponSlot.WeaponType.LASER else " ",
		laser_ammo,
		laser_pack,
		laser_cost,
		">" if weapon_type == WeaponSlot.WeaponType.STUN else " ",
		stun_ammo,
		stun_pack,
		stun_cost,
		">" if weapon_type == WeaponSlot.WeaponType.HOMING else " ",
		homing_ammo,
		homing_pack,
		homing_cost
	]

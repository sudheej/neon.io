extends Node2D
class_name World

const WeaponSlot = preload("res://scripts/weapons/WeaponSlot.gd")

const ENEMY_START: int = 5
const ENEMY_SPAWN_RADIUS: float = 260.0
const MAX_ENEMIES: int = 16
const SPAWN_INTERVAL: float = 2.4
const SPAWN_RAMP_SECONDS: float = 25.0
const PlayerScene = preload("res://scenes/Player.tscn")
const AIControllerScript = preload("res://scripts/ai/AIController.gd")

var spawn_timer: float = 0.0
var elapsed: float = 0.0
var game_over: bool = false
var game_over_pulse: float = 0.0

@onready var player = $Player
@onready var enemies_root = $Enemies
@onready var camera = $Camera2D
@onready var hud_label: Label = $HUD/Info
@onready var weapon_legend: Label = $HUD/WeaponLegend
@onready var game_over_layer: CanvasLayer = $GameOver
@onready var game_over_time: Label = $GameOver/TimeSurvived

func _ready() -> void:
	add_to_group("world")
	_randomize_enemies()
	spawn_timer = SPAWN_INTERVAL
	if player != null and player.has_signal("died"):
		player.died.connect(_on_player_died)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart_game"):
		get_tree().reload_current_scene()

func _process(delta: float) -> void:
	if game_over:
		game_over_pulse = fmod(game_over_pulse + delta, TAU)
		_update_game_over_time()
		return
	if player == null or not is_instance_valid(player):
		return
	camera.global_position = player.global_position
	elapsed += delta
	var combatants: Array[Node] = _get_combatants()
	_process_combatants(delta, combatants)
	_update_hud(combatants)
	_update_weapon_legend()
	_maybe_spawn_enemy(delta, combatants.size() - 1)

func _get_combatants() -> Array[Node]:
	var list: Array[Node] = get_tree().get_nodes_in_group("combatants")
	list.sort_custom(func(a, b): return a.get_instance_id() < b.get_instance_id())
	return list

func _process_combatants(delta: float, combatants: Array[Node]) -> void:
	for entity in combatants:
		var node = entity as Node
		if node == null:
			continue
		if not node.has_node("WeaponSystem"):
			continue
		var system = node.get_node("WeaponSystem")
		var targets = combatants.filter(func(item): return item != node)
		system.process_weapons(delta, targets)

func _randomize_enemies() -> void:
	for i in range(ENEMY_START):
		_spawn_enemy()

func _spawn_enemy() -> void:
	var enemy = PlayerScene.instantiate() as Node2D
	var angle = randf_range(0.0, TAU)
	var radius = randf_range(120.0, ENEMY_SPAWN_RADIUS)
	enemy.global_position = player.global_position + Vector2(cos(angle), sin(angle)) * radius
	var ai = AIControllerScript.new()
	enemy.add_child(ai)
	enemies_root.add_child(enemy)

func _maybe_spawn_enemy(delta: float, enemy_count: int) -> void:
	spawn_timer -= delta
	if spawn_timer > 0.0:
		return
	spawn_timer = SPAWN_INTERVAL
	var cap = _current_enemy_cap()
	if enemy_count >= cap:
		return
	_spawn_enemy()

func _update_hud(combatants: Array[Node]) -> void:
	if hud_label == null:
		return
	var enemy_count = max(combatants.size() - 1, 0)
	hud_label.text = "Credits: %.1f\nEnemies: %d\n[R] Restart" % [player.xp, enemy_count]

func _current_enemy_cap() -> int:
	var ramp = int(floor(elapsed / SPAWN_RAMP_SECONDS))
	return clamp(ENEMY_START + ramp, ENEMY_START, MAX_ENEMIES)

func _on_player_died(_victim: Node) -> void:
	game_over = true
	game_over_pulse = 0.0
	if game_over_layer != null:
		game_over_layer.visible = true
	_update_game_over_time()

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

func _update_game_over_time() -> void:
	if game_over_time == null:
		return
	var total = int(round(elapsed))
	var hours = total / 3600
	var minutes = (total % 3600) / 60
	var seconds = total % 60
	game_over_time.text = "Time Survived: %02d:%02d:%02d" % [hours, minutes, seconds]
	var pulse = 0.9 + 0.12 * sin(game_over_pulse * 2.0)
	game_over_time.modulate = Color(1.0, 1.0, 1.0, pulse)

extends Node2D

const WeaponSlot = preload("res://src/domain/weapons/WeaponSlot.gd")

const ENEMY_START: int = 5
const ENEMY_SPAWN_RADIUS: float = 260.0
const MAX_ENEMIES: int = 16
const SPAWN_INTERVAL: float = 2.2
const SURGE_CYCLE_SECONDS: float = 36.0
const SURGE_DURATION_SECONDS: float = 8.0
const SURGE_SPAWN_MULT: float = 0.7
const SPAWN_RAMP_SECONDS: float = 25.0
const DANGER_WINDOW_SECONDS: float = 6.0
const KILL_REWARD_DANGER_MULT: float = 1.35
const TELEMETRY_INTERVAL: float = 10.0
const LOW_HEALTH_THRESHOLD: float = 0.4
const LOW_HEALTH_HYSTERESIS: float = 0.005
const LOW_HEALTH_BANNER_DURATION: float = 1.2
const PlayerScene = preload("res://src/presentation/scenes/Player.tscn")
const AIControllerScript = preload("res://src/input/AIInputSource.gd")

var spawn_timer: float = 0.0
var elapsed: float = 0.0
var game_over: bool = false
var game_over_pulse: float = 0.0
var pending_hud_shot: bool = false
var input_enabled: bool = true
var camera_follow_speed: float = 6.0
var telemetry_enabled: bool = true
var telemetry_timer: float = TELEMETRY_INTERVAL
var low_health_alert_active: bool = false
var low_health_banner_timer: float = 0.0

@onready var player = $Player
@onready var enemies_root = $Enemies
@onready var camera = $Camera2D
@onready var hud_label: Label = $HUD/InfoPanel/Body/Info
@onready var low_health_banner = $HUD/LowHealthBanner
@onready var game_over_layer: CanvasLayer = $GameOver
@onready var game_over_time: Label = $GameOver/TimeSurvived

func _ready() -> void:
	add_to_group("world")
	_randomize_enemies()
	spawn_timer = _current_spawn_interval()
	if OS.get_cmdline_args().has("--no-telemetry"):
		telemetry_enabled = false
	if player != null and player.has_signal("died"):
		player.died.connect(_on_player_died)
	_maybe_schedule_hud_screenshot()

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event.is_action_pressed("restart_game"):
		get_tree().reload_current_scene()

func _process(delta: float) -> void:
	if game_over:
		game_over_pulse = fmod(game_over_pulse + delta, TAU)
		_update_game_over_time()
		return
	if player == null or not is_instance_valid(player):
		return
	var focus = player.global_position
	if player.has_method("get_active_cell_world_pos"):
		focus = player.get_active_cell_world_pos()
	if camera != null:
		var t = 1.0 - exp(-camera_follow_speed * delta)
		camera.global_position = camera.global_position.lerp(focus, t)
	elapsed += delta
	var combatants: Array[Node] = _get_combatants()
	if telemetry_enabled:
		telemetry_timer -= delta
		if telemetry_timer <= 0.0:
			telemetry_timer = TELEMETRY_INTERVAL
			_log_telemetry(combatants)
	_process_combatants(delta, combatants)
	_update_hud(combatants)
	_update_announcements(delta)
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
	if player == null:
		return
	var enemy_radius = 16.0
	if enemy.has_method("get_collision_radius"):
		enemy_radius = float(enemy.get_collision_radius())
	var player_radius = 16.0
	if player.has_method("get_collision_radius"):
		player_radius = float(player.get_collision_radius())
	var min_radius = maxf(120.0, player_radius + enemy_radius + 12.0)
	var combatants = _get_combatants()
	var pos = player.global_position
	for _i in range(12):
		var angle = randf_range(0.0, TAU)
		var radius = randf_range(min_radius, ENEMY_SPAWN_RADIUS)
		var candidate = player.global_position + Vector2(cos(angle), sin(angle)) * radius
		var ok = true
		for entity in combatants:
			var node = entity as Node2D
			if node == null:
				continue
			var other_radius = 16.0
			if node.has_method("get_collision_radius"):
				other_radius = float(node.get_collision_radius())
			if candidate.distance_to(node.global_position) < (other_radius + enemy_radius + 8.0):
				ok = false
				break
		if ok:
			pos = candidate
			break
		pos = candidate
	enemy.global_position = pos
	var ai = AIControllerScript.new()
	var game_world = get_tree().get_first_node_in_group("game_world")
	if game_world != null and game_world.has_method("get_command_queue"):
		var queue = game_world.get_command_queue()
		if ai.has_method("set_command_queue"):
			ai.set_command_queue(queue)
	enemy.add_child(ai)
	enemies_root.add_child(enemy)
	if enemy.has_method("set_ai_enabled"):
		enemy.set_ai_enabled(true)

func _maybe_spawn_enemy(delta: float, enemy_count: int) -> void:
	spawn_timer -= delta
	if spawn_timer > 0.0:
		return
	spawn_timer = _current_spawn_interval()
	var cap = _current_enemy_cap()
	if enemy_count >= cap:
		return
	_spawn_enemy()

func _update_hud(combatants: Array[Node]) -> void:
	if hud_label == null:
		return
	if player == null or not is_instance_valid(player):
		return
	if player.get("xp") == null:
		return
	var enemy_count = max(combatants.size() - 1, 0)
	hud_label.text = "CREDITS: %.1f\nENEMIES: %d\n[R] RESTART" % [player.xp, enemy_count]

func _current_enemy_cap() -> int:
	var ramp = int(floor(elapsed / SPAWN_RAMP_SECONDS))
	return clamp(ENEMY_START + ramp, ENEMY_START, MAX_ENEMIES)

func _current_spawn_interval() -> float:
	if _is_surge_active():
		return SPAWN_INTERVAL * SURGE_SPAWN_MULT
	return SPAWN_INTERVAL

func _is_surge_active() -> bool:
	if SURGE_CYCLE_SECONDS <= 0.0 or elapsed < SURGE_CYCLE_SECONDS:
		return false
	return fmod(elapsed, SURGE_CYCLE_SECONDS) < SURGE_DURATION_SECONDS

func get_kill_reward_multiplier() -> float:
	if SPAWN_RAMP_SECONDS <= 0.0:
		return 1.0
	var cycle = fmod(elapsed, SPAWN_RAMP_SECONDS)
	if cycle < DANGER_WINDOW_SECONDS:
		return KILL_REWARD_DANGER_MULT
	return 1.0

func _on_player_died(_victim: Node) -> void:
	game_over = true
	game_over_pulse = 0.0
	if low_health_banner != null and low_health_banner.has_method("hide_announcement"):
		low_health_banner.hide_announcement()
	if telemetry_enabled:
		_log_telemetry(_get_combatants())
		_log_telemetry_summary()
	if game_over_layer != null:
		game_over_layer.visible = true
	_update_game_over_time()

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

func _maybe_schedule_hud_screenshot() -> void:
	var args = OS.get_cmdline_args()
	if not args.has("--hud-shot"):
		return
	if pending_hud_shot:
		return
	var delay := 1.2
	var path := "user://hud_shot.png"
	for arg in args:
		if arg.begins_with("--hud-shot-delay="):
			delay = float(arg.get_slice("=", 1))
		elif arg.begins_with("--hud-shot-path="):
			path = arg.get_slice("=", 1)
	pending_hud_shot = true
	call_deferred("_do_hud_screenshot", delay, path)

func _do_hud_screenshot(delay: float, path: String) -> void:
	await get_tree().create_timer(delay).timeout
	await get_tree().process_frame
	var image = get_viewport().get_texture().get_image()
	if image != null:
		image.save_png(path)

func request_restart() -> void:
	get_tree().reload_current_scene()

func _log_telemetry(combatants: Array[Node]) -> void:
	if player == null or not is_instance_valid(player):
		return
	var enemy_count = max(combatants.size() - 1, 0)
	var xp_val = float(player.get("xp"))
	var expansions = int(player.get("expansions_bought"))
	var cells = 1
	if player.has_node("PlayerShape"):
		var shape = player.get_node("PlayerShape")
		if shape != null:
			var shape_cells = shape.get("cells")
			if shape_cells is Dictionary:
				cells = max(1, (shape_cells as Dictionary).size())
	var usage_text = _weapon_usage_text()
	print(
		"[telemetry] t=%.1fs credits=%.1f cells=%d expansions=%d enemies=%d surge=%d usage={%s}" %
		[elapsed, xp_val, cells, expansions, enemy_count, 1 if _is_surge_active() else 0, usage_text]
	)

func _log_telemetry_summary() -> void:
	if player == null or not is_instance_valid(player):
		return
	var xp_val = float(player.get("xp"))
	var expansions = int(player.get("expansions_bought"))
	var usage_text = _weapon_usage_text()
	print(
		"[telemetry-summary] survived=%.1fs credits=%.1f expansions=%d surge=%d usage={%s}" %
		[elapsed, xp_val, expansions, 1 if _is_surge_active() else 0, usage_text]
	)

func _weapon_usage_text() -> String:
	if player == null or not is_instance_valid(player):
		return ""
	if not player.has_node("WeaponSystem"):
		return ""
	var system = player.get_node("WeaponSystem")
	if system == null or not system.has_method("get_shots_fired_by_weapon"):
		return ""
	var usage: Dictionary = system.get_shots_fired_by_weapon()
	var laser = int(usage.get(WeaponSlot.WeaponType.LASER, 0))
	var stun = int(usage.get(WeaponSlot.WeaponType.STUN, 0))
	var homing = int(usage.get(WeaponSlot.WeaponType.HOMING, 0))
	var spread = int(usage.get(WeaponSlot.WeaponType.SPREAD, 0))
	return "laser:%d stun:%d homing:%d spread:%d" % [laser, stun, homing, spread]

func _update_announcements(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if low_health_banner == null:
		return
	if low_health_banner_timer > 0.0:
		low_health_banner_timer = maxf(low_health_banner_timer - delta, 0.0)
		if low_health_banner_timer <= 0.0 and low_health_banner.has_method("hide_announcement"):
			low_health_banner.hide_announcement()
	var max_hp = float(player.get("max_health"))
	if max_hp <= 0.0:
		return
	var hp = float(player.get("health"))
	var ratio = hp / max_hp
	if ratio <= LOW_HEALTH_THRESHOLD:
		if not low_health_alert_active:
			low_health_alert_active = true
			if low_health_banner.has_method("show_announcement"):
				low_health_banner.show_announcement("LOW HEALTH")
			low_health_banner_timer = LOW_HEALTH_BANNER_DURATION
	elif ratio >= LOW_HEALTH_THRESHOLD + LOW_HEALTH_HYSTERESIS:
		if low_health_alert_active:
			low_health_alert_active = false
			if low_health_banner.has_method("hide_announcement"):
				low_health_banner.hide_announcement()
			low_health_banner_timer = 0.0

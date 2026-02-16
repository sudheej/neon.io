extends Node2D

const WeaponSlot = preload("res://src/domain/weapons/WeaponSlot.gd")
const BoostOrbScript = preload("res://src/presentation/world/BoostOrb.gd")
const SessionConfig = preload("res://src/infrastructure/network/SessionConfig.gd")

const ENEMY_START: int = 5
const ENEMY_SPAWN_RADIUS: float = 260.0
const ENEMY_SPAWN_RADIUS_FAR: float = 420.0
const ACTION_SPAWN_CHANCE: float = 0.55
const PLAYER_FAR_SPAWN_CHANCE: float = 0.45
const ACTION_SPAWN_MIN_RADIUS: float = 84.0
const ACTION_SPAWN_MAX_RADIUS: float = 240.0
const ACTION_ANCHOR_MIN_PLAYER_DIST: float = 150.0
const PLAYER_EXCLUSION_RADIUS_EARLY: float = 250.0
const PLAYER_EXCLUSION_RADIUS_LATE: float = 155.0
const PLAYER_EXCLUSION_BLEND_TIME: float = 60.0
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
const ORB_MIN_XP: float = 4.0
const ORB_MAX_XP: float = 34.0
const ORB_MIN_HEALTH: float = 3.0
const ORB_MAX_HEALTH: float = 20.0
const ORB_MIN_AMMO: int = 2
const ORB_MAX_AMMO: int = 18
const ORB_SURVIVAL_BONUS_RATE: float = 0.12
const ORB_SURVIVAL_BONUS_MAX: float = 14.0
const ORB_CREDIT_BONUS_RATE: float = 0.04
const ORB_CREDIT_BONUS_MAX: float = 10.0
const ORB_CELL_BONUS: float = 1.8
const ORB_BOUNDARY_PADDING: float = 16.0
const LEADER_CHECK_INTERVAL: float = 0.35
const STREAK_BANNER_DURATION: float = 1.45
const STREAK_CHAIN_GAP_SECONDS: float = 2.1
const STREAK_ANNOUNCE_MIN_TIME: float = 14.0
const STREAK_ANNOUNCE_MIN_ENEMIES: int = 3
const LEADERBOARD_CONTEST_MIN_TIME: float = 22.0
const LEADERBOARD_CONTEST_MIN_ENEMIES: int = 4
const LEADERBOARD_CONTEST_UNLOCK_MAX_RANK: int = 3
const AWESOME_SFX_PATH: String = "res://assets/audio/ui/awesome.wav"
const MESSAGE_SFX_PATH: String = "res://assets/audio/ui/message.wav"
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
var general_announcement_timer: float = 0.0
var pending_general_text: String = ""
var pending_general_sfx: AudioStream = null
var pending_general_volume_db: float = -4.0
var leaderboard_timer: float = 0.0
var player_is_leader: bool = false
var leaderboard_contest_unlocked: bool = false
var leaderboard_state_ready: bool = false
var streak_chain_by_id: Dictionary = {}
var last_kill_time_by_id: Dictionary = {}
var awesome_sfx: AudioStream = null
var message_sfx: AudioStream = null
var event_audio_loaded: bool = false
var minimap_toggle_was_pressed: bool = false
var minimap_visible_target: bool = true
var mute_toggle_was_pressed: bool = false
var audio_muted: bool = false
var game_mode: String = "offline_ai"
var dedicated_server: bool = false
var net_debug_hud: bool = false
var local_actor_id: String = "player"
var local_player: Node2D = null
var _last_local_player_ref: Node2D = null
var _bound_local_death_actor: Node = null
var _bound_input_actor_id: String = ""
var _network_adapter: Node = null
var _last_network_state_tick: int = -1
var _replicated_actor_ids: Dictionary = {}
var _net_target_pos_by_actor: Dictionary = {}
var _net_debug_label: Label = null

@onready var player = $Player
@onready var enemies_root = $Enemies
@onready var camera = $Camera2D
@onready var hud_label: Label = $HUD/InfoPanel/Body/Info
@onready var low_health_banner = $HUD/LowHealthBanner
@onready var mini_map: Control = $HUD/MiniMap
@onready var game_over_layer: CanvasLayer = $GameOver
@onready var game_over_time: Label = $GameOver/TimeSurvived
@onready var boost_orbs_root: Node2D = $BoostOrbs

func _ready() -> void:
	_apply_runtime_mode()
	_apply_local_actor_binding()
	_bind_network_adapter()
	add_to_group("world")
	if _is_ai_enabled_for_mode() and _should_spawn_ai_locally():
		_randomize_enemies()
	spawn_timer = _current_spawn_interval()
	if dedicated_server:
		_configure_dedicated_server_presentation()
	if OS.get_cmdline_args().has("--no-telemetry"):
		telemetry_enabled = false
	_connect_combatant_death_signals()
	_bind_input_sources()
	_bind_hud_targets()
	if mini_map != null:
		minimap_visible_target = mini_map.visible
	audio_muted = _is_master_bus_muted()
	_ensure_event_audio_loaded()
	_maybe_schedule_hud_screenshot()
	_setup_net_debug_hud()

func _input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event.is_action_pressed("toggle_minimap"):
		_toggle_minimap_visibility()
		minimap_toggle_was_pressed = true
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_mute"):
		_toggle_mute()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event.is_action_pressed("restart_game"):
		get_tree().reload_current_scene()
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.keycode == KEY_ESCAPE:
			SessionConfig.requeue_on_lobby_entry = false
			get_tree().change_scene_to_file("res://scenes/Lobby.tscn")

func _process(delta: float) -> void:
	_refresh_local_player()
	_smooth_network_actor_positions(delta)
	_poll_minimap_toggle()
	_poll_mute_toggle()
	if game_over:
		game_over_pulse = fmod(game_over_pulse + delta, TAU)
		_update_game_over_time()
		return
	if local_player == null or not is_instance_valid(local_player):
		return
	var focus: Vector2 = local_player.global_position
	if not _is_online_client() and local_player.has_method("get_active_cell_world_pos"):
		var focus_raw = local_player.get_active_cell_world_pos()
		if focus_raw is Vector2:
			focus = focus_raw
	if camera != null:
		var follow_speed := camera_follow_speed
		var dist: float = camera.global_position.distance_to(focus)
		if _is_online_client():
			follow_speed = 10.0
			if dist > 320.0:
				camera.global_position = focus
			elif dist > 120.0:
				follow_speed = 18.0
		var t = 1.0 - exp(-follow_speed * delta)
		camera.global_position = camera.global_position.lerp(focus, t)
	elapsed += delta
	var combatants: Array[Node] = _get_combatants()
	if telemetry_enabled:
		telemetry_timer -= delta
		if telemetry_timer <= 0.0:
			telemetry_timer = TELEMETRY_INTERVAL
			_log_telemetry(combatants)
	_process_combatants(delta, combatants)
	_process_boost_orbs(combatants)
	_update_hud(combatants)
	_update_leaderboard(delta, combatants)
	_update_announcements(delta)
	_maybe_spawn_enemy(delta, combatants.size() - 1)

func _apply_local_actor_binding() -> void:
	var actor_override: String = OS.get_environment("NEON_ACTOR_ID")
	if actor_override.is_empty():
		for arg in OS.get_cmdline_args():
			if arg.begins_with("--actor-id="):
				actor_override = arg.get_slice("=", 1)
				break
	if actor_override.is_empty():
		actor_override = SessionConfig.local_actor_id
	if actor_override.is_empty():
		actor_override = "player"
	local_actor_id = actor_override
	SessionConfig.local_actor_id = local_actor_id
	_sync_local_player_actor_id()
	_refresh_local_player()

func _sync_local_player_actor_id() -> void:
	if player == null or not is_instance_valid(player):
		return
	var current_id := String(player.get("actor_id"))
	if current_id == local_actor_id:
		return
	if local_actor_id.is_empty():
		return
	player.set("actor_id", local_actor_id)

func _refresh_local_player() -> void:
	local_player = _resolve_local_player()
	if local_player != _last_local_player_ref:
		_snap_camera_to_local_player()
		_last_local_player_ref = local_player
	_ensure_local_player_death_hook()
	if _bound_input_actor_id != local_actor_id:
		_bind_input_sources()
		_bind_hud_targets()
		_bound_input_actor_id = local_actor_id

func _snap_camera_to_local_player() -> void:
	if camera == null or local_player == null or not is_instance_valid(local_player):
		return
	var focus = local_player.global_position
	if local_player.has_method("get_active_cell_world_pos"):
		focus = local_player.get_active_cell_world_pos()
	camera.global_position = focus

func _resolve_local_player() -> Node2D:
	if player != null and is_instance_valid(player):
		var player_actor_id = String(player.get("actor_id"))
		if player_actor_id == local_actor_id or local_actor_id == "player":
			return player
	for node in get_tree().get_nodes_in_group("combatants"):
		var actor = node as Node2D
		if actor == null or not is_instance_valid(actor):
			continue
		if String(actor.get("actor_id")) == local_actor_id:
			return actor
	if player != null and is_instance_valid(player):
		return player
	return get_tree().get_first_node_in_group("player") as Node2D

func _connect_combatant_death_signals() -> void:
	for node in _get_combatants():
		if node == null or not is_instance_valid(node):
			continue
		if not node.has_signal("died"):
			continue
		if not node.is_connected("died", Callable(self, "_on_combatant_died")):
			node.connect("died", Callable(self, "_on_combatant_died"))
		_register_actor_with_world(node)

func _ensure_local_player_death_hook() -> void:
	if local_player == null or not is_instance_valid(local_player):
		return
	if _bound_local_death_actor == local_player:
		return
	if local_player.has_signal("died") and not local_player.is_connected("died", Callable(self, "_on_player_died")):
		local_player.connect("died", Callable(self, "_on_player_died"))
	_bound_local_death_actor = local_player

func _bind_input_sources() -> void:
	var human = get_node_or_null("GameWorld/HumanInputSource")
	if human != null:
		human.set("actor_id", local_actor_id)
		if local_player != null:
			human.set("actor_path", human.get_path_to(local_player))
	var agent = get_node_or_null("GameWorld/AgentInputSource")
	if agent != null:
		agent.set("actor_id", local_actor_id)

func _bind_hud_targets() -> void:
	var weapon_hud = get_node_or_null("HUD/WeaponHUD")
	if weapon_hud != null and weapon_hud.has_method("set_target_actor_id"):
		weapon_hud.call("set_target_actor_id", local_actor_id)

func _register_actor_with_world(actor: Node) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var game_world = get_tree().get_first_node_in_group("game_world")
	if game_world != null and game_world.has_method("register_combatant"):
		game_world.call("register_combatant", actor)
	if not actor.is_connected("tree_exited", Callable(self, "_on_combatant_tree_exited").bind(String(actor.get("actor_id")))):
		actor.connect("tree_exited", Callable(self, "_on_combatant_tree_exited").bind(String(actor.get("actor_id"))), CONNECT_ONE_SHOT)

func _on_combatant_tree_exited(actor_id: String) -> void:
	if actor_id.is_empty():
		return
	_net_target_pos_by_actor.erase(actor_id)
	_replicated_actor_ids.erase(actor_id)
	if _bound_local_death_actor != null:
		if not is_instance_valid(_bound_local_death_actor):
			_bound_local_death_actor = null
		elif String(_bound_local_death_actor.get("actor_id")) == actor_id:
			_bound_local_death_actor = null
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	var game_world = tree.get_first_node_in_group("game_world")
	if game_world != null and game_world.has_method("unregister_actor"):
		game_world.call("unregister_actor", actor_id)

func _poll_minimap_toggle() -> void:
	var pressed = Input.is_action_pressed("toggle_minimap") or Input.is_key_pressed(KEY_TAB)
	if pressed and not minimap_toggle_was_pressed:
		_toggle_minimap_visibility()
	minimap_toggle_was_pressed = pressed

func _poll_mute_toggle() -> void:
	var pressed = Input.is_action_pressed("toggle_mute") or Input.is_key_pressed(KEY_M)
	if pressed and not mute_toggle_was_pressed:
		_toggle_mute()
	mute_toggle_was_pressed = pressed

func _toggle_minimap_visibility() -> void:
	if mini_map == null:
		return
	minimap_visible_target = not minimap_visible_target
	if mini_map.has_method("set_minimap_enabled"):
		mini_map.set_minimap_enabled(minimap_visible_target)
	else:
		mini_map.visible = minimap_visible_target

func _get_combatants() -> Array[Node]:
	var list: Array[Node] = get_tree().get_nodes_in_group("combatants")
	list.sort_custom(func(a, b):
		var a_id := ""
		var b_id := ""
		if a != null and is_instance_valid(a):
			a_id = String(a.get("actor_id"))
		if b != null and is_instance_valid(b):
			b_id = String(b.get("actor_id"))
		if a_id != b_id:
			return a_id < b_id
		return a.get_instance_id() < b.get_instance_id()
	)
	return list

func _process_combatants(delta: float, combatants: Array[Node]) -> void:
	if _is_online_client():
		for entity in combatants:
			var node = entity as Node
			if node == null or not is_instance_valid(node):
				continue
			if bool(node.get("is_dying")):
				continue
			if not node.has_node("WeaponSystem"):
				continue
			var system = node.get_node("WeaponSystem")
			var targets = combatants.filter(func(item):
				return item != node and item != null and is_instance_valid(item) and not bool(item.get("is_dying"))
			)
			system.process_weapons(delta, targets)
		return
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
	var anchor_player := _resolve_local_player()
	if anchor_player == null:
		return
	if enemy.has_method("set_ai_enabled"):
		enemy.set_ai_enabled(true)
	var enemy_radius = 16.0
	if enemy.has_method("get_collision_radius"):
		enemy_radius = float(enemy.get_collision_radius())
	var player_radius = 16.0
	if anchor_player.has_method("get_collision_radius"):
		player_radius = float(anchor_player.get_collision_radius())
	var combatants = _get_combatants()
	var enemy_count = max(combatants.size() - 1, 0)
	var min_player_dist = _current_player_spawn_exclusion(enemy_count)
	var anchor = anchor_player.global_position
	var min_radius = maxf(120.0, player_radius + enemy_radius + 12.0)
	var max_radius = ENEMY_SPAWN_RADIUS
	if randf() < ACTION_SPAWN_CHANCE:
		var action_anchor = _pick_action_spawn_anchor(combatants)
		if action_anchor.distance_to(anchor_player.global_position) >= ACTION_ANCHOR_MIN_PLAYER_DIST:
			anchor = action_anchor
			min_radius = maxf(ACTION_SPAWN_MIN_RADIUS, enemy_radius + 10.0)
			max_radius = ACTION_SPAWN_MAX_RADIUS
	if anchor.distance_to(anchor_player.global_position) <= 1.0 and randf() < PLAYER_FAR_SPAWN_CHANCE:
		min_radius = maxf(min_radius, 185.0)
		max_radius = ENEMY_SPAWN_RADIUS_FAR
	if anchor.distance_to(anchor_player.global_position) <= 1.0:
		min_radius = maxf(min_radius, min_player_dist)
		max_radius = maxf(max_radius, min_radius + 36.0)
	var pos = anchor
	var found_valid = false
	var fallback_any_pos = anchor
	var fallback_any_dist = -INF
	var fallback_safe_pos = anchor
	var fallback_safe_dist = -INF
	for _i in range(12):
		var angle = randf_range(0.0, TAU)
		var radius = randf_range(min_radius, max_radius)
		var candidate = anchor + Vector2(cos(angle), sin(angle)) * radius
		var player_dist = candidate.distance_to(anchor_player.global_position)
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
		if ok and player_dist > fallback_safe_dist:
			fallback_safe_dist = player_dist
			fallback_safe_pos = candidate
		if player_dist > fallback_any_dist:
			fallback_any_dist = player_dist
			fallback_any_pos = candidate
		if player_dist < min_player_dist:
			continue
		if ok:
			pos = candidate
			found_valid = true
			break
	if not found_valid:
		if fallback_safe_dist > -INF:
			pos = fallback_safe_pos
		elif fallback_any_dist > -INF:
			pos = fallback_any_pos
	enemy.global_position = pos
	var ai = AIControllerScript.new()
	var game_world = get_tree().get_first_node_in_group("game_world")
	if game_world != null and game_world.has_method("get_command_queue"):
		var queue = game_world.get_command_queue()
		if ai.has_method("set_command_queue"):
			ai.set_command_queue(queue)
	if ai != null and enemy != null:
		var enemy_actor_id = enemy.get("actor_id")
		if enemy_actor_id != null and not String(enemy_actor_id).is_empty():
			ai.set("actor_id", String(enemy_actor_id))
	enemy.add_child(ai)
	enemies_root.add_child(enemy)
	_register_actor_with_world(enemy)
	if enemy.has_signal("died"):
		enemy.died.connect(_on_combatant_died)

func spawn_network_human_actor(actor_id: String, _owner_player_id: String = "") -> Node2D:
	if actor_id.is_empty():
		return null
	var existing := _find_actor_by_id(actor_id)
	if existing != null and is_instance_valid(existing):
		return existing
	var claimed := _claim_bootstrap_player_for_actor(actor_id)
	if claimed != null and is_instance_valid(claimed):
		return claimed
	var actor := PlayerScene.instantiate() as Node2D
	if actor == null:
		return null
	actor.name = "Net_%s" % actor_id
	if actor.has_method("set_ai_enabled"):
		actor.set_ai_enabled(false)
	if actor.has_method("set_input_enabled"):
		actor.set_input_enabled(false)
	actor.set("actor_id", actor_id)
	actor.global_position = _network_spawn_position()
	enemies_root.add_child(actor)
	_register_actor_with_world(actor)
	if actor.has_signal("died"):
		actor.died.connect(_on_combatant_died)
	return actor

func _claim_bootstrap_player_for_actor(actor_id: String) -> Node2D:
	if player == null or not is_instance_valid(player):
		return null
	if String(player.get("actor_id")) != "player":
		return null
	if player.has_method("set_ai_enabled"):
		player.set_ai_enabled(false)
	if player.has_method("set_input_enabled"):
		player.set_input_enabled(false)
	player.set("actor_id", actor_id)
	player.global_position = _network_spawn_position()
	_register_actor_with_world(player)
	return player

func _network_spawn_position() -> Vector2:
	var angle := randf_range(0.0, TAU)
	var radius := randf_range(40.0, 150.0)
	return Vector2(cos(angle), sin(angle)) * radius

func _current_player_spawn_exclusion(enemy_count: int) -> float:
	var t = clampf(elapsed / PLAYER_EXCLUSION_BLEND_TIME, 0.0, 1.0)
	var dist = lerpf(PLAYER_EXCLUSION_RADIUS_EARLY, PLAYER_EXCLUSION_RADIUS_LATE, t)
	if enemy_count < ENEMY_START:
		dist += 18.0
	if _is_surge_active():
		dist *= 0.9
	return dist

func _pick_action_spawn_anchor(combatants: Array[Node]) -> Vector2:
	var anchor_player := _resolve_local_player()
	if anchor_player == null:
		return Vector2.ZERO
	if boost_orbs_root != null and boost_orbs_root.get_child_count() > 0 and randf() < 0.45:
		var index = randi() % boost_orbs_root.get_child_count()
		var orb = boost_orbs_root.get_child(index) as Node2D
		if orb != null and is_instance_valid(orb):
			return orb.global_position
	var non_player: Array[Node2D] = []
	for entity in combatants:
		var node = entity as Node2D
		if node == null or not is_instance_valid(node):
			continue
		if node == anchor_player:
			continue
		if bool(node.get("is_dying")):
			continue
		non_player.append(node)
	if non_player.is_empty():
		return anchor_player.global_position
	return non_player[randi() % non_player.size()].global_position

func _maybe_spawn_enemy(delta: float, enemy_count: int) -> void:
	if not _should_spawn_ai_locally():
		return
	if not _is_ai_enabled_for_mode():
		return
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
	if local_player == null or not is_instance_valid(local_player):
		return
	if local_player.get("xp") == null:
		return
	var enemy_count = max(combatants.size() - 1, 0)
	hud_label.text = "CREDITS: %.1f\nENEMIES: %d\n[M] MUTE  [R] RESTART" % [local_player.xp, enemy_count]
	_update_net_debug_hud()

func _toggle_mute() -> void:
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus < 0:
		return
	audio_muted = not AudioServer.is_bus_mute(master_bus)
	AudioServer.set_bus_mute(master_bus, audio_muted)
	if audio_muted:
		_show_general_announcement("AUDIO MUTED", null, 0.0)
	else:
		_show_general_announcement("AUDIO ON", null, 0.0)

func _is_master_bus_muted() -> bool:
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus < 0:
		return false
	return AudioServer.is_bus_mute(master_bus)

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
	if _should_return_to_lobby_on_death():
		_return_to_lobby()
		return
	game_over = true
	game_over_pulse = 0.0
	if low_health_banner != null and low_health_banner.has_method("hide_announcement"):
		low_health_banner.hide_announcement()
	pending_general_text = ""
	if telemetry_enabled:
		_log_telemetry(_get_combatants())
		_log_telemetry_summary()
	if game_over_layer != null:
		game_over_layer.visible = true
	_update_game_over_time()

func _on_combatant_died(victim: Node) -> void:
	_handle_kill_achievements(victim)
	_spawn_boost_orb(victim)

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

func set_game_mode(mode_name: String) -> void:
	if mode_name == "offline_ai" or mode_name == "mixed" or mode_name == "human_only":
		game_mode = mode_name
		SessionConfig.selected_mode = mode_name

func _log_telemetry(combatants: Array[Node]) -> void:
	if local_player == null or not is_instance_valid(local_player):
		return
	var enemy_count = max(combatants.size() - 1, 0)
	var xp_val = float(local_player.get("xp"))
	var expansions = int(local_player.get("expansions_bought"))
	var cells = 1
	if local_player.has_node("PlayerShape"):
		var shape = local_player.get_node("PlayerShape")
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
	if local_player == null or not is_instance_valid(local_player):
		return
	var xp_val = float(local_player.get("xp"))
	var expansions = int(local_player.get("expansions_bought"))
	var usage_text = _weapon_usage_text()
	print(
		"[telemetry-summary] survived=%.1fs credits=%.1f expansions=%d surge=%d usage={%s}" %
		[elapsed, xp_val, expansions, 1 if _is_surge_active() else 0, usage_text]
	)

func _weapon_usage_text() -> String:
	if local_player == null or not is_instance_valid(local_player):
		return ""
	if not local_player.has_node("WeaponSystem"):
		return ""
	var system = local_player.get_node("WeaponSystem")
	if system == null or not system.has_method("get_shots_fired_by_weapon"):
		return ""
	var usage: Dictionary = system.get_shots_fired_by_weapon()
	var laser = int(usage.get(WeaponSlot.WeaponType.LASER, 0))
	var stun = int(usage.get(WeaponSlot.WeaponType.STUN, 0))
	var homing = int(usage.get(WeaponSlot.WeaponType.HOMING, 0))
	var spread = int(usage.get(WeaponSlot.WeaponType.SPREAD, 0))
	return "laser:%d stun:%d homing:%d spread:%d" % [laser, stun, homing, spread]

func _update_announcements(delta: float) -> void:
	if local_player == null or not is_instance_valid(local_player):
		return
	if low_health_banner == null:
		return
	if low_health_banner_timer > 0.0:
		low_health_banner_timer = maxf(low_health_banner_timer - delta, 0.0)
		if low_health_banner_timer <= 0.0 and low_health_banner.has_method("hide_announcement"):
			low_health_banner.hide_announcement()
	if general_announcement_timer > 0.0:
		general_announcement_timer = maxf(general_announcement_timer - delta, 0.0)
		if general_announcement_timer <= 0.0 and not low_health_alert_active and low_health_banner.has_method("hide_announcement"):
			low_health_banner.hide_announcement()
	var max_hp = float(local_player.get("max_health"))
	if max_hp <= 0.0:
		return
	var hp = float(local_player.get("health"))
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
		if not pending_general_text.is_empty():
			_show_general_announcement(pending_general_text, pending_general_sfx, pending_general_volume_db)
			pending_general_text = ""
			pending_general_sfx = null

func _update_leaderboard(delta: float, combatants: Array[Node]) -> void:
	if local_player == null or not is_instance_valid(local_player):
		return
	leaderboard_timer -= delta
	if leaderboard_timer > 0.0:
		return
	leaderboard_timer = LEADER_CHECK_INTERVAL
	var enemy_count = max(combatants.size() - 1, 0)
	if not leaderboard_contest_unlocked:
		if elapsed < LEADERBOARD_CONTEST_MIN_TIME:
			return
		if enemy_count < LEADERBOARD_CONTEST_MIN_ENEMIES:
			return
		var rank = _get_player_rank(combatants)
		if rank > LEADERBOARD_CONTEST_UNLOCK_MAX_RANK:
			return
		leaderboard_contest_unlocked = true
	if not leaderboard_state_ready:
		player_is_leader = (_pick_leader(combatants) == local_player)
		leaderboard_state_ready = true
		return
	var leader = _pick_leader(combatants)
	var player_now_leads = leader == local_player
	if player_now_leads and not player_is_leader:
		player_is_leader = true
		_show_general_announcement("LEADER", awesome_sfx, -4.0)
	elif not player_now_leads and player_is_leader:
		player_is_leader = false
		_show_general_announcement("LOST THE LEAD", message_sfx, -5.0)

func _pick_leader(combatants: Array[Node]) -> Node:
	var best: Node = null
	var best_score := -INF
	for entity in combatants:
		var node = entity as Node
		if node == null or not is_instance_valid(node):
			continue
		if bool(node.get("is_dying")):
			continue
		var score = _leaderboard_score(node)
		if score > best_score:
			best_score = score
			best = node
	return best

func _leaderboard_score(entity: Node) -> float:
	var xp = float(entity.get("xp"))
	var survival = 0.0
	if entity.has_method("get_survival_time"):
		survival = float(entity.get_survival_time())
	var cells = 1
	if entity.has_node("PlayerShape"):
		var shape = entity.get_node("PlayerShape")
		if shape != null:
			var shape_cells = shape.get("cells")
			if shape_cells is Dictionary:
				cells = max(1, (shape_cells as Dictionary).size())
	return xp + float(cells - 1) * 35.0 + survival * 0.08

func _get_player_rank(combatants: Array[Node]) -> int:
	if local_player == null or not is_instance_valid(local_player):
		return 999
	var player_score = _leaderboard_score(local_player)
	var better_count = 0
	for entity in combatants:
		var node = entity as Node
		if node == null or not is_instance_valid(node):
			continue
		if node == local_player or bool(node.get("is_dying")):
			continue
		if _leaderboard_score(node) > player_score:
			better_count += 1
	return better_count + 1

func _handle_kill_achievements(victim: Node) -> void:
	if local_player == null or not is_instance_valid(local_player):
		return
	if victim == null or not is_instance_valid(victim):
		return
	var killer = victim.get("last_damage_source")
	if killer == null or not is_instance_valid(killer):
		return
	if killer == victim:
		return
	if not killer.is_in_group("combatants"):
		return

	var killer_id = killer.get_instance_id()
	var kill_gap = elapsed - float(last_kill_time_by_id.get(killer_id, -INF))
	var chain = 1
	if kill_gap <= STREAK_CHAIN_GAP_SECONDS:
		chain = int(streak_chain_by_id.get(killer_id, 0)) + 1
	streak_chain_by_id[killer_id] = chain
	last_kill_time_by_id[killer_id] = elapsed

	if elapsed < STREAK_ANNOUNCE_MIN_TIME:
		return
	if _alive_enemy_count() < STREAK_ANNOUNCE_MIN_ENEMIES:
		return

	if chain <= 1:
		return
	var title_data = _get_streak_title_data(chain)
	if title_data.is_empty():
		return
	var bonus_xp = float(title_data["bonus_xp"])
	if killer.has_method("on_achievement_reward"):
		killer.on_achievement_reward(bonus_xp)
	elif killer.has_method("add_xp"):
		killer.add_xp(bonus_xp)
	if killer == local_player:
		_show_general_announcement("%s  +%d XP" % [String(title_data["title"]), int(title_data["bonus_xp"])], awesome_sfx, -4.0)

func _alive_enemy_count() -> int:
	var count = 0
	for entity in _get_combatants():
		var node = entity as Node
		if node == null or not is_instance_valid(node):
			continue
		if node == local_player:
			continue
		if bool(node.get("is_dying")):
			continue
		count += 1
	return count

func _get_streak_title_data(chain: int) -> Dictionary:
	var tiers = [
		{"chain": 2, "title": "DOUBLE KILL", "bonus_xp": 5},
		{"chain": 3, "title": "KILLING SPREE", "bonus_xp": 10},
		{"chain": 4, "title": "DOMINATING", "bonus_xp": 16},
		{"chain": 5, "title": "RAMPAGE", "bonus_xp": 24},
		{"chain": 6, "title": "UNSTOPPABLE", "bonus_xp": 34},
		{"chain": 7, "title": "IMMORTAL", "bonus_xp": 46},
		{"chain": 8, "title": "GODLIKE", "bonus_xp": 60},
		{"chain": 10, "title": "BEAST MODE", "bonus_xp": 80}
	]
	for tier in tiers:
		if chain == int(tier["chain"]):
			return tier
	if chain > 10 and chain % 2 == 0:
		var extra_steps = int((chain - 10) / 2)
		return {
			"chain": chain,
			"title": "BEYOND GODLIKE x%d" % (extra_steps + 1),
			"bonus_xp": min(80 + extra_steps * 12, 160)
		}
	return {}

func _show_general_announcement(message: String, sfx: AudioStream, volume_db: float) -> void:
	if low_health_banner == null or not low_health_banner.has_method("show_announcement"):
		return
	if low_health_alert_active:
		pending_general_text = message
		pending_general_sfx = sfx
		pending_general_volume_db = volume_db
		return
	low_health_banner.show_announcement(message)
	general_announcement_timer = STREAK_BANNER_DURATION
	_play_event_sfx(sfx, volume_db)

func _play_event_sfx(stream: AudioStream, volume_db: float) -> void:
	if stream == null:
		return
	var audio := AudioStreamPlayer.new()
	audio.stream = stream
	audio.volume_db = volume_db
	audio.pitch_scale = 1.0
	add_child(audio)
	audio.play()
	audio.finished.connect(audio.queue_free)

func _ensure_event_audio_loaded() -> void:
	if event_audio_loaded:
		return
	event_audio_loaded = true
	awesome_sfx = _load_imported_audio(AWESOME_SFX_PATH)
	if awesome_sfx == null:
		awesome_sfx = ResourceLoader.load(AWESOME_SFX_PATH) as AudioStream
	message_sfx = _load_imported_audio(MESSAGE_SFX_PATH)
	if message_sfx == null:
		message_sfx = ResourceLoader.load(MESSAGE_SFX_PATH) as AudioStream

func _load_imported_audio(source_path: String) -> AudioStream:
	var import_path := source_path + ".import"
	var cfg := ConfigFile.new()
	if cfg.load(import_path) != OK:
		return null
	var remap_path := cfg.get_value("remap", "path", "") as String
	if remap_path.is_empty():
		return null
	return ResourceLoader.load(remap_path) as AudioStream

func _process_boost_orbs(combatants: Array[Node]) -> void:
	if boost_orbs_root == null:
		return
	for child in boost_orbs_root.get_children():
		var orb = child as Node2D
		if orb == null or not is_instance_valid(orb):
			continue
		if not orb.has_method("try_consume") or not orb.has_method("is_entity_in_pickup_range"):
			continue
		for entity in combatants:
			var node = entity as Node2D
			if node == null or not is_instance_valid(node):
				continue
			if bool(node.get("is_dying")):
				continue
			if not bool(orb.is_entity_in_pickup_range(node)):
				continue
			orb.try_consume(node, true)
			if not is_instance_valid(orb):
				break

func _spawn_boost_orb(victim: Node) -> void:
	if boost_orbs_root == null:
		return
	var victim_node = victim as Node2D
	if victim_node == null or not is_instance_valid(victim_node):
		return
	var orb = BoostOrbScript.new()
	var boost_type = randi() % 3
	var amount = _compute_orb_value(victim, boost_type)
	var weapon_type = WeaponSlot.WeaponType.LASER
	if boost_type == BoostOrbScript.BoostType.AMMO:
		var weapon_pool = [
			WeaponSlot.WeaponType.LASER,
			WeaponSlot.WeaponType.STUN,
			WeaponSlot.WeaponType.HOMING,
			WeaponSlot.WeaponType.SPREAD
		]
		weapon_type = weapon_pool[randi() % weapon_pool.size()]
	orb.configure(boost_type, amount, weapon_type)
	orb.global_position = _safe_orb_spawn_position(victim_node.global_position, orb)
	boost_orbs_root.add_child(orb)

func _safe_orb_spawn_position(desired_pos: Vector2, orb: Node) -> Vector2:
	var boundary = get_node_or_null("ArenaBoundary")
	if boundary == null or not boundary.has_method("clamp_point"):
		return desired_pos
	var pickup_radius = 0.0
	if orb != null and orb.has_method("get_pickup_radius"):
		pickup_radius = maxf(float(orb.get_pickup_radius()), 0.0)
	var clamp_radius = pickup_radius + ORB_BOUNDARY_PADDING
	return boundary.clamp_point(desired_pos, clamp_radius)

func _compute_orb_value(victim: Node, boost_type: int) -> float:
	var survival = 0.0
	if victim.has_method("get_survival_time"):
		survival = float(victim.get_survival_time())
	var credits = 0.0
	var victim_xp = victim.get("xp")
	if victim_xp != null:
		credits = float(victim_xp)
	var cells = 1
	if victim.has_node("PlayerShape"):
		var shape = victim.get_node("PlayerShape")
		if shape != null:
			var shape_cells = shape.get("cells")
			if shape_cells is Dictionary:
				cells = max(1, (shape_cells as Dictionary).size())
	var base = 0.0
	match boost_type:
		BoostOrbScript.BoostType.XP:
			base = ORB_MIN_XP
		BoostOrbScript.BoostType.AMMO:
			base = float(ORB_MIN_AMMO)
		BoostOrbScript.BoostType.HEALTH:
			base = ORB_MIN_HEALTH
	var survival_bonus = minf(survival * ORB_SURVIVAL_BONUS_RATE, ORB_SURVIVAL_BONUS_MAX)
	var credit_bonus = minf(credits * ORB_CREDIT_BONUS_RATE, ORB_CREDIT_BONUS_MAX)
	var cell_bonus = float(max(0, cells - 1)) * ORB_CELL_BONUS
	var total = base + survival_bonus + credit_bonus + cell_bonus
	match boost_type:
		BoostOrbScript.BoostType.XP:
			return clampf(total, ORB_MIN_XP, ORB_MAX_XP)
		BoostOrbScript.BoostType.AMMO:
			return float(clampi(int(round(total)), ORB_MIN_AMMO, ORB_MAX_AMMO))
		BoostOrbScript.BoostType.HEALTH:
			return clampf(total, ORB_MIN_HEALTH, ORB_MAX_HEALTH)
		_:
			return ORB_MIN_XP

func _apply_runtime_mode() -> void:
	var mode_override: String = OS.get_environment("NEON_MODE")
	var net_hud_env := OS.get_environment("NEON_NET_DEBUG_HUD").to_lower()
	net_debug_hud = net_hud_env == "1" or net_hud_env == "true"
	for arg in OS.get_cmdline_args():
		if arg == "--server":
			dedicated_server = true
		elif arg.begins_with("--mode="):
			mode_override = arg.get_slice("=", 1)
		elif arg == "--net-debug-hud":
			net_debug_hud = true
	var env_server: String = OS.get_environment("NEON_SERVER")
	if env_server == "1" or env_server.to_lower() == "true":
		dedicated_server = true
	if mode_override.is_empty():
		mode_override = SessionConfig.selected_mode
	if mode_override == "offline_ai" or mode_override == "mixed" or mode_override == "human_only":
		game_mode = mode_override
	else:
		game_mode = "offline_ai"
	SessionConfig.selected_mode = game_mode

func _is_ai_enabled_for_mode() -> bool:
	return game_mode != "human_only"

func _is_online_mode() -> bool:
	return game_mode == "mixed" or game_mode == "human_only"

func _should_return_to_lobby_on_death() -> bool:
	if dedicated_server:
		return false
	if not _is_online_mode():
		return false
	return SessionConfig.auto_requeue_on_death

func _return_to_lobby() -> void:
	SessionConfig.requeue_on_lobby_entry = true
	if game_over_layer != null:
		game_over_layer.visible = false
	call_deferred("_deferred_return_to_lobby")

func _deferred_return_to_lobby() -> void:
	var timer = get_tree().create_timer(0.35)
	await timer.timeout
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")

func _configure_dedicated_server_presentation() -> void:
	input_enabled = false
	if has_node("HUD"):
		get_node("HUD").visible = false
	if game_over_layer != null:
		game_over_layer.visible = false

func _setup_net_debug_hud() -> void:
	if not net_debug_hud:
		return
	var hud_layer = get_node_or_null("HUD") as CanvasLayer
	if hud_layer == null:
		return
	_net_debug_label = Label.new()
	_net_debug_label.name = "NetDebugHUD"
	_net_debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_net_debug_label.anchor_left = 0.0
	_net_debug_label.anchor_top = 0.0
	_net_debug_label.anchor_right = 0.0
	_net_debug_label.anchor_bottom = 0.0
	_net_debug_label.offset_left = 14.0
	_net_debug_label.offset_top = 248.0
	_net_debug_label.offset_right = 520.0
	_net_debug_label.offset_bottom = 300.0
	_net_debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_net_debug_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_net_debug_label.add_theme_color_override("font_color", Color(0.65, 0.96, 1.0, 0.92))
	_net_debug_label.add_theme_constant_override("outline_size", 1)
	_net_debug_label.add_theme_color_override("font_outline_color", Color(0.02, 0.1, 0.16, 0.92))
	hud_layer.add_child(_net_debug_label)
	_update_net_debug_hud()

func _update_net_debug_hud() -> void:
	if _net_debug_label == null or not is_instance_valid(_net_debug_label):
		return
	var connected := false
	var role := "offline"
	if _network_adapter != null and is_instance_valid(_network_adapter):
		role = String(_network_adapter.get("role"))
		if _network_adapter.has_method("net_is_connected"):
			connected = bool(_network_adapter.call("net_is_connected"))
	_net_debug_label.text = "NET match=%s actor=%s remotes=%d conn=%d role=%s" % [
		SessionConfig.match_id,
		local_actor_id,
		int(_replicated_actor_ids.size()),
		1 if connected else 0,
		role
	]

func _bind_network_adapter() -> void:
	_network_adapter = get_node_or_null("GameWorld/NetworkAdapter")
	if _network_adapter == null:
		_network_adapter = get_tree().get_first_node_in_group("network_adapter")
	if _network_adapter == null:
		return
	if _network_adapter.has_signal("state_received") and not _network_adapter.is_connected("state_received", Callable(self, "_on_network_state_received")):
		_network_adapter.connect("state_received", Callable(self, "_on_network_state_received"))

func _on_network_state_received(state: Dictionary) -> void:
	if not _is_online_client():
		return
	var tick := int(state.get("tick", -1))
	if tick >= 0 and tick <= _last_network_state_tick:
		return
	var data_raw = state.get("data", {})
	if not (data_raw is Dictionary):
		return
	var data: Dictionary = data_raw
	if data.has("time"):
		elapsed = maxf(elapsed, float(data.get("time", elapsed)))
	if data.has("actors"):
		_apply_full_actor_state(data.get("actors", []))
	else:
		_apply_delta_actor_state(data)
	if tick >= 0:
		_last_network_state_tick = tick

func _apply_full_actor_state(raw_actors) -> void:
	var present_remote_ids: Dictionary = {}
	if not (raw_actors is Array):
		return
	for raw_actor in raw_actors:
		if not (raw_actor is Dictionary):
			continue
		var actor_data: Dictionary = raw_actor
		var actor_id := String(actor_data.get("id", ""))
		if actor_id.is_empty():
			continue
		var actor: Node2D = null
		if actor_id == local_actor_id:
			actor = _ensure_local_network_actor(actor_data)
		else:
			present_remote_ids[actor_id] = true
			actor = _ensure_replicated_actor(actor_id, actor_data)
		if actor != null:
			_apply_actor_state(actor, actor_data)
	for actor_id in _replicated_actor_ids.keys():
		var id := String(actor_id)
		if not present_remote_ids.has(id):
			_remove_replicated_actor(id)

func _apply_delta_actor_state(data: Dictionary) -> void:
	var upserts_raw = data.get("actors_upsert", [])
	if upserts_raw is Array:
		for raw_actor in upserts_raw:
			if not (raw_actor is Dictionary):
				continue
			var actor_data: Dictionary = raw_actor
			var actor_id := String(actor_data.get("id", ""))
			if actor_id.is_empty():
				continue
			var actor: Node2D = null
			if actor_id == local_actor_id:
				actor = _ensure_local_network_actor(actor_data)
			else:
				actor = _ensure_replicated_actor(actor_id, actor_data)
			if actor != null:
				_apply_actor_state(actor, actor_data)
	var removes_raw = data.get("actors_remove", [])
	if removes_raw is Array:
		for raw_id in removes_raw:
			var actor_id := String(raw_id)
			if actor_id.is_empty():
				continue
			_remove_replicated_actor(actor_id)

func _ensure_local_network_actor(actor_data: Dictionary) -> Node2D:
	var existing := _find_actor_by_id(local_actor_id)
	if existing != null and is_instance_valid(existing):
		if existing.has_method("set_network_driven"):
			existing.set_network_driven(true)
		return existing
	if player != null and is_instance_valid(player) and String(player.get("actor_id")) == "player":
		player.set("actor_id", local_actor_id)
		if player.has_method("set_ai_enabled"):
			player.set_ai_enabled(false)
		if player.has_method("set_input_enabled"):
			player.set_input_enabled(false)
		if player.has_method("set_network_driven"):
			player.set_network_driven(true)
		_register_actor_with_world(player)
		return player
	var actor := PlayerScene.instantiate() as Node2D
	if actor == null:
		return null
	actor.name = "Local_%s" % local_actor_id
	if actor.has_method("set_ai_enabled"):
		actor.set_ai_enabled(false)
	if actor.has_method("set_input_enabled"):
		actor.set_input_enabled(false)
	if actor.has_method("set_network_driven"):
		actor.set_network_driven(true)
	actor.set("actor_id", local_actor_id)
	var pos_raw = actor_data.get("position", null)
	if pos_raw is Vector2:
		actor.global_position = pos_raw
	elif pos_raw is Dictionary:
		var pos_dict: Dictionary = pos_raw
		actor.global_position = Vector2(float(pos_dict.get("x", 0.0)), float(pos_dict.get("y", 0.0)))
	else:
		actor.global_position = _network_spawn_position()
	enemies_root.add_child(actor)
	_register_actor_with_world(actor)
	if actor.has_signal("died"):
		actor.died.connect(_on_combatant_died)
	return actor

func _ensure_replicated_actor(actor_id: String, actor_data: Dictionary) -> Node2D:
	var existing = _find_actor_by_id(actor_id)
	if existing != null and is_instance_valid(existing):
		if existing.has_method("set_network_driven"):
			existing.set_network_driven(true)
		_replicated_actor_ids[actor_id] = true
		return existing
	var actor := PlayerScene.instantiate() as Node2D
	if actor == null:
		return null
	actor.name = "Remote_%s" % actor_id
	if actor.has_method("set_ai_enabled"):
		actor.set_ai_enabled(bool(actor_data.get("is_ai", true)))
	if actor.is_in_group("player"):
		actor.remove_from_group("player")
	if actor.has_method("set_input_enabled"):
		actor.set_input_enabled(false)
	if actor.has_method("set_network_driven"):
		actor.set_network_driven(true)
	actor.set("actor_id", actor_id)
	enemies_root.add_child(actor)
	_register_actor_with_world(actor)
	_replicated_actor_ids[actor_id] = true
	return actor

func _apply_actor_state(actor: Node2D, actor_data: Dictionary) -> void:
	if actor == null or not is_instance_valid(actor):
		return
	var actor_id := String(actor.get("actor_id"))
	if actor_data.has("position"):
		var pos_raw = actor_data.get("position")
		var target_pos := actor.global_position
		if pos_raw is Vector2:
			target_pos = pos_raw
		elif pos_raw is Dictionary:
			var pos_dict: Dictionary = pos_raw
			target_pos = Vector2(float(pos_dict.get("x", actor.global_position.x)), float(pos_dict.get("y", actor.global_position.y)))
		if not actor_id.is_empty():
			if not _net_target_pos_by_actor.has(actor_id):
				actor.global_position = target_pos
			_net_target_pos_by_actor[actor_id] = target_pos
	if actor_data.has("health"):
		var prev_health := float(actor.get("health"))
		var next_health := float(actor_data.get("health", prev_health))
		actor.set("health", next_health)
		if next_health < prev_health:
			actor.set("damage_flash", maxf(float(actor.get("damage_flash")), 0.08))
	if actor_data.has("max_health"):
		actor.set("max_health", float(actor_data.get("max_health", actor.get("max_health"))))
	if actor_data.has("is_ai"):
		actor.set("is_ai", bool(actor_data.get("is_ai", actor.get("is_ai"))))
	if actor_data.has("xp"):
		actor.set("xp", float(actor_data.get("xp", actor.get("xp"))))
	if actor_data.has("cells"):
		_apply_actor_cells(actor, actor_data.get("cells", []))
	var weapon_system = actor.get_node_or_null("WeaponSystem")
	if weapon_system != null and actor_data.has("selected_weapon"):
		var selected_weapon := int(actor_data.get("selected_weapon", weapon_system.get("selected_weapon_type")))
		if int(weapon_system.get("selected_weapon_type")) != selected_weapon:
			weapon_system.set("selected_weapon_type", selected_weapon)
			if weapon_system.has_method("_apply_weapon_to_all_slots"):
				weapon_system.call("_apply_weapon_to_all_slots", selected_weapon)
	if weapon_system != null and actor_data.has("armed_cell"):
		var armed = actor_data.get("armed_cell")
		var armed_cell := Vector2i.ZERO
		if armed is Vector2i:
			armed_cell = armed
		elif armed is Dictionary:
			var armed_dict: Dictionary = armed
			armed_cell = Vector2i(int(armed_dict.get("x", 0)), int(armed_dict.get("y", 0)))
		if weapon_system.has_method("set_armed_cell"):
			weapon_system.call("set_armed_cell", armed_cell)

func _apply_actor_cells(actor: Node2D, raw_cells) -> void:
	var shape = actor.get_node_or_null("PlayerShape")
	if shape == null or not (raw_cells is Array):
		return
	var next_cells: Array[Vector2i] = []
	for entry in raw_cells:
		if entry is Vector2i:
			next_cells.append(entry)
		elif entry is Dictionary:
			var cell_dict: Dictionary = entry
			next_cells.append(Vector2i(int(cell_dict.get("x", 0)), int(cell_dict.get("y", 0))))
	if next_cells.is_empty():
		next_cells.append(Vector2i.ZERO)
	var current_raw = shape.get("cells")
	if current_raw is Dictionary:
		var current_keys: Array[Vector2i] = []
		for key in (current_raw as Dictionary).keys():
			if key is Vector2i:
				current_keys.append(key)
		if _same_cell_set(current_keys, next_cells):
			return
	shape.set("cells", {})
	for grid_pos in next_cells:
		shape.call("add_cell", grid_pos)
	var weapon_system = actor.get_node_or_null("WeaponSystem")
	if weapon_system != null and weapon_system.has_method("on_shape_changed"):
		weapon_system.call("on_shape_changed")

func _same_cell_set(a: Array[Vector2i], b: Array[Vector2i]) -> bool:
	if a.size() != b.size():
		return false
	var lookup: Dictionary = {}
	for cell in a:
		lookup["%d:%d" % [cell.x, cell.y]] = true
	for cell in b:
		if not lookup.has("%d:%d" % [cell.x, cell.y]):
			return false
	return true

func _remove_replicated_actor(actor_id: String) -> void:
	if actor_id.is_empty():
		return
	_replicated_actor_ids.erase(actor_id)
	_net_target_pos_by_actor.erase(actor_id)
	var actor = _find_actor_by_id(actor_id)
	if actor != null and is_instance_valid(actor):
		actor.queue_free()

func _find_actor_by_id(actor_id: String) -> Node2D:
	for node in get_tree().get_nodes_in_group("combatants"):
		var actor := node as Node2D
		if actor == null or not is_instance_valid(actor):
			continue
		if String(actor.get("actor_id")) == actor_id:
			return actor
	return null

func _is_replicated_actor(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var actor_id := String(node.get("actor_id"))
	if actor_id.is_empty():
		return false
	return _replicated_actor_ids.has(actor_id)

func _smooth_network_actor_positions(delta: float) -> void:
	if not _is_online_client():
		return
	var alpha_ai := 1.0 - exp(-16.0 * delta)
	var alpha_human := 1.0 - exp(-22.0 * delta)
	var alpha_local := 1.0 - exp(-26.0 * delta)
	for node in get_tree().get_nodes_in_group("combatants"):
		var actor := node as Node2D
		if actor == null or not is_instance_valid(actor):
			continue
		var actor_id := String(actor.get("actor_id"))
		if actor_id.is_empty():
			continue
		if not _net_target_pos_by_actor.has(actor_id):
			continue
		var target: Vector2 = _net_target_pos_by_actor[actor_id]
		var delta_pos := target - actor.global_position
		var is_local := actor_id == local_actor_id
		if is_local:
			var local_dist := delta_pos.length()
			if local_dist <= 1.25:
				continue
			if local_dist > 85.0:
				actor.global_position = target
			else:
				actor.global_position = actor.global_position.lerp(target, alpha_local)
			continue
		var is_ai_actor := bool(actor.get("is_ai"))
		var snap_dist := 170.0
		var alpha := alpha_human
		if is_ai_actor:
			alpha = alpha_ai
			snap_dist = 140.0
		if delta_pos.length() > snap_dist:
			actor.global_position = target
			continue
		actor.global_position = actor.global_position.lerp(target, alpha)

func _should_spawn_ai_locally() -> bool:
	if dedicated_server:
		return true
	return not _is_online_client()

func _is_online_client() -> bool:
	if _network_adapter == null or not is_instance_valid(_network_adapter):
		return false
	if not _network_adapter.has_method("is_online"):
		return false
	if not bool(_network_adapter.call("is_online")):
		return false
	return String(_network_adapter.get("role")) == "client"

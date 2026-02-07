extends Node2D

const PlayerShapeScript = preload("res://src/presentation/player/PlayerShape.gd")
const WeaponSlot = preload("res://src/domain/weapons/WeaponSlot.gd")

signal died(victim: Node)

const MOVE_SPEED: float = 180.0
const ACCEL: float = 12.0
const EXPAND_COST: float = 60.0
const KILL_REWARD_BASE: float = 6.5
const KILL_REWARD_PER_EXTRA_CELL: float = 2.0
const KILL_REWARD_MAX: float = 20.0
const KILL_COMBO_WINDOW: float = 4.0
const KILL_COMBO_BONUS_STEP: float = 1.0
const KILL_COMBO_BONUS_MAX: float = 4.0
const LOW_CREDIT_THRESHOLD: float = 10.0
const LOW_CREDIT_STIPEND: float = 2.0
const LOW_CREDIT_INTERVAL: float = 5.0
const LOW_HEALTH_THRESHOLD: float = 0.4
const CRITICAL_SFX_COOLDOWN: float = 4.0
const CRITICAL_SFX_PATH: String = "res://assets/audio/ui/critical.wav"
const HUMAN_DAMAGE_MULTIPLIER: float = 0.6
const ARMOR_REDUCTION_PER_CELL: float = 0.04
const ARMOR_REDUCTION_MAX: float = 0.4
const SPAWN_DURATION: float = 0.35
const DEATH_DURATION: float = 0.45
const COLLISION_PUSH_SCALE: float = 0.5
const COLLISION_PLAYER_PUSH_SCALE: float = 0.22
const COLLISION_AI_PUSH_SCALE: float = 0.55
const COLLISION_PULSE_LIFE: float = 0.18
var velocity: Vector2 = Vector2.ZERO
var xp: float = 250.0
var expansions_bought: int = 0
var expand_mode: bool = false
var expand_hold: bool = false
var show_range: bool = false
var range_phase: float = 0.0
var active_pulse_phase: float = 0.0
var is_ai: bool = false
var input_enabled: bool = true
var actor_id: String = ""
var ai_move: Vector2 = Vector2.ZERO
var max_health: float = 40.0
var health: float = 40.0
var stun_time: float = 0.0
var damage_flash: float = 0.0
var damage_blink_timer: float = 0.0
var damage_blink_phase: float = 0.0
var damage_blink_color: Color = Color(1.0, 0.4, 0.4, 1.0)
var regen_delay: float = 3.0
var regen_rate: float = 4.0
var regen_timer: float = 0.0
var combo_chain: int = 0
var combo_timer: float = 0.0
var low_credit_timer: float = LOW_CREDIT_INTERVAL
var critical_sfx_timer: float = 0.0
var critical_sfx_armed: bool = true
var event_audio_loaded: bool = false
var critical_sfx: AudioStream = null

var move_command: Vector2 = Vector2.ZERO
var expand_command: bool = false
var place_command: Vector2i = Vector2i(99999, 99999)

var pulse_timer: float = 0.0
var pulses: Array[Dictionary] = []
var repel_pulses: Array[Dictionary] = []
var spawn_timer: float = 0.0
var death_timer: float = 0.0
var is_dying: bool = false
var debug_collision: bool = false
var debug_collisions: Array[Dictionary] = []
var debug_collision_print_timer: float = 0.0

@onready var shape = $PlayerShape
@onready var weapon_system = $WeaponSystem

func _ready() -> void:
	add_to_group("combatants")
	if not is_ai:
		add_to_group("player")
	if actor_id.is_empty():
		actor_id = "player"
	spawn_timer = SPAWN_DURATION
	modulate.a = 0.0
	debug_collision = OS.get_cmdline_args().has("--collision-debug")

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
	if regen_timer > 0.0:
		regen_timer = maxf(regen_timer - delta, 0.0)
	elif health < max_health:
		health = minf(max_health, health + regen_rate * delta)
	if combo_timer > 0.0:
		combo_timer = maxf(combo_timer - delta, 0.0)
	elif combo_chain > 0:
		combo_chain = 0
	low_credit_timer = maxf(low_credit_timer - delta, 0.0)
	critical_sfx_timer = maxf(critical_sfx_timer - delta, 0.0)
	if not is_ai:
		if xp < LOW_CREDIT_THRESHOLD and low_credit_timer <= 0.0:
			add_xp(LOW_CREDIT_STIPEND)
			low_credit_timer = LOW_CREDIT_INTERVAL
		var health_ratio := health / maxf(max_health, 0.001)
		if health_ratio <= LOW_HEALTH_THRESHOLD:
			if critical_sfx_armed and critical_sfx_timer <= 0.0:
				_play_critical_sfx()
				critical_sfx_timer = CRITICAL_SFX_COOLDOWN
				critical_sfx_armed = false
		elif health_ratio >= LOW_HEALTH_THRESHOLD + 0.08:
			critical_sfx_armed = true
	pulse_timer -= delta
	if pulse_timer <= 0.0:
		_spawn_pulse()
		pulse_timer = randf_range(0.15, 0.35)
	range_phase = fmod(range_phase + delta * 0.6, TAU)
	active_pulse_phase = fmod(active_pulse_phase + delta * 3.8, TAU)
	if stun_time > 0.0:
		stun_time = maxf(stun_time - delta, 0.0)
	if damage_flash > 0.0:
		damage_flash = maxf(damage_flash - delta, 0.0)
	if damage_blink_timer > 0.0:
		damage_blink_timer = maxf(damage_blink_timer - delta, 0.0)
		damage_blink_phase = fmod(damage_blink_phase + delta * 22.0, TAU)
	if debug_collision and debug_collision_print_timer > 0.0:
		debug_collision_print_timer = maxf(debug_collision_print_timer - delta, 0.0)

	for i in range(pulses.size() - 1, -1, -1):
		pulses[i]["time"] -= delta
		if pulses[i]["time"] <= 0.0:
			pulses.remove_at(i)
	for i in range(repel_pulses.size() - 1, -1, -1):
		repel_pulses[i]["time"] -= delta
		if repel_pulses[i]["time"] <= 0.0:
			repel_pulses.remove_at(i)

	queue_redraw()

func _physics_process(delta: float) -> void:
	if is_dying:
		return
	if is_ai:
		move_command = ai_move
	elif input_enabled:
		_update_commands()
	var move_dir = move_command
	if not is_ai:
		move_dir = move_command.normalized()
	elif move_dir.length() > 1.0:
		move_dir = move_dir.normalized()
	var target_vel = move_dir * MOVE_SPEED
	if stun_time > 0.0:
		target_vel *= 0.35
	velocity = velocity.lerp(target_vel, 1.0 - pow(0.001, delta * ACCEL))
	global_position += velocity * delta
	if spawn_timer <= 0.0:
		_apply_soft_collisions(delta)

func _unhandled_input(event: InputEvent) -> void:
	if is_ai:
		return
	if not input_enabled:
		return
	if is_dying:
		return
	if event.is_action_pressed("expand_mode"):
		expand_mode = !expand_mode
		expand_command = expand_mode
		queue_redraw()
	if event.is_action_pressed("select_next_slot"):
		weapon_system.select_next_slot()
		weapon_system.sync_armed_cell_to_selection()
		queue_redraw()
	if event.is_action_pressed("select_prev_slot"):
		weapon_system.select_prev_slot()
		weapon_system.sync_armed_cell_to_selection()
		queue_redraw()
	if event.is_action_pressed("toggle_range"):
		show_range = !show_range
		queue_redraw()
	if event.is_action_pressed("weapon_laser"):
		weapon_system.select_weapon_and_buy(WeaponSlot.WeaponType.LASER)
		queue_redraw()
	if event.is_action_pressed("weapon_stun"):
		weapon_system.select_weapon_and_buy(WeaponSlot.WeaponType.STUN)
		queue_redraw()
	if event.is_action_pressed("weapon_homing"):
		weapon_system.select_weapon_and_buy(WeaponSlot.WeaponType.HOMING)
		queue_redraw()
	if event.is_action_pressed("weapon_spread"):
		weapon_system.select_weapon_and_buy(WeaponSlot.WeaponType.SPREAD)
		queue_redraw()

	if expand_mode and event.is_action_pressed("expand_place"):
		var grid_pos = local_to_grid(to_local(get_global_mouse_position()))
		place_command = grid_pos
		_try_place_cell(grid_pos)

func _update_commands() -> void:
	var x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	move_command = Vector2(x, y)

func add_xp(amount: float) -> void:
	xp += amount

func award_kill_reward(base_reward: float) -> void:
	var chain_next = combo_chain + 1 if combo_timer > 0.0 else 1
	var combo_bonus = minf(float(max(0, chain_next - 1)) * KILL_COMBO_BONUS_STEP, KILL_COMBO_BONUS_MAX)
	add_xp(base_reward + combo_bonus)
	combo_chain = chain_next
	combo_timer = KILL_COMBO_WINDOW
	if combo_bonus > 0.0:
		print("[reward] combo x%d bonus=%.1f" % [combo_chain, combo_bonus])

func spend_xp(amount: float) -> bool:
	if xp < amount:
		return false
	xp -= amount
	return true

func set_ai_enabled(enabled: bool) -> void:
	is_ai = enabled
	if is_ai:
		if is_in_group("player"):
			remove_from_group("player")
		if actor_id.is_empty() or actor_id == "player":
			actor_id = "ai_%s" % str(get_instance_id())
	else:
		if not is_in_group("player"):
			add_to_group("player")
		if actor_id.is_empty() or actor_id.begins_with("ai_"):
			actor_id = "player"

func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled

func set_move_command(dir: Vector2) -> void:
	if is_ai:
		ai_move = dir
	else:
		move_command = dir

func toggle_expand_mode() -> void:
	expand_mode = !expand_mode
	expand_command = expand_mode
	queue_redraw()

func set_expand_mode(enabled: bool) -> void:
	expand_mode = enabled
	expand_command = expand_mode
	queue_redraw()

func set_expand_hold(enabled: bool) -> void:
	expand_hold = enabled
	queue_redraw()

func try_expand_direction(dir: Vector2i) -> void:
	if dir == Vector2i.ZERO:
		return
	if shape == null:
		return
	var base = weapon_system.get_armed_cell()
	if not shape.cells.has(base):
		return
	var target = base + dir
	if shape.cells.has(target):
		_set_active_cell(target)
		return
	if xp < EXPAND_COST:
		return
	if shape.add_cell(target):
		xp -= EXPAND_COST
		expansions_bought += 1
		weapon_system.on_shape_changed()
		_set_active_cell(target)
		queue_redraw()

func try_place_cell(grid_pos: Vector2i) -> void:
	place_command = grid_pos
	_try_place_cell(grid_pos)

func select_next_slot() -> void:
	weapon_system.select_next_slot()
	weapon_system.sync_armed_cell_to_selection()
	queue_redraw()

func select_prev_slot() -> void:
	weapon_system.select_prev_slot()
	weapon_system.sync_armed_cell_to_selection()
	queue_redraw()

func toggle_range() -> void:
	show_range = !show_range
	queue_redraw()

func select_weapon_and_buy(weapon_type: int) -> void:
	weapon_system.select_weapon_and_buy(weapon_type)
	queue_redraw()

func set_ai_move_command(dir: Vector2) -> void:
	ai_move = dir

func apply_damage(amount: float, stun_duration: float, source: Node = null, weapon_type: int = -1) -> void:
	if not is_ai:
		amount *= HUMAN_DAMAGE_MULTIPLIER
	var armor_cells = 0
	if shape != null:
		armor_cells = max(0, shape.cells.size() - 1)
	var armor_reduction = clampf(armor_cells * ARMOR_REDUCTION_PER_CELL, 0.0, ARMOR_REDUCTION_MAX)
	amount *= (1.0 - armor_reduction)
	health -= amount
	regen_timer = regen_delay
	if stun_duration > 0.0:
		stun_time = maxf(stun_time, stun_duration)
	damage_flash = 0.25
	damage_blink_timer = 0.18
	damage_blink_phase = 0.0
	damage_blink_color = _get_damage_blink_color(weapon_type)
	if health <= 0.0 and not is_dying:
		if source != null and source.has_method("award_kill_reward"):
			source.award_kill_reward(_compute_kill_reward())
		elif source != null and source.has_method("add_xp"):
			source.add_xp(_compute_kill_reward())
		emit_signal("died", self)
		_start_death()

func _compute_kill_reward() -> float:
	var cell_count = 1
	if shape != null:
		cell_count = max(1, shape.cells.size())
	var reward = KILL_REWARD_BASE + float(max(0, cell_count - 1)) * KILL_REWARD_PER_EXTRA_CELL
	reward = minf(reward, KILL_REWARD_MAX)
	var world = get_tree().get_first_node_in_group("world")
	if world != null and world.has_method("get_kill_reward_multiplier"):
		reward *= float(world.get_kill_reward_multiplier())
	return reward

func local_to_grid(v: Vector2) -> Vector2i:
	return shape.local_to_grid(v)

func get_active_cell_grid_pos() -> Vector2i:
	return weapon_system.get_armed_cell()

func get_active_cell_world_pos() -> Vector2:
	if shape == null:
		return global_position
	var active = weapon_system.get_armed_cell()
	if not shape.cells.has(active):
		return global_position
	return global_position + shape.grid_to_local(active)

func _set_active_cell(grid_pos: Vector2i) -> void:
	if shape == null:
		return
	if not shape.cells.has(grid_pos):
		return
	weapon_system.set_armed_cell(grid_pos)
	queue_redraw()

func _try_place_cell(grid_pos: Vector2i) -> void:
	if xp < EXPAND_COST:
		return
	var valid = _get_valid_expand_cells().has(grid_pos)
	if not valid:
		return
	if shape.add_cell(grid_pos):
		xp -= EXPAND_COST
		expansions_bought += 1
		weapon_system.on_shape_changed()
		_set_active_cell(grid_pos)
		queue_redraw()

func _get_valid_expand_cells() -> Array[Vector2i]:
	var valid: Array[Vector2i] = []
	var active_cell = weapon_system.get_armed_cell()
	if not shape.cells.has(active_cell):
		return valid
	for dir in PlayerShapeScript.DIRS:
		var neighbor = active_cell + dir
		if shape.cells.has(neighbor):
			continue
		valid.append(neighbor)
	return valid

func _draw() -> void:
	_draw_death_fx()
	_draw_spawn_fx()
	_draw_cells()
	_draw_repel_pulses()
	if expand_hold:
		_draw_expand_ghosts()
	_draw_selected_slot_range()
	if debug_collision:
		_draw_collision_debug()

func _draw_cells() -> void:
	var outline := Color(0.92, 0.96, 1.0, 0.9)
	var outline_active := Color(0.96, 1.0, 1.0, 1.0)
	var inner := Color(0.92, 0.96, 1.0, 0.25)
	var blink_active := damage_blink_timer > 0.0
	var blink_strength := 0.5 + 0.5 * sin(damage_blink_phase)
	var blink_outline := Color(damage_blink_color.r, damage_blink_color.g, damage_blink_color.b, 0.95)
	var blink_inner := Color(damage_blink_color.r, damage_blink_color.g, damage_blink_color.b, 0.35)
	var armed_cell: Vector2i = weapon_system.get_armed_cell()
	var active_pulse = 0.5 + 0.5 * sin(active_pulse_phase)
	for grid_pos in shape.cells.keys():
		var local_pos = shape.grid_to_local(grid_pos)
		var half = PlayerShapeScript.CELL_SIZE * 0.5
		var rect = Rect2(local_pos - Vector2.ONE * half, Vector2.ONE * PlayerShapeScript.CELL_SIZE)
		var border_color := outline_active if grid_pos == armed_cell else outline
		if blink_active:
			border_color = border_color.lerp(blink_outline, blink_strength)
		var border_width := 1.6 if grid_pos == armed_cell else 1.2
		draw_rect(rect, border_color, false, border_width)
		if grid_pos == armed_cell:
			var glow = Color(0.4, 0.95, 1.0, 0.32 + 0.28 * active_pulse)
			draw_rect(rect.grow(2.5), glow, false, 1.2 + 0.9 * active_pulse)
		var inner_color := inner
		if blink_active:
			inner_color = inner_color.lerp(blink_inner, blink_strength)
		draw_line(rect.position + Vector2(half, 0.0), rect.position + Vector2(half, rect.size.y), inner_color, 1.0)
		draw_line(rect.position + Vector2(0.0, half), rect.position + Vector2(rect.size.x, half), inner_color, 1.0)

		_draw_pulse_edges(rect)

func _get_damage_blink_color(weapon_type: int) -> Color:
	match weapon_type:
		WeaponSlot.WeaponType.LASER:
			return Color(0.2, 0.95, 1.0, 1.0)
		WeaponSlot.WeaponType.STUN:
			return Color(0.2, 1.0, 0.4, 1.0)
		WeaponSlot.WeaponType.HOMING:
			return Color(1.0, 0.6, 0.15, 1.0)
		WeaponSlot.WeaponType.SPREAD:
			return Color(0.75, 0.4, 1.0, 1.0)
		_:
			return Color(1.0, 0.4, 0.4, 1.0)

func _play_critical_sfx() -> void:
	if is_ai:
		return
	_ensure_event_audio_loaded()
	_play_event_sfx(critical_sfx, -4.5)

func _play_event_sfx(stream: AudioStream, volume_db: float) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0
	var world := get_tree().get_first_node_in_group("world")
	if world != null:
		world.add_child(player)
	else:
		get_tree().current_scene.add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

func _ensure_event_audio_loaded() -> void:
	if event_audio_loaded:
		return
	event_audio_loaded = true
	critical_sfx = _load_imported_audio(CRITICAL_SFX_PATH)
	if critical_sfx == null:
		critical_sfx = ResourceLoader.load(CRITICAL_SFX_PATH) as AudioStream

func _load_imported_audio(source_path: String) -> AudioStream:
	var import_path := source_path + ".import"
	var cfg := ConfigFile.new()
	if cfg.load(import_path) != OK:
		return null
	var remap_path := cfg.get_value("remap", "path", "") as String
	if remap_path.is_empty():
		return null
	return ResourceLoader.load(remap_path) as AudioStream

func _draw_pulse_edges(rect: Rect2) -> void:
	for pulse in pulses:
		if pulse["grid_pos"] != shape.local_to_grid(rect.position + rect.size * 0.5):
			continue
		var t = pulse["time"] / pulse["life"]
		var color = Color(0.8, 0.95, 1.0, 0.6 * t)
		var p1 = rect.position
		var p2 = rect.position + Vector2(rect.size.x, 0.0)
		var p3 = rect.position + rect.size
		var p4 = rect.position + Vector2(0.0, rect.size.y)
		match pulse["dir"]:
			"N":
				draw_line(p1, p2, color, 2.0)
			"E":
				draw_line(p2, p3, color, 2.0)
			"S":
				draw_line(p4, p3, color, 2.0)
			"W":
				draw_line(p1, p4, color, 2.0)

func _draw_repel_pulses() -> void:
	for pulse in repel_pulses:
		var t = pulse["time"] / pulse["life"]
		var radius = lerpf(6.0, 16.0, 1.0 - t)
		var alpha = 0.5 * t
		var color = Color(0.6, 0.9, 1.0, alpha)
		var local_pos = to_local(pulse["pos"])
		draw_arc(local_pos, radius, 0.0, TAU, 48, color, 1.2)

func _draw_expand_ghosts() -> void:
	var color := Color(0.4, 0.9, 1.0, 0.35)
	for grid_pos in _get_valid_expand_cells():
		var local_pos = shape.grid_to_local(grid_pos)
		var half = PlayerShapeScript.CELL_SIZE * 0.5
		var rect = Rect2(local_pos - Vector2.ONE * half, Vector2.ONE * PlayerShapeScript.CELL_SIZE)
		_draw_dashed_rect(rect, color)

func _draw_dashed_rect(rect: Rect2, color: Color) -> void:
	var dash := 6.0
	var gap := 4.0
	_draw_dashed_line(rect.position, rect.position + Vector2(rect.size.x, 0.0), color, dash, gap)
	_draw_dashed_line(rect.position + Vector2(rect.size.x, 0.0), rect.position + rect.size, color, dash, gap)
	_draw_dashed_line(rect.position + rect.size, rect.position + Vector2(0.0, rect.size.y), color, dash, gap)
	_draw_dashed_line(rect.position + Vector2(0.0, rect.size.y), rect.position, color, dash, gap)

func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, dash: float, gap: float) -> void:
	var total = from.distance_to(to)
	var dir = (to - from).normalized()
	var dist = 0.0
	while dist < total:
		var seg_len = minf(dash, total - dist)
		var start = from + dir * dist
		var end = start + dir * seg_len
		draw_line(start, end, color, 1.2)
		dist += dash + gap

func _draw_selected_slot_range() -> void:
	if not show_range:
		return
	var slot = weapon_system.get_selected_slot()
	if slot == null:
		return
	var origin = weapon_system.get_slot_world_origin(slot)
	var local_origin = to_local(origin)
	var blocked = weapon_system.is_slot_blocked(slot)
	var glow = Color(0.6, 0.2, 0.2, 0.35) if blocked else Color(0.2, 0.9, 1.0, 0.25)
	var core = Color(0.9, 0.4, 0.4, 0.6) if blocked else Color(0.4, 1.0, 1.0, 0.75)
	_draw_dotted_ring(local_origin, slot.range, glow, 3.0, range_phase, 0.08, 0.12)
	_draw_dotted_ring(local_origin, slot.range, core, 1.4, range_phase + 0.3, 0.06, 0.12)

func _draw_ring(center: Vector2, radius: float, color: Color, width: float) -> void:
	draw_arc(center, radius, 0.0, TAU, 96, color, width)

func _draw_dotted_ring(
	center: Vector2,
	radius: float,
	color: Color,
	width: float,
	phase: float,
	dash_angle: float,
	gap_angle: float
) -> void:
	var angle := phase
	while angle < TAU + phase:
		var a0 := angle
		var a1 := minf(angle + dash_angle, TAU + phase)
		var p0 := center + Vector2(cos(a0), sin(a0)) * radius
		var p1 := center + Vector2(cos(a1), sin(a1)) * radius
		draw_line(p0, p1, color, width)
		angle += dash_angle + gap_angle

func _spawn_pulse() -> void:
	if shape.cells.is_empty():
		return
	var keys = shape.cells.keys()
	var grid_pos = keys[randi() % keys.size()]
	var dirs = ["N", "E", "S", "W"]
	pulses.append({"grid_pos": grid_pos, "dir": dirs[randi() % dirs.size()], "time": 0.2, "life": 0.2})

func _apply_soft_collisions(_delta: float) -> void:
	var others = get_tree().get_nodes_in_group("combatants")
	var my_radius = _get_collision_radius()
	if debug_collision:
		debug_collisions.clear()
	for other in others:
		var node = other as Node2D
		if node == null or node == self:
			continue
		if not node.has_method("get_collision_radius"):
			continue
		var other_spawn = node.get("spawn_timer")
		if other_spawn != null and float(other_spawn) > 0.0:
			continue
		var collision = _get_cell_collision(node)
		var dist = collision.get("dist", 0.0)
		var min_dist = collision.get("min_dist", my_radius + node.get_collision_radius())
		if dist < 0.001:
			continue
		if dist >= min_dist:
			continue
		var dir = collision.get("dir", (global_position - node.global_position).normalized())
		var push = (min_dist - dist) * COLLISION_PUSH_SCALE
		if debug_collision:
			debug_collisions.append({
				"other": node,
				"dist": dist,
				"min_dist": min_dist,
				"push": push
			})
			if debug_collision_print_timer <= 0.0:
				var other_id = String(node.get("actor_id"))
				print("COLLIDE ", actor_id, " <-> ", other_id, " d=", dist, " md=", min_dist, " p=", push)
				debug_collision_print_timer = 0.5
		if is_ai:
			global_position += dir * push
		else:
			var other_is_ai = bool(node.get("is_ai"))
			if other_is_ai:
				global_position += dir * (push * COLLISION_PLAYER_PUSH_SCALE)
				node.global_position -= dir * (push * COLLISION_AI_PUSH_SCALE)
			else:
				global_position += dir * (push * COLLISION_PLAYER_PUSH_SCALE)
		if push > 0.35 and not is_ai:
			var pulse_pos = collision.get("self_pos", global_position - dir * my_radius)
			_spawn_repel_pulse(pulse_pos)

func _get_cell_collision(other: Node2D) -> Dictionary:
	var result: Dictionary = {}
	if shape == null:
		return result
	var other_shape = other.get_node_or_null("PlayerShape")
	if other_shape == null or not other_shape.has_method("grid_to_local"):
		return result
	var cell_radius = PlayerShapeScript.CELL_SIZE * 0.5
	var best_dist = INF
	var best_dir = Vector2.ZERO
	var best_self = Vector2.ZERO
	var best_other = Vector2.ZERO
	for my_cell in shape.cells.keys():
		var my_pos = global_position + shape.grid_to_local(my_cell)
		for other_cell in other_shape.cells.keys():
			var other_pos = other.global_position + other_shape.grid_to_local(other_cell)
			var to_me = my_pos - other_pos
			var dist = to_me.length()
			if dist < best_dist:
				best_dist = dist
				best_dir = to_me.normalized() if dist > 0.001 else Vector2.ZERO
				best_self = my_pos
				best_other = other_pos
	result["dist"] = best_dist
	result["min_dist"] = cell_radius * 2.0
	result["dir"] = best_dir
	result["self_pos"] = best_self
	result["other_pos"] = best_other
	return result

func _draw_collision_debug() -> void:
	var center := Vector2.ZERO
	var radius := _get_collision_radius()
	draw_arc(center, radius, 0.0, TAU, 48, Color(1.0, 0.3, 0.3, 0.2), 1.0)
	var font = ThemeDB.fallback_font
	var font_size = max(10, int(ThemeDB.fallback_font_size * 0.75))
	var y = -radius - 12.0
	for info in debug_collisions:
		var other = info.get("other", null) as Node2D
		if other == null or not is_instance_valid(other):
			continue
		var other_local = to_local(other.global_position)
		draw_line(center, other_local, Color(1.0, 0.6, 0.1, 0.6), 1.0)
		var text = "d=%.1f md=%.1f p=%.2f" % [info["dist"], info["min_dist"], info["push"]]
		draw_string(font, Vector2(-radius, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.8, 0.6, 0.85))
		y -= font_size + 2.0

func get_collision_radius() -> float:
	return _get_collision_radius()

func _get_collision_radius() -> float:
	if shape == null or shape.cells.is_empty():
		return PlayerShapeScript.CELL_SIZE * 0.5
	var max_dist := 0.0
	for grid_pos in shape.cells.keys():
		var local_pos = shape.grid_to_local(grid_pos)
		var dist = local_pos.length() + PlayerShapeScript.CELL_SIZE * 0.5
		if dist > max_dist:
			max_dist = dist
	return max_dist

func _spawn_repel_pulse(world_pos: Vector2) -> void:
	if repel_pulses.size() > 10:
		repel_pulses.pop_front()
	repel_pulses.append({
		"pos": world_pos,
		"time": COLLISION_PULSE_LIFE,
		"life": COLLISION_PULSE_LIFE
	})

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
	var expand := lerpf(1.6, 1.0, t)
	var glow := Color(0.6, 0.9, 1.0, 0.5 * (1.0 - t))
	for grid_pos: Vector2i in shape.cells.keys():
		var local_pos: Vector2 = shape.grid_to_local(grid_pos)
		var half := PlayerShapeScript.CELL_SIZE * 0.5 * expand
		var rect := Rect2(local_pos - Vector2.ONE * half, Vector2.ONE * PlayerShapeScript.CELL_SIZE * expand)
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
	scale = Vector2.ONE * lerpf(1.0, 0.4, 1.0 - t)
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
	var flash := Color(1.0, 0.7, 0.3, 0.9 * (1.0 - t))
	var expand := lerpf(1.0, 1.8, 1.0 - t)
	for grid_pos: Vector2i in shape.cells.keys():
		var local_pos: Vector2 = shape.grid_to_local(grid_pos)
		var half := PlayerShapeScript.CELL_SIZE * 0.5 * expand
		var rect := Rect2(local_pos - Vector2.ONE * half, Vector2.ONE * PlayerShapeScript.CELL_SIZE * expand)
		draw_rect(rect, flash, false, 2.2)

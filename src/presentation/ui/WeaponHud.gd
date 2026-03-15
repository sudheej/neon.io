extends Control

const WeaponSlot = preload("res://src/domain/weapons/WeaponSlot.gd")

const WEAPON_ORDER := [
	WeaponSlot.WeaponType.LASER,
	WeaponSlot.WeaponType.STUN,
	WeaponSlot.WeaponType.HOMING,
	WeaponSlot.WeaponType.SPREAD
]
const WEAPON_KEYS := {
	WeaponSlot.WeaponType.LASER: "1",
	WeaponSlot.WeaponType.STUN: "2",
	WeaponSlot.WeaponType.HOMING: "3",
	WeaponSlot.WeaponType.SPREAD: "4"
}
const WEAPON_NAMES := {
	WeaponSlot.WeaponType.LASER: "LASER",
	WeaponSlot.WeaponType.STUN: "STUN",
	WeaponSlot.WeaponType.HOMING: "HOMING",
	WeaponSlot.WeaponType.SPREAD: "SPREAD"
}
const WEAPON_COLORS := {
	WeaponSlot.WeaponType.LASER: Color(0.34, 0.9, 1.0, 1.0),
	WeaponSlot.WeaponType.STUN: Color(0.34, 0.9, 1.0, 1.0),
	WeaponSlot.WeaponType.HOMING: Color(0.34, 0.9, 1.0, 1.0),
	WeaponSlot.WeaponType.SPREAD: Color(0.34, 0.9, 1.0, 1.0)
}

const XP_STEP := 60.0
const REF_SIZE := Vector2(286.0, 238.0)
const PANEL_RADIUS := 16.0
const PANEL_BG := Color(0.01, 0.04, 0.08, 0.83)
const PANEL_INNER := Color(0.02, 0.07, 0.12, 0.82)
const PANEL_OUTLINE := Color(0.24, 0.78, 0.96, 0.6)
const PANEL_GLOW := Color(0.1, 0.72, 1.0, 0.05)
const DIVIDER := Color(0.18, 0.44, 0.58, 0.34)
const TEXT_PRIMARY := Color(0.93, 0.98, 1.0, 0.98)
const TEXT_MUTED := Color(0.48, 0.78, 0.9, 0.7)
const TEXT_SOFT := Color(0.62, 0.88, 0.96, 0.92)
const BAR_BG := Color(0.07, 0.14, 0.2, 0.92)
const CHIP_BG := Color(0.08, 0.15, 0.22, 0.95)

@export var target_actor_id: String = "player"

var player: Node = null
var weapon_system: Node = null
var selected_weapon: int = WeaponSlot.WeaponType.LASER
var selection_strength: Dictionary = {}
var flash_time: float = 0.0
var displayed_xp: float = 0.0
var displayed_health: float = 0.0
var displayed_max_health: float = 0.0
var xp_flash: float = 0.0
var xp_hint_timer: float = 0.0
var xp_hint_value: int = 0
var hud_presence: float = 0.0
var _xp_initialized: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for weapon_type in WEAPON_ORDER:
		selection_strength[weapon_type] = 0.0
	_resolve_player()
	set_process(true)

func _process(delta: float) -> void:
	_resolve_player()
	hud_presence = lerpf(hud_presence, 1.0, 1.0 - exp(-10.0 * delta))
	_update_xp_animation(delta)
	_update_health_animation(delta)
	_update_weapon_animation(delta)
	queue_redraw()

func _update_xp_animation(delta: float) -> void:
	var xp_now := _get_player_xp()
	if not _xp_initialized:
		displayed_xp = xp_now
		_xp_initialized = true
	elif absf(displayed_xp - xp_now) > 0.05:
		if xp_now > displayed_xp + 0.1:
			xp_flash = 1.0
			xp_hint_timer = 2.4
			xp_hint_value = int(ceil(maxf(_get_next_xp_threshold(xp_now) - xp_now, 0.0)))
		displayed_xp = lerpf(displayed_xp, xp_now, 1.0 - exp(-12.0 * delta))
	else:
		displayed_xp = xp_now
	xp_flash = maxf(0.0, xp_flash - delta * 2.8)
	xp_hint_timer = maxf(0.0, xp_hint_timer - delta)

func _update_health_animation(delta: float) -> void:
	var health_now := _get_player_health()
	var max_health_now := _get_player_max_health()
	if displayed_max_health <= 0.0:
		displayed_max_health = max_health_now
		displayed_health = health_now
		return
	displayed_max_health = lerpf(displayed_max_health, max_health_now, 1.0 - exp(-10.0 * delta))
	displayed_health = lerpf(displayed_health, health_now, 1.0 - exp(-16.0 * delta))

func _update_weapon_animation(delta: float) -> void:
	if weapon_system == null:
		flash_time = maxf(flash_time - delta, 0.0)
		for weapon_type in WEAPON_ORDER:
			var current_strength = float(selection_strength.get(weapon_type, 0.0))
			selection_strength[weapon_type] = lerpf(current_strength, 0.0, 1.0 - exp(-12.0 * delta))
		return
	var current = weapon_system.get_selected_weapon_type()
	if current != selected_weapon:
		selected_weapon = current
		flash_time = 1.0
	flash_time = maxf(flash_time - delta * 4.4, 0.0)
	for weapon_type in WEAPON_ORDER:
		var target = 1.0 if weapon_type == selected_weapon else 0.0
		var current_strength = float(selection_strength.get(weapon_type, 0.0))
		selection_strength[weapon_type] = lerpf(current_strength, target, 1.0 - exp(-16.0 * delta))

func _resolve_player() -> void:
	var expected_actor_id := _resolve_target_actor_id()
	if player != null and is_instance_valid(player):
		if player.is_queued_for_deletion():
			player = null
			weapon_system = null
		elif not expected_actor_id.is_empty() and String(player.get("actor_id")) != expected_actor_id:
			player = null
			weapon_system = null
	if player == null or not is_instance_valid(player):
		player = _find_player_by_actor_id(expected_actor_id)
		if player == null and expected_actor_id == "player":
			player = get_tree().get_first_node_in_group("player")
		weapon_system = null
	if weapon_system == null and player != null and player.has_node("WeaponSystem"):
		weapon_system = player.get_node("WeaponSystem")
	elif weapon_system != null and (not is_instance_valid(weapon_system) or weapon_system.get_parent() != player):
		weapon_system = null

func set_target_actor_id(actor_id: String) -> void:
	target_actor_id = actor_id
	player = null
	weapon_system = null
	_xp_initialized = false
	_resolve_player()

func _find_player_by_actor_id(actor_id: String) -> Node:
	if actor_id.is_empty():
		return null
	var world := get_tree().get_first_node_in_group("world")
	if world != null:
		var local_candidate = world.get("local_player")
		if (
			local_candidate != null
			and is_instance_valid(local_candidate)
			and not local_candidate.is_queued_for_deletion()
			and String(local_candidate.get("actor_id")) == actor_id
		):
			return local_candidate as Node
	for node in get_tree().get_nodes_in_group("combatants"):
		if node == null or not is_instance_valid(node):
			continue
		if node.is_queued_for_deletion():
			continue
		if String(node.get("actor_id")) == actor_id:
			return node as Node
	return null

func _resolve_target_actor_id() -> String:
	if not target_actor_id.is_empty():
		return target_actor_id
	var world := get_tree().get_first_node_in_group("world")
	if world != null:
		var world_actor_id := String(world.get("local_actor_id"))
		if not world_actor_id.is_empty():
			return world_actor_id
	return "player"

func _draw() -> void:
	var width_scale := clampf(size.x / REF_SIZE.x, 0.8, 1.35)
	var height_scale := clampf(size.y / REF_SIZE.y, 0.8, 1.35)
	var hud_scale := minf(width_scale, height_scale)
	var alpha := clampf(hud_presence, 0.0, 1.0)
	var outer := Rect2(Vector2.ZERO, size)
	var shell := outer.grow(-4.0 * hud_scale)
	var header_h := 64.0 * hud_scale
	var section_pad := 16.0 * hud_scale
	var row_h := 29.0 * hud_scale
	var row_gap := 9.0 * hud_scale

	_draw_shell(shell, hud_scale, alpha)
	_draw_header(shell, section_pad, header_h, hud_scale, alpha)

	var list_top := shell.position.y + header_h + 18.0 * hud_scale
	draw_line(
		Vector2(shell.position.x + section_pad, list_top - 8.0 * hud_scale),
		Vector2(shell.end.x - section_pad, list_top - 8.0 * hud_scale),
		Color(DIVIDER.r, DIVIDER.g, DIVIDER.b, 0.8 * alpha),
		1.0
	)

	var y := list_top
	for weapon_type in WEAPON_ORDER:
		_draw_weapon_row(Rect2(shell.position.x + section_pad, y, shell.size.x - section_pad * 2.0, row_h), weapon_type, hud_scale, alpha)
		y += row_h + row_gap

func _draw_shell(rect: Rect2, hud_scale: float, alpha: float) -> void:
	draw_rect(rect, Color(PANEL_BG.r, PANEL_BG.g, PANEL_BG.b, PANEL_BG.a * alpha), true)
	draw_rect(rect.grow(-2.0 * hud_scale), Color(PANEL_INNER.r, PANEL_INNER.g, PANEL_INNER.b, PANEL_INNER.a * alpha), true)
	draw_rect(rect.grow(4.0 * hud_scale), Color(PANEL_GLOW.r, PANEL_GLOW.g, PANEL_GLOW.b, PANEL_GLOW.a * alpha), false, 2.0)
	_draw_notched_outline(rect, 12.0 * hud_scale, Color(PANEL_OUTLINE.r, PANEL_OUTLINE.g, PANEL_OUTLINE.b, PANEL_OUTLINE.a * alpha))

func _draw_notched_outline(rect: Rect2, notch: float, color: Color) -> void:
	var points := PackedVector2Array([
		Vector2(rect.position.x + notch, rect.position.y),
		Vector2(rect.end.x - notch, rect.position.y),
		Vector2(rect.end.x, rect.position.y + notch),
		Vector2(rect.end.x, rect.end.y - notch),
		Vector2(rect.end.x - notch, rect.end.y),
		Vector2(rect.position.x + notch, rect.end.y),
		Vector2(rect.position.x, rect.end.y - notch),
		Vector2(rect.position.x, rect.position.y + notch),
		Vector2(rect.position.x + notch, rect.position.y)
	])
	draw_polyline(points, color, 1.4, true)
	draw_line(rect.position + Vector2(22.0, 0.0), rect.position + Vector2(64.0, 0.0), color, 2.0)
	draw_line(Vector2(rect.end.x - 58.0, rect.position.y), Vector2(rect.end.x - 16.0, rect.position.y), color, 2.0)

func _draw_header(rect: Rect2, pad: float, header_h: float, hud_scale: float, alpha: float) -> void:
	var header_rect := Rect2(rect.position.x + pad, rect.position.y + 14.0 * hud_scale, rect.size.x - pad * 2.0, header_h)
	var xp_now := displayed_xp
	var xp_main_color := TEXT_PRIMARY.lerp(WEAPON_COLORS[WeaponSlot.WeaponType.LASER], xp_flash * 0.35)
	var xp_label_y := header_rect.position.y + 12.0 * hud_scale

	var font := get_theme_font("font")
	if font == null:
		font = get_theme_default_font()
	draw_string(font, Vector2(header_rect.position.x, xp_label_y), "XP", HORIZONTAL_ALIGNMENT_LEFT, -1, int(18.0 * hud_scale), Color(TEXT_MUTED.r, TEXT_MUTED.g, TEXT_MUTED.b, alpha))
	var xp_text := str(int(round(xp_now)))
	draw_string(font, Vector2(header_rect.position.x, xp_label_y + 28.0 * hud_scale), xp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(28.0 * hud_scale), Color(xp_main_color.r, xp_main_color.g, xp_main_color.b, alpha))
	if xp_hint_timer > 0.0 and xp_hint_value > 0:
		var hint_alpha := alpha * minf(xp_hint_timer / 2.4, 1.0)
		var xp_width := font.get_string_size(xp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(28.0 * hud_scale)).x
		draw_string(font, Vector2(header_rect.position.x + xp_width + 10.0 * hud_scale, xp_label_y + 25.0 * hud_scale), "+%d" % xp_hint_value, HORIZONTAL_ALIGNMENT_LEFT, -1, int(14.0 * hud_scale), Color(TEXT_SOFT.r, TEXT_SOFT.g, TEXT_SOFT.b, hint_alpha))

	var hp_ratio := 0.0
	if displayed_max_health > 0.0:
		hp_ratio = clampf(displayed_health / displayed_max_health, 0.0, 1.0)
	var hp_text := "%d/%d" % [int(round(displayed_health)), int(round(displayed_max_health))]
	var hp_value_size := font.get_string_size(hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(12.0 * hud_scale))
	var right_block_x := header_rect.position.x + header_rect.size.x * 0.6
	var hp_value_y := header_rect.position.y + 14.0 * hud_scale
	draw_string(font, Vector2(header_rect.end.x - hp_value_size.x, hp_value_y), hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(12.0 * hud_scale), Color(TEXT_SOFT.r, TEXT_SOFT.g, TEXT_SOFT.b, alpha))
	var health_label_y := header_rect.position.y + 34.0 * hud_scale
	draw_string(font, Vector2(right_block_x, health_label_y), "HEALTH", HORIZONTAL_ALIGNMENT_LEFT, -1, int(12.0 * hud_scale), Color(TEXT_MUTED.r, TEXT_MUTED.g, TEXT_MUTED.b, alpha))

	var bar_rect := Rect2(right_block_x, header_rect.position.y + 44.0 * hud_scale, header_rect.end.x - right_block_x, 5.0 * hud_scale)
	draw_rect(bar_rect, Color(BAR_BG.r, BAR_BG.g, BAR_BG.b, alpha), true)
	var bar_fill_rect := bar_rect.grow_individual(-1.0, -1.0, -1.0, -1.0)
	var fill_color := TEXT_SOFT
	if hp_ratio <= 0.4:
		fill_color = Color(0.95, 0.38, 0.38, 1.0)
	if hp_ratio > 0.0 and bar_fill_rect.size.x > 0.0 and bar_fill_rect.size.y > 0.0:
		draw_rect(Rect2(bar_fill_rect.position, Vector2(bar_fill_rect.size.x * hp_ratio, bar_fill_rect.size.y)), Color(fill_color.r, fill_color.g, fill_color.b, 0.96 * alpha), true)
	draw_rect(bar_rect, Color(PANEL_OUTLINE.r, PANEL_OUTLINE.g, PANEL_OUTLINE.b, 0.34 * alpha), false, 1.0)

func _draw_weapon_row(rect: Rect2, weapon_type: int, hud_scale: float, alpha: float) -> void:
	var active := float(selection_strength.get(weapon_type, 0.0))
	var accent: Color = WEAPON_COLORS[weapon_type]
	var font := get_theme_font("font")
	if font == null:
		font = get_theme_default_font()
	var bg_alpha := lerpf(0.16, 0.34, active)
	draw_rect(rect, Color(PANEL_INNER.r, PANEL_INNER.g, PANEL_INNER.b, bg_alpha * alpha), true)
	draw_rect(rect, Color(DIVIDER.r, DIVIDER.g, DIVIDER.b, (0.35 + active * 0.35) * alpha), false, 1.0)

	var left_accent_h := lerpf(7.0, rect.size.y - 6.0 * hud_scale, active)
	draw_rect(Rect2(rect.position.x, rect.position.y + (rect.size.y - left_accent_h) * 0.5, 3.0 * hud_scale, left_accent_h), Color(accent.r, accent.g, accent.b, (0.44 + active * 0.56) * alpha), true)

	var key_rect := Rect2(rect.position.x + 10.0 * hud_scale, rect.position.y + 5.5 * hud_scale, 20.0 * hud_scale, 16.0 * hud_scale)
	draw_rect(key_rect, Color(CHIP_BG.r, CHIP_BG.g, CHIP_BG.b, 0.96 * alpha), true)
	draw_rect(key_rect, Color(accent.r, accent.g, accent.b, 0.5 * alpha), false, 1.0)
	var key_text: String = String(WEAPON_KEYS[weapon_type])
	var key_size := font.get_string_size(key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(12.0 * hud_scale))
	draw_string(font, Vector2(key_rect.position.x + (key_rect.size.x - key_size.x) * 0.5, key_rect.position.y + 12.5 * hud_scale), key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(11.0 * hud_scale), Color(TEXT_PRIMARY.r, TEXT_PRIMARY.g, TEXT_PRIMARY.b, alpha))

	var label_x := key_rect.end.x + 10.0 * hud_scale
	draw_string(font, Vector2(label_x, rect.position.y + 14.0 * hud_scale), WEAPON_NAMES[weapon_type], HORIZONTAL_ALIGNMENT_LEFT, -1, int(15.0 * hud_scale), Color(TEXT_PRIMARY.r, TEXT_PRIMARY.g, TEXT_PRIMARY.b, alpha))

	var ammo := 0
	if weapon_system != null and weapon_system.has_method("get_weapon_ammo"):
		ammo = weapon_system.get_weapon_ammo(weapon_type)
	var cap := _get_capacity(weapon_type)
	var ratio := 0.0
	if cap > 0:
		ratio = clampf(float(ammo) / float(cap), 0.0, 1.0)

	var ammo_text := str(ammo)
	var ammo_size := font.get_string_size(ammo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(21.0 * hud_scale))
	var ammo_x := rect.end.x - ammo_size.x - 10.0 * hud_scale
	draw_string(font, Vector2(ammo_x, rect.position.y + 16.0 * hud_scale), ammo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(21.0 * hud_scale), Color(accent.r, accent.g, accent.b, alpha))

	var bar_rect := Rect2(label_x, rect.position.y + rect.size.y - 6.0 * hud_scale, ammo_x - label_x - 12.0 * hud_scale, 3.0 * hud_scale)
	draw_rect(bar_rect, Color(BAR_BG.r, BAR_BG.g, BAR_BG.b, 0.92 * alpha), true)
	var bar_fill_rect := bar_rect.grow_individual(-1.0, 0.0, -1.0, 0.0)
	if ratio > 0.0 and bar_fill_rect.size.x > 0.0:
		draw_rect(Rect2(bar_fill_rect.position, Vector2(bar_fill_rect.size.x * ratio, bar_fill_rect.size.y)), Color(accent.r, accent.g, accent.b, (0.82 + active * 0.18) * alpha), true)

func _get_capacity(weapon_type: int) -> int:
	if weapon_system == null:
		return 0
	if weapon_system.has_method("get_weapon_capacity"):
		return weapon_system.get_weapon_capacity(weapon_type)
	var pack_amount = weapon_system.get_weapon_pack_ammo(weapon_type)
	var starting = weapon_system.get_weapon_ammo(weapon_type)
	return max(starting, pack_amount * 4)

func _get_player_xp() -> float:
	if player == null or not is_instance_valid(player):
		return 0.0
	var value = player.get("xp")
	if value == null:
		return 0.0
	return maxf(float(value), 0.0)

func _get_next_xp_threshold(xp_value: float) -> float:
	if xp_value <= 0.0:
		return XP_STEP
	return maxf(ceil((xp_value + 0.001) / XP_STEP) * XP_STEP, XP_STEP)

func _get_player_health() -> float:
	if player == null or not is_instance_valid(player):
		return 0.0
	var value = player.get("health")
	if value == null:
		return 0.0
	return maxf(float(value), 0.0)

func _get_player_max_health() -> float:
	if player == null or not is_instance_valid(player):
		return 1.0
	var value = player.get("max_health")
	if value == null:
		return 1.0
	return maxf(float(value), 1.0)

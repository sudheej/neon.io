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

const PADDING := Vector2(12.0, 10.0)
const ROW_HEIGHT := 38.0
const ROW_GAP := 4.0
const RING_RADIUS := 16.0
const RING_WIDTH := 2.0
const BAR_WIDTH := 72.0
const BAR_HEIGHT := 4.0
const PANEL_RADIUS := 6.0

const PANEL_BG := Color(0.04, 0.06, 0.08, 0.82)
const PANEL_BORDER := Color(0.2, 0.9, 1.0, 0.75)
const PANEL_GLOW := Color(0.0, 1.0, 1.0, 0.18)
const ROW_GLOW := Color(0.2, 0.9, 1.0, 0.2)
const TEXT_PRIMARY := Color(0.9, 0.96, 1.0, 0.9)
const TEXT_MUTED := Color(0.55, 0.85, 1.0, 0.65)
const BAR_BG := Color(0.1, 0.22, 0.28, 0.6)
const BAR_FILL := Color(0.2, 0.95, 1.0, 0.9)
const RING_BG := Color(0.2, 0.5, 0.6, 0.4)
const RING_FILL := Color(0.2, 0.95, 1.0, 0.95)

@export var target_actor_id: String = "player"

var player: Node = null
var weapon_system: Node = null
var selected_weapon: int = WeaponSlot.WeaponType.LASER
var selection_strength: Dictionary = {}
var flash_time: float = 0.0
var _panel_style: StyleBoxFlat = StyleBoxFlat.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_style.bg_color = PANEL_BG
	_panel_style.border_color = PANEL_BORDER
	_panel_style.border_width_left = 1
	_panel_style.border_width_top = 1
	_panel_style.border_width_right = 1
	_panel_style.border_width_bottom = 1
	_panel_style.corner_radius_top_left = PANEL_RADIUS
	_panel_style.corner_radius_top_right = PANEL_RADIUS
	_panel_style.corner_radius_bottom_left = PANEL_RADIUS
	_panel_style.corner_radius_bottom_right = PANEL_RADIUS
	for weapon_type in WEAPON_ORDER:
		selection_strength[weapon_type] = 0.0
	_resolve_player()
	set_process(true)

func _process(delta: float) -> void:
	_resolve_player()
	if weapon_system == null:
		return
	var current = weapon_system.get_selected_weapon_type()
	if current != selected_weapon:
		selected_weapon = current
		flash_time = 0.22
	flash_time = maxf(flash_time - delta, 0.0)
	for weapon_type in WEAPON_ORDER:
		var target = 1.0 if weapon_type == selected_weapon else 0.0
		var current_strength = float(selection_strength.get(weapon_type, 0.0))
		selection_strength[weapon_type] = _smooth(current_strength, target, delta, 10.0)
	queue_redraw()

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

func _smooth(value: float, target: float, delta: float, speed: float) -> float:
	return lerp(value, target, 1.0 - exp(-speed * delta))

func _draw() -> void:
	var rect = Rect2(Vector2.ZERO, size)
	draw_style_box(_panel_style, rect)
	draw_rect(rect.grow(-3.0), PANEL_GLOW, false, 1.0)

	var width_scale = clampf(size.x / 288.0, 0.72, 1.5)
	var height_scale = clampf(size.y / 184.0, 0.72, 1.5)
	var hud_scale = minf(width_scale, height_scale)
	var padding: Vector2 = PADDING * hud_scale
	var row_height: float = ROW_HEIGHT * hud_scale
	var row_gap: float = ROW_GAP * hud_scale
	var ring_radius: float = RING_RADIUS * hud_scale
	var ring_width: float = maxf(1.2, RING_WIDTH * hud_scale)
	var bar_width: float = BAR_WIDTH * hud_scale
	var bar_height: float = maxf(3.0, BAR_HEIGHT * hud_scale)

	var font = get_theme_default_font()
	var font_size = max(10, int(get_theme_default_font_size() * 0.85 * hud_scale))
	var small_size = max(9, int(font_size * 0.8))
	var percent_size = max(8, int(small_size * 0.9))

	var y = padding.y
	for weapon_type in WEAPON_ORDER:
		var center_y = y + row_height * 0.5
		var glow = float(selection_strength.get(weapon_type, 0.0))
		var flash = (flash_time / 0.22) if flash_time > 0.0 and weapon_type == selected_weapon else 0.0
		var glow_alpha = clamp(glow * 0.25 + flash * 0.25, 0.0, 0.4)
		if glow_alpha > 0.0:
			var glow_color = Color(ROW_GLOW.r, ROW_GLOW.g, ROW_GLOW.b, glow_alpha)
			draw_rect(Rect2(padding.x * 0.5, y - 3.0 * hud_scale, size.x - padding.x, row_height + 6.0 * hud_scale), glow_color, true)

		var label = "%s %s" % [WEAPON_KEYS[weapon_type], WEAPON_NAMES[weapon_type]]
		draw_string(font, Vector2(padding.x, center_y - 5.0 * hud_scale), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, TEXT_PRIMARY)

		if weapon_system != null and weapon_system.has_method("get_weapon_ammo"):
			var ammo = weapon_system.get_weapon_ammo(weapon_type)
			var ammo_text = "AMMO %d" % ammo
			draw_string(font, Vector2(padding.x, center_y + 10.0 * hud_scale), ammo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, small_size, TEXT_MUTED)

		var cap = _get_capacity(weapon_type)
		var ammo_value = 0
		if weapon_system != null and weapon_system.has_method("get_weapon_ammo"):
			ammo_value = weapon_system.get_weapon_ammo(weapon_type)
		var ratio = 0.0
		if cap > 0:
			ratio = clamp(float(ammo_value) / float(cap), 0.0, 1.0)

		var ring_center = Vector2(size.x - padding.x - ring_radius, center_y)
		var bar_right = ring_center.x - ring_radius - 10.0 * hud_scale
		var bar_rect = Rect2(bar_right - bar_width, center_y - bar_height * 0.5, bar_width, bar_height)

		draw_rect(bar_rect, BAR_BG, true)
		if ratio > 0.0:
			draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * ratio, bar_rect.size.y)), BAR_FILL, true)

		draw_arc(ring_center, ring_radius, -PI * 0.5, TAU - PI * 0.5, 64, RING_BG, ring_width)
		if ratio > 0.0:
			draw_arc(ring_center, ring_radius, -PI * 0.5, TAU * ratio - PI * 0.5, 64, RING_FILL, ring_width)

		var percent = int(round(ratio * 100.0))
		var percent_text = "%d%%" % percent
		var text_size = font.get_string_size(percent_text, HORIZONTAL_ALIGNMENT_LEFT, -1, percent_size)
		var baseline = ring_center.y + text_size.y * 0.35
		draw_string(font, Vector2(ring_center.x - text_size.x * 0.5, baseline), percent_text, HORIZONTAL_ALIGNMENT_LEFT, -1, percent_size, TEXT_PRIMARY)

		y += row_height + row_gap

func _get_capacity(weapon_type: int) -> int:
	if weapon_system == null:
		return 0
	if weapon_system.has_method("get_weapon_capacity"):
		return weapon_system.get_weapon_capacity(weapon_type)
	var pack_amount = weapon_system.get_weapon_pack_ammo(weapon_type)
	var starting = weapon_system.get_weapon_ammo(weapon_type)
	return max(starting, pack_amount * 4)

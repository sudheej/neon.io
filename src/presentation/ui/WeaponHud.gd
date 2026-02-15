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

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	if player == null or not is_instance_valid(player):
		player = _find_player_by_actor_id(target_actor_id)
		if player == null:
			player = get_tree().get_first_node_in_group("player")
		weapon_system = null
	if weapon_system == null and player != null and player.has_node("WeaponSystem"):
		weapon_system = player.get_node("WeaponSystem")

func set_target_actor_id(actor_id: String) -> void:
	target_actor_id = actor_id
	player = null
	weapon_system = null
	_resolve_player()

func _find_player_by_actor_id(actor_id: String) -> Node:
	if actor_id.is_empty():
		return null
	for node in get_tree().get_nodes_in_group("combatants"):
		if node == null or not is_instance_valid(node):
			continue
		if String(node.get("actor_id")) == actor_id:
			return node as Node
	return null

func _smooth(value: float, target: float, delta: float, speed: float) -> float:
	return lerp(value, target, 1.0 - exp(-speed * delta))

func _draw() -> void:
	var rect = Rect2(Vector2.ZERO, size)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = PANEL_BG
	panel_style.border_color = PANEL_BORDER
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.corner_radius_top_left = PANEL_RADIUS
	panel_style.corner_radius_top_right = PANEL_RADIUS
	panel_style.corner_radius_bottom_left = PANEL_RADIUS
	panel_style.corner_radius_bottom_right = PANEL_RADIUS
	draw_style_box(panel_style, rect)
	draw_rect(rect.grow(-3.0), PANEL_GLOW, false, 1.0)

	var font = get_theme_default_font()
	var font_size = max(10, int(get_theme_default_font_size() * 0.85))
	var small_size = max(9, int(font_size * 0.8))
	var percent_size = max(8, int(small_size * 0.9))

	var y = PADDING.y
	for weapon_type in WEAPON_ORDER:
		var center_y = y + ROW_HEIGHT * 0.5
		var glow = float(selection_strength.get(weapon_type, 0.0))
		var flash = (flash_time / 0.22) if flash_time > 0.0 and weapon_type == selected_weapon else 0.0
		var glow_alpha = clamp(glow * 0.25 + flash * 0.25, 0.0, 0.4)
		if glow_alpha > 0.0:
			var glow_color = Color(ROW_GLOW.r, ROW_GLOW.g, ROW_GLOW.b, glow_alpha)
			draw_rect(Rect2(PADDING.x * 0.5, y - 3.0, size.x - PADDING.x, ROW_HEIGHT + 6.0), glow_color, true)

		var label = "%s %s" % [WEAPON_KEYS[weapon_type], WEAPON_NAMES[weapon_type]]
		draw_string(font, Vector2(PADDING.x, center_y - 5.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, TEXT_PRIMARY)

		if weapon_system != null and weapon_system.has_method("get_weapon_ammo"):
			var ammo = weapon_system.get_weapon_ammo(weapon_type)
			var ammo_text = "AMMO %d" % ammo
			draw_string(font, Vector2(PADDING.x, center_y + 10.0), ammo_text, HORIZONTAL_ALIGNMENT_LEFT, -1, small_size, TEXT_MUTED)

		var cap = _get_capacity(weapon_type)
		var ammo_value = 0
		if weapon_system != null and weapon_system.has_method("get_weapon_ammo"):
			ammo_value = weapon_system.get_weapon_ammo(weapon_type)
		var ratio = 0.0
		if cap > 0:
			ratio = clamp(float(ammo_value) / float(cap), 0.0, 1.0)

		var ring_center = Vector2(size.x - PADDING.x - RING_RADIUS, center_y)
		var bar_right = ring_center.x - RING_RADIUS - 10.0
		var bar_rect = Rect2(bar_right - BAR_WIDTH, center_y - BAR_HEIGHT * 0.5, BAR_WIDTH, BAR_HEIGHT)

		draw_rect(bar_rect, BAR_BG, true)
		if ratio > 0.0:
			draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * ratio, bar_rect.size.y)), BAR_FILL, true)

		draw_arc(ring_center, RING_RADIUS, -PI * 0.5, TAU - PI * 0.5, 64, RING_BG, RING_WIDTH)
		if ratio > 0.0:
			draw_arc(ring_center, RING_RADIUS, -PI * 0.5, TAU * ratio - PI * 0.5, 64, RING_FILL, RING_WIDTH)

		var percent = int(round(ratio * 100.0))
		var percent_text = "%d%%" % percent
		var text_size = font.get_string_size(percent_text, HORIZONTAL_ALIGNMENT_LEFT, -1, percent_size)
		var baseline = ring_center.y + text_size.y * 0.35
		draw_string(font, Vector2(ring_center.x - text_size.x * 0.5, baseline), percent_text, HORIZONTAL_ALIGNMENT_LEFT, -1, percent_size, TEXT_PRIMARY)

		y += ROW_HEIGHT + ROW_GAP

func _get_capacity(weapon_type: int) -> int:
	if weapon_system == null:
		return 0
	if weapon_system.has_method("get_weapon_capacity"):
		return weapon_system.get_weapon_capacity(weapon_type)
	var pack_amount = weapon_system.get_weapon_pack_ammo(weapon_type)
	var starting = weapon_system.get_weapon_ammo(weapon_type)
	return max(starting, pack_amount * 4)

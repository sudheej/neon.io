extends Control

const PANEL_BG := Color(0.04, 0.06, 0.08, 0.82)
const PANEL_BORDER := Color(0.2, 0.9, 1.0, 0.75)
const PANEL_GLOW := Color(0.0, 1.0, 1.0, 0.18)
const MAP_BG := Color(0.02, 0.07, 0.1, 0.58)
const MAP_WORLD_BG := Color(0.05, 0.18, 0.24, 0.28)
const MAP_GRID := Color(0.32, 0.88, 0.98, 0.16)
const MAP_BORDER := Color(0.35, 0.95, 1.0, 0.9)
const PLAYER_COLOR := Color(0.22, 1.0, 0.92, 1.0)
const ENEMY_COLOR := Color(1.0, 0.42, 0.3, 0.9)
const OUTSIDE_DARK := Color(0.0, 0.0, 0.0, 0.52)

const PANEL_RADIUS := 6
const PANEL_PADDING := 10.0
const PLAYER_MARKER_SIZE := 7.0
const ENEMY_MARKER_SIZE := 4.5
const BORDER_THICKNESS := 1.3
const BORDER_PULSE_SPEED := 2.3
const SHOW_DURATION := 0.28
const HIDE_DURATION := 0.2
const CRT_LINE_PHASE := 0.22
const CRT_DOT_PHASE := 0.08

var _world: Node = null
var _boundary: Node = null
var _border_pulse_t: float = 0.0
var _is_shown: bool = true
var _fx_strength: float = 0.0
var _screen_power: float = 1.0
var _scanline_flash: float = 0.0
var _transition_tween: Tween = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_is_shown = visible
	_screen_power = 1.0 if _is_shown else 0.0
	modulate = Color(1.0, 1.0, 1.0, 1.0)
	_update_pivot()
	set_process(true)

func _process(delta: float) -> void:
	_border_pulse_t = fmod(_border_pulse_t + delta * BORDER_PULSE_SPEED, TAU)
	if _scanline_flash > 0.0:
		_scanline_flash = maxf(_scanline_flash - delta * 3.2, 0.0)
	_resolve_refs()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_pivot()

func _update_pivot() -> void:
	pivot_offset = size * 0.5

func is_minimap_enabled() -> bool:
	return _is_shown

func set_minimap_enabled(enabled: bool) -> void:
	if _is_shown == enabled:
		return
	_is_shown = enabled
	if _transition_tween != null:
		_transition_tween.kill()
	_transition_tween = create_tween()
	_transition_tween.set_parallel(true)
	_fx_strength = 1.0
	_scanline_flash = 1.0
	if enabled:
		visible = true
		_screen_power = 0.0
		transition_on()
		_transition_tween.tween_property(self, "_screen_power", 1.0, SHOW_DURATION).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	else:
		_transition_tween.tween_property(self, "_screen_power", 0.0, HIDE_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_transition_tween.tween_property(self, "_fx_strength", 0.0, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if not enabled:
		_transition_tween.chain().tween_callback(func() -> void:
			if not _is_shown:
				visible = false
		)

func transition_on() -> void:
	# Kept separate to make transition intent explicit and tunable.
	_scanline_flash = 1.0

func _resolve_refs() -> void:
	if _world == null or not is_instance_valid(_world):
		_world = get_tree().get_first_node_in_group("world")
		_boundary = null
	if _boundary == null or not is_instance_valid(_boundary):
		if _world != null:
			_boundary = _world.get_node_or_null("ArenaBoundary")
		else:
			_boundary = get_tree().get_first_node_in_group("arena_boundary")

func _draw() -> void:
	var panel_rect = Rect2(Vector2.ZERO, size)
	_draw_panel(panel_rect)
	if _screen_power <= 0.001:
		_draw_crt_shutdown(panel_rect, 0.0, 0.0, 1.0)
		return

	var map_margin = PANEL_PADDING
	var map_rect = panel_rect.grow_individual(-map_margin, -map_margin, -map_margin, -map_margin)
	if map_rect.size.x <= 2.0 or map_rect.size.y <= 2.0:
		return
	if _screen_power < CRT_LINE_PHASE:
		var line_t = clampf(_screen_power / CRT_LINE_PHASE, 0.0, 1.0)
		var dot_t = clampf(_screen_power / CRT_DOT_PHASE, 0.0, 1.0)
		_draw_crt_shutdown(map_rect, line_t, dot_t, 0.82 + (1.0 - line_t) * 0.18)
		return
	var expand_t = clampf((_screen_power - CRT_LINE_PHASE) / (1.0 - CRT_LINE_PHASE), 0.0, 1.0)
	var collapsed_h = maxf(1.2, map_rect.size.y * expand_t)
	var collapsed_y = map_rect.position.y + (map_rect.size.y - collapsed_h) * 0.5
	var screen_rect = Rect2(Vector2(map_rect.position.x, collapsed_y), Vector2(map_rect.size.x, collapsed_h))
	draw_rect(screen_rect, Color(0.01, 0.05, 0.07, 0.72), true)
	draw_rect(screen_rect, MAP_BG, true)
	_draw_toggle_fx(screen_rect)

	if _boundary == null or not is_instance_valid(_boundary) or not _boundary.has_method("get_inner_rect_global"):
		return

	var world_rect: Rect2 = _boundary.get_inner_rect_global()
	if world_rect.size.x <= 0.0 or world_rect.size.y <= 0.0:
		return

	var fit_scale = minf(screen_rect.size.x / world_rect.size.x, screen_rect.size.y / world_rect.size.y)
	var border_size = world_rect.size * fit_scale
	var border_pos = screen_rect.position + (screen_rect.size - border_size) * 0.5
	var border_rect = Rect2(border_pos, border_size)
	_draw_outside_dark(screen_rect, border_rect)
	draw_rect(border_rect, MAP_WORLD_BG, true)
	_draw_grid(border_rect)
	var pulse = 0.5 + 0.5 * sin(_border_pulse_t)
	var border_width = BORDER_THICKNESS + pulse * 1.2
	var border_color = Color(MAP_BORDER.r, MAP_BORDER.g, MAP_BORDER.b, 0.65 + pulse * 0.35)
	var glow_color = Color(MAP_BORDER.r, MAP_BORDER.g, MAP_BORDER.b, 0.16 + pulse * 0.2)
	draw_rect(border_rect.grow(2.0 + pulse * 2.0), glow_color, false, 1.0 + pulse)
	draw_rect(border_rect, border_color, false, border_width)

	var combatants = get_tree().get_nodes_in_group("combatants")
	for entity in combatants:
		var node = entity as Node2D
		if node == null or not is_instance_valid(node):
			continue
		if bool(node.get("is_dying")):
			continue
		var world_pos = node.global_position
		var local = (world_pos - world_rect.position)
		var map_pos = border_rect.position + (local * fit_scale)
		if map_pos.x < border_rect.position.x or map_pos.x > border_rect.end.x:
			continue
		if map_pos.y < border_rect.position.y or map_pos.y > border_rect.end.y:
			continue
		if node.is_in_group("player"):
			var player_half = PLAYER_MARKER_SIZE * 0.5
			var player_rect = Rect2(map_pos - Vector2(player_half, player_half), Vector2(PLAYER_MARKER_SIZE, PLAYER_MARKER_SIZE))
			draw_rect(player_rect, PLAYER_COLOR, true)
			draw_rect(player_rect.grow(1.5), Color(PLAYER_COLOR.r, PLAYER_COLOR.g, PLAYER_COLOR.b, 0.26), false, 1.0)
		else:
			var enemy_half = ENEMY_MARKER_SIZE * 0.5
			var enemy_rect = Rect2(map_pos - Vector2(enemy_half, enemy_half), Vector2(ENEMY_MARKER_SIZE, ENEMY_MARKER_SIZE))
			draw_rect(enemy_rect, ENEMY_COLOR, true)

func _draw_panel(rect: Rect2) -> void:
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
	var alpha_scale = clampf(0.2 + _screen_power * 0.8, 0.0, 1.0)
	panel_style.bg_color = Color(PANEL_BG.r, PANEL_BG.g, PANEL_BG.b, PANEL_BG.a * alpha_scale)
	panel_style.border_color = Color(PANEL_BORDER.r, PANEL_BORDER.g, PANEL_BORDER.b, PANEL_BORDER.a * alpha_scale)
	draw_style_box(panel_style, rect)
	draw_rect(rect.grow(-3.0), Color(PANEL_GLOW.r, PANEL_GLOW.g, PANEL_GLOW.b, PANEL_GLOW.a * alpha_scale), false, 1.0)
	if _fx_strength > 0.001:
		var pulse = 0.5 + 0.5 * sin(_border_pulse_t * 8.0)
		var glow_alpha = _fx_strength * (0.1 + pulse * 0.22)
		draw_rect(rect.grow(5.0 + pulse * 3.0), Color(0.45, 1.0, 1.0, glow_alpha), false, 1.3 + pulse * 0.8)

func _draw_grid(rect: Rect2) -> void:
	var columns = 8
	var rows = 6
	var v_step = rect.size.x / float(columns)
	var h_step = rect.size.y / float(rows)
	for i in range(1, columns):
		var x = rect.position.x + v_step * i
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), MAP_GRID, 1.0)
	for j in range(1, rows):
		var y = rect.position.y + h_step * j
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), MAP_GRID, 1.0)

func _draw_toggle_fx(rect: Rect2) -> void:
	if _fx_strength <= 0.001:
		return
	var pulse = 0.5 + 0.5 * sin(_border_pulse_t * 3.2)
	var alpha = clampf(_fx_strength * (0.28 + pulse * 0.22), 0.0, 0.5)
	var scan_y = rect.position.y + rect.size.y * (0.12 + 0.76 * (1.0 - _fx_strength))
	var scan_color = Color(0.45, 1.0, 1.0, alpha)
	draw_line(Vector2(rect.position.x, scan_y), Vector2(rect.end.x, scan_y), scan_color, 2.0)
	draw_rect(rect.grow(-2.0), Color(0.3, 1.0, 1.0, alpha * 0.72), false, 1.0)

func _draw_outside_dark(full_rect: Rect2, inner_rect: Rect2) -> void:
	var c = Color(OUTSIDE_DARK.r, OUTSIDE_DARK.g, OUTSIDE_DARK.b, OUTSIDE_DARK.a * clampf(_screen_power, 0.35, 1.0))
	if inner_rect.position.y > full_rect.position.y:
		draw_rect(Rect2(full_rect.position.x, full_rect.position.y, full_rect.size.x, inner_rect.position.y - full_rect.position.y), c, true)
	if inner_rect.end.y < full_rect.end.y:
		draw_rect(Rect2(full_rect.position.x, inner_rect.end.y, full_rect.size.x, full_rect.end.y - inner_rect.end.y), c, true)
	if inner_rect.position.x > full_rect.position.x:
		draw_rect(Rect2(full_rect.position.x, inner_rect.position.y, inner_rect.position.x - full_rect.position.x, inner_rect.size.y), c, true)
	if inner_rect.end.x < full_rect.end.x:
		draw_rect(Rect2(inner_rect.end.x, inner_rect.position.y, full_rect.end.x - inner_rect.end.x, inner_rect.size.y), c, true)

func _draw_crt_shutdown(rect: Rect2, line_t: float, dot_t: float, strength: float) -> void:
	var glitch_x = sin(_border_pulse_t * 27.0) * (1.0 - line_t) * 1.2
	var center = rect.position + rect.size * 0.5 + Vector2(glitch_x, 0.0)
	var line_half = rect.size.x * 0.5 * line_t
	var y = rect.position.y + rect.size.y * 0.5
	var beam_alpha = clampf(0.28 + _scanline_flash * 0.48, 0.0, 0.9) * strength
	var beam = Color(0.58, 1.0, 1.0, beam_alpha)
	if line_t > 0.001:
		draw_line(Vector2(center.x - line_half, y), Vector2(center.x + line_half, y), beam, 2.2)
		draw_rect(Rect2(center.x - line_half, y - 1.0, line_half * 2.0, 2.0), Color(0.35, 1.0, 1.0, beam.a * 0.35), true)
	var dot_strength = sin(dot_t * PI)
	if dot_strength > 0.001:
		var dot_pulse = 0.5 + 0.5 * sin(_border_pulse_t * 19.0)
		var dot_radius = 0.8 + dot_strength * (0.9 + dot_pulse * 1.1)
		var dot_alpha = dot_strength * (0.28 + dot_pulse * 0.32) * strength
		draw_circle(center, dot_radius + 2.4, Color(0.38, 1.0, 1.0, dot_alpha * 0.32))
		draw_circle(center, dot_radius, Color(0.62, 1.0, 1.0, dot_alpha))

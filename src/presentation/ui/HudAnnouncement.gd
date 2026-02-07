extends PanelContainer

const POP_IN_SCALE: Vector2 = Vector2(0.88, 0.88)
const REST_SCALE: Vector2 = Vector2.ONE
const HIDE_SCALE: Vector2 = Vector2(0.94, 0.94)
const APPEAR_GLITCH_SECONDS: float = 0.55
const TEXT_INSET_TOP: float = 1.0
const TEXT_INSET_BOTTOM: float = 6.0

@onready var message_label: Label = $Margin/Message
@onready var margin_container: MarginContainer = $Margin

var _anim_t: float = 0.0
var _is_active: bool = false
var _hide_tween: Tween = null
var _show_tween: Tween = null
var _appear_fx_t: float = APPEAR_GLITCH_SECONDS
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	visible = false
	scale = POP_IN_SCALE
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	_rng.randomize()
	if message_label != null:
		# Draw text manually for glitch/vector styling while keeping node for theme + layout.
		message_label.visible = false

func _process(delta: float) -> void:
	if not visible:
		return
	_anim_t += delta
	_appear_fx_t += delta
	queue_redraw()

func show_announcement(text: String) -> void:
	_is_active = true
	_appear_fx_t = 0.0
	if message_label != null:
		message_label.text = text
	visible = true
	if _hide_tween != null:
		_hide_tween.kill()
	if _show_tween != null:
		_show_tween.kill()
	scale = POP_IN_SCALE
	modulate = Color(1.0, 1.0, 1.0, 0.0)
	_show_tween = create_tween()
	_show_tween.tween_property(self, "modulate:a", 1.0, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_show_tween.parallel().tween_property(self, "scale", Vector2(1.03, 1.03), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_show_tween.tween_property(self, "scale", REST_SCALE, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func hide_announcement() -> void:
	_is_active = false
	if not visible:
		return
	if _show_tween != null:
		_show_tween.kill()
	if _hide_tween != null:
		_hide_tween.kill()
	_hide_tween = create_tween()
	_hide_tween.tween_property(self, "scale", HIDE_SCALE, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_hide_tween.parallel().tween_property(self, "modulate:a", 0.0, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_hide_tween.tween_callback(func() -> void:
		if not _is_active:
			visible = false
	)

func _draw() -> void:
	if not visible:
		return
	var rect := Rect2(Vector2.ZERO, size)
	var pulse = 0.5 + 0.5 * sin(_anim_t * 5.2)
	var neon = Color(0.08, 0.95, 1.0, 0.21 + pulse * 0.10)
	var magenta = Color(1.0, 0.28, 0.86, 0.07 + pulse * 0.06)
	draw_rect(rect.grow(1.4), neon, false, 1.2)
	draw_rect(rect.grow(2.8), neon * Color(1, 1, 1, 0.4), false, 0.9)
	draw_rect(rect.grow(4.0), magenta, false, 0.7)
	var sweep = fmod(_anim_t * 92.0, rect.size.x + 40.0) - 20.0
	var from = Vector2(sweep, 2.0)
	var to = Vector2(sweep - 16.0, rect.size.y - 2.0)
	draw_line(from, to, Color(0.95, 0.55, 1.0, 0.26), 2.0)
	_draw_glitch_text(rect)

func _draw_glitch_text(rect: Rect2) -> void:
	if message_label == null:
		return
	var text := message_label.text
	if text.is_empty():
		return
	var font := message_label.get_theme_font("font")
	if font == null:
		font = get_theme_default_font()
	var font_size := message_label.get_theme_font_size("font_size")
	if font_size <= 0:
		font_size = get_theme_default_font_size()
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var content_rect := rect
	if margin_container != null:
		content_rect = Rect2(margin_container.position, margin_container.size)
	content_rect.position.y += TEXT_INSET_TOP
	content_rect.size.y = maxf(1.0, content_rect.size.y - (TEXT_INSET_TOP + TEXT_INSET_BOTTOM))
	var base := Vector2(
		content_rect.position.x + (content_rect.size.x - text_size.x) * 0.5,
		content_rect.position.y + (content_rect.size.y + text_size.y) * 0.5 - 3.0
	)
	var appear: float = clamp(1.0 - (_appear_fx_t / APPEAR_GLITCH_SECONDS), 0.0, 1.0)
	var flicker: float = 0.8 + 0.2 * (0.5 + 0.5 * sin(_anim_t * 24.0))
	var jitter: float = 6.0 * appear
	var drift: float = sin(_anim_t * 42.0) * jitter * 0.35
	var split: float = 1.0 + 5.0 * appear

	draw_string(font, base + Vector2(-2.4, 0.4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.15, 0.95, 1.0, 0.12 + appear * 0.10))
	draw_string(font, base + Vector2(2.4, -0.4), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.92, 0.4, 1.0, 0.08 + appear * 0.08))
	draw_string(font, base + Vector2(-split + drift, -0.6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.28, 0.95, 1.0, 0.42 + appear * 0.22))
	draw_string(font, base + Vector2(split + drift * 0.5, 0.6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.36, 0.9, 0.28 + appear * 0.22))
	draw_string(font, base + Vector2(drift * 0.35, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.88, 0.98, 1.0, 0.86 * flicker))

	if appear <= 0.0:
		return
	var glitch_lines: int = 1 + int(round(appear * 2.0))
	for i in range(glitch_lines):
		var line_y := base.y - text_size.y + _rng.randf_range(0.0, text_size.y + 1.0)
		var line_x := base.x + _rng.randf_range(-5.0, 5.0)
		var line_w := text_size.x + _rng.randf_range(-8.0, 10.0)
		var alpha: float = 0.08 + 0.20 * appear
		var line_color := Color(0.2, 0.95, 1.0, alpha)
		if i % 2 == 1:
			line_color = Color(1.0, 0.4, 0.92, alpha * 0.8)
		draw_rect(Rect2(line_x, line_y, maxf(2.0, line_w), 1.0), line_color, true)

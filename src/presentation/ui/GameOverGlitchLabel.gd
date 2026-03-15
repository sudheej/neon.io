extends Label

@export var glow_color: Color = Color(0.16, 0.95, 1.0, 0.28)
@export var split_a_color: Color = Color(0.3, 0.95, 1.0, 0.46)
@export var split_b_color: Color = Color(1.0, 0.36, 0.92, 0.32)
@export var sweep_color: Color = Color(0.95, 0.55, 1.0, 0.22)

var _t: float = 0.0

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var pulse := 0.5 + 0.5 * sin(_t * 5.3)
	var border_col := Color(glow_color.r, glow_color.g, glow_color.b, 0.18 + pulse * 0.1)
	draw_rect(rect.grow(1.6), border_col, false, 1.2)
	draw_rect(rect.grow(3.1), Color(border_col.r, border_col.g, border_col.b, border_col.a * 0.45), false, 0.9)

	var sweep_x := fmod(_t * 122.0, rect.size.x + 64.0) - 32.0
	draw_line(Vector2(sweep_x, 2.0), Vector2(sweep_x - 26.0, rect.size.y - 2.0), sweep_color, 2.0)

	var font := get_theme_font("font")
	if font == null:
		font = get_theme_default_font()
	if font == null:
		return
	var font_size := get_theme_font_size("font_size")
	if font_size <= 0:
		font_size = get_theme_default_font_size()
	if font_size <= 0:
		return
	var txt := text
	if txt.is_empty():
		return
	var text_size := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var base := Vector2((rect.size.x - text_size.x) * 0.5, (rect.size.y + text_size.y) * 0.5 - 3.0)
	var split := 1.2 + 1.2 * (0.5 + 0.5 * sin(_t * 19.0))
	var drift := sin(_t * 33.0) * 1.1
	draw_string(font, base + Vector2(-split + drift, -0.55), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, split_a_color)
	draw_string(font, base + Vector2(split + drift * 0.4, 0.55), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, split_b_color)

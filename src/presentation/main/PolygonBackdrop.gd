extends Node2D

@export var polygon_count: int = 26
@export var drift_speed: float = 8.0
@export var pulse_speed: float = 0.22

var _time_s: float = 0.0
var _view_size: Vector2 = Vector2.ZERO
var _shards: Array[Dictionary] = []

func _ready() -> void:
	_view_size = get_viewport_rect().size
	_rebuild_shards()
	set_process(true)

func _process(delta: float) -> void:
	var size_now := get_viewport_rect().size
	if size_now != _view_size:
		_view_size = size_now
		_rebuild_shards()
	_time_s += delta
	queue_redraw()

func _draw() -> void:
	# Low-contrast industrial wash under the UI.
	draw_rect(Rect2(Vector2.ZERO, _view_size), Color(0.015, 0.022, 0.035, 1.0), true)
	draw_rect(Rect2(Vector2(0, 0), Vector2(_view_size.x, _view_size.y * 0.46)), Color(0.12, 0.05, 0.06, 0.08), true)

	for shard in _shards:
		var base_pos: Vector2 = shard.base_pos
		var drift: Vector2 = shard.drift
		var wobble: Vector2 = shard.wobble
		var phase: float = shard.phase
		var ang: float = shard.angle
		var points: PackedVector2Array = shard.points
		var col: Color = shard.color
		var edge_col: Color = shard.edge_color

		var p := base_pos
		p += drift * _time_s * drift_speed
		p += Vector2(
			sin((_time_s * pulse_speed) + phase) * wobble.x,
			cos((_time_s * pulse_speed * 0.73) + phase) * wobble.y
		)
		p.x = wrapf(p.x, -220.0, _view_size.x + 220.0)
		p.y = wrapf(p.y, -220.0, _view_size.y + 220.0)

		var rot := ang + sin((_time_s * pulse_speed * 0.5) + phase) * 0.04
		var xf := Transform2D(rot, p)
		var poly := PackedVector2Array()
		for q in points:
			poly.append(xf * q)

		var alpha := col.a * (0.86 + 0.14 * sin((_time_s * pulse_speed * 1.7) + phase))
		draw_colored_polygon(poly, Color(col.r, col.g, col.b, alpha))
		poly.append(poly[0])
		draw_polyline(poly, edge_col, 1.4, true)

	_draw_diagonal_bands()

func _draw_diagonal_bands() -> void:
	var band_a := Color(0.83, 0.14, 0.2, 0.08)
	var band_b := Color(0.16, 0.75, 0.86, 0.06)
	var shift := fposmod(_time_s * 14.0, _view_size.x + 500.0) - 250.0
	var w := _view_size.x
	var h := _view_size.y
	var p1 := PackedVector2Array([
		Vector2(-220 + shift, h * 0.75),
		Vector2(-50 + shift, h * 0.75),
		Vector2(380 + shift, h * 0.18),
		Vector2(210 + shift, h * 0.18)
	])
	var p2 := PackedVector2Array([
		Vector2(w - 90 - shift * 0.55, h * 0.88),
		Vector2(w + 100 - shift * 0.55, h * 0.88),
		Vector2(w + 340 - shift * 0.55, h * 0.28),
		Vector2(w + 150 - shift * 0.55, h * 0.28)
	])
	draw_colored_polygon(p1, band_a)
	draw_colored_polygon(p2, band_b)

func _rebuild_shards() -> void:
	_shards.clear()
	if _view_size == Vector2.ZERO:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x6E656F6E0A

	var palette: Array[Color] = [
		Color(0.78, 0.12, 0.18, 0.14),
		Color(0.67, 0.09, 0.12, 0.12),
		Color(0.2, 0.76, 0.88, 0.12),
		Color(0.12, 0.45, 0.64, 0.11),
		Color(0.52, 0.18, 0.22, 0.13)
	]

	for i in range(polygon_count):
		var radius := rng.randf_range(34.0, 118.0)
		var sides := rng.randi_range(4, 7)
		var points := PackedVector2Array()
		for s in range(sides):
			var t := (float(s) / float(sides)) * TAU
			var jitter := rng.randf_range(-0.28, 0.28)
			var r := radius * rng.randf_range(0.62, 1.15)
			points.append(Vector2(cos(t + jitter), sin(t + jitter)) * r)
		var c: Color = palette[rng.randi_range(0, palette.size() - 1)]
		_shards.append({
			"base_pos": Vector2(
				rng.randf_range(-160.0, _view_size.x + 160.0),
				rng.randf_range(-120.0, _view_size.y + 120.0)
			),
			"drift": Vector2(rng.randf_range(-0.06, 0.06), rng.randf_range(-0.03, 0.03)),
			"wobble": Vector2(rng.randf_range(8.0, 26.0), rng.randf_range(5.0, 18.0)),
			"phase": rng.randf_range(0.0, TAU),
			"angle": rng.randf_range(-0.9, 0.9),
			"points": points,
			"color": c,
			"edge_color": Color(c.r + 0.15, c.g + 0.15, c.b + 0.15, c.a * 0.9)
		})

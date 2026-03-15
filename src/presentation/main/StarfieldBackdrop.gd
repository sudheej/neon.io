extends Node2D

@onready var core_field: GPUParticles2D = $CoreField
@onready var glow_field: GPUParticles2D = $GlowField
@onready var heavy_field: GPUParticles2D = $HeavyField
@onready var left_light: PointLight2D = $LeftLight
@onready var right_light: PointLight2D = $RightLight

var _time_s: float = 0.0
var _view_size: Vector2 = Vector2.ZERO
var _base_scale: Vector2 = Vector2.ONE

func _ready() -> void:
	_configure_emitters()
	_configure_blend_modes()
	_configure_lights()
	_resize_for_viewport()
	_base_scale = scale
	set_process(true)

func _process(delta: float) -> void:
	_time_s += delta
	var size_now := get_viewport_rect().size
	if size_now != _view_size:
		_resize_for_viewport()
	_update_lights()
	_update_background_dolly()

func _configure_emitters() -> void:
	core_field.texture = _make_square_outline_texture(56, 0.84, 1.6)
	core_field.amount = 34
	core_field.lifetime = 11.0
	core_field.preprocess = 11.0
	core_field.explosiveness = 0.0
	core_field.randomness = 0.9
	core_field.local_coords = false
	core_field.emitting = true
	core_field.fixed_fps = 60
	core_field.trail_enabled = false

	var core_mat := ParticleProcessMaterial.new()
	core_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	core_mat.direction = Vector3.ZERO
	core_mat.spread = 180.0
	core_mat.gravity = Vector3.ZERO
	core_mat.initial_velocity_min = 0.22
	core_mat.initial_velocity_max = 1.45
	core_mat.radial_accel_min = 2.8
	core_mat.radial_accel_max = 8.4
	core_mat.scale_min = 0.35
	core_mat.scale_max = 0.58
	core_mat.angular_velocity_min = 0.0
	core_mat.angular_velocity_max = 0.0
	core_mat.hue_variation_min = -0.01
	core_mat.hue_variation_max = 0.01
	core_mat.color = Color(0.52, 0.78, 1.0, 0.95)
	core_mat.color_ramp = _make_color_ramp([
		Color(0.52, 0.78, 1.0, 0.0),
		Color(0.62, 0.84, 1.0, 0.74),
		Color(0.72, 0.9, 1.0, 0.68),
		Color(0.52, 0.78, 1.0, 0.0)
	], [0.0, 0.2, 0.85, 1.0])
	core_field.process_material = core_mat

	glow_field.texture = _make_square_outline_texture(76, 0.58, 3.8)
	glow_field.amount = 32
	glow_field.lifetime = 13.0
	glow_field.preprocess = 13.0
	glow_field.explosiveness = 0.0
	glow_field.randomness = 0.92
	glow_field.local_coords = false
	glow_field.emitting = true
	glow_field.fixed_fps = 60
	glow_field.trail_enabled = false

	var glow_mat := ParticleProcessMaterial.new()
	glow_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	glow_mat.direction = Vector3.ZERO
	glow_mat.spread = 180.0
	glow_mat.gravity = Vector3.ZERO
	glow_mat.initial_velocity_min = 0.18
	glow_mat.initial_velocity_max = 1.12
	glow_mat.radial_accel_min = 2.2
	glow_mat.radial_accel_max = 6.8
	glow_mat.scale_min = 0.42
	glow_mat.scale_max = 0.82
	glow_mat.angular_velocity_min = -0.85
	glow_mat.angular_velocity_max = 0.85
	glow_mat.hue_variation_min = -0.01
	glow_mat.hue_variation_max = 0.01
	glow_mat.color = Color(0.42, 0.68, 0.98, 0.42)
	glow_mat.color_ramp = _make_color_ramp([
		Color(0.42, 0.68, 0.98, 0.0),
		Color(0.5, 0.76, 1.0, 0.34),
		Color(0.62, 0.84, 1.0, 0.3),
		Color(0.42, 0.68, 0.98, 0.0)
	], [0.0, 0.22, 0.86, 1.0])
	glow_field.process_material = glow_mat

	heavy_field.texture = _make_square_outline_texture(66, 0.86, 2.1)
	heavy_field.amount = 12
	heavy_field.lifetime = 15.0
	heavy_field.preprocess = 15.0
	heavy_field.explosiveness = 0.0
	heavy_field.randomness = 0.95
	heavy_field.local_coords = false
	heavy_field.emitting = true
	heavy_field.fixed_fps = 60
	heavy_field.trail_enabled = false

	var heavy_mat := ParticleProcessMaterial.new()
	heavy_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	heavy_mat.direction = Vector3.ZERO
	heavy_mat.spread = 180.0
	heavy_mat.gravity = Vector3.ZERO
	heavy_mat.initial_velocity_min = 0.12
	heavy_mat.initial_velocity_max = 0.92
	heavy_mat.radial_accel_min = 2.6
	heavy_mat.radial_accel_max = 6.6
	heavy_mat.scale_min = 0.62
	heavy_mat.scale_max = 1.1
	heavy_mat.angular_velocity_min = -0.55
	heavy_mat.angular_velocity_max = 0.55
	heavy_mat.hue_variation_min = -0.01
	heavy_mat.hue_variation_max = 0.01
	heavy_mat.color = Color(0.72, 0.88, 1.0, 0.58)
	heavy_mat.color_ramp = _make_color_ramp([
		Color(0.72, 0.88, 1.0, 0.0),
		Color(0.8, 0.92, 1.0, 0.6),
		Color(0.76, 0.9, 1.0, 0.54),
		Color(0.72, 0.88, 1.0, 0.0)
	], [0.0, 0.2, 0.86, 1.0])
	heavy_field.process_material = heavy_mat

func _configure_blend_modes() -> void:
	var core_blend := CanvasItemMaterial.new()
	core_blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	core_field.material = core_blend
	var glow_blend := CanvasItemMaterial.new()
	glow_blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow_field.material = glow_blend
	var heavy_blend := CanvasItemMaterial.new()
	heavy_blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	heavy_field.material = heavy_blend

func _configure_lights() -> void:
	left_light.texture = _make_light_texture()
	left_light.color = Color(0.15, 0.5, 1.0, 0.34)
	left_light.energy = 0.24
	left_light.blend_mode = Light2D.BLEND_MODE_ADD
	left_light.texture_scale = 2.9

	right_light.texture = _make_light_texture()
	right_light.color = Color(0.2, 0.58, 1.0, 0.32)
	right_light.energy = 0.22
	right_light.blend_mode = Light2D.BLEND_MODE_ADD
	right_light.texture_scale = 3.1

func _resize_for_viewport() -> void:
	_view_size = get_viewport_rect().size
	position = Vector2.ZERO
	var center := _view_size * 0.5
	core_field.position = center
	glow_field.position = center
	heavy_field.position = center

	var core_mat := core_field.process_material as ParticleProcessMaterial
	if core_mat != null:
		core_mat.emission_box_extents = Vector3(_view_size.x * 0.56, _view_size.y * 0.56, 1.0)
	var glow_mat := glow_field.process_material as ParticleProcessMaterial
	if glow_mat != null:
		glow_mat.emission_box_extents = Vector3(_view_size.x * 0.56, _view_size.y * 0.56, 1.0)
	var heavy_mat := heavy_field.process_material as ParticleProcessMaterial
	if heavy_mat != null:
		heavy_mat.emission_box_extents = Vector3(_view_size.x * 0.56, _view_size.y * 0.56, 1.0)

	left_light.position = Vector2(_view_size.x * 0.2, _view_size.y * 0.3)
	right_light.position = Vector2(_view_size.x * 0.82, _view_size.y * 0.25)

func _update_lights() -> void:
	left_light.energy = 0.2 + 0.04 * sin(_time_s * 0.14)
	right_light.energy = 0.18 + 0.04 * cos(_time_s * 0.15 + 0.9)
	left_light.position.y = (_view_size.y * 0.3) + sin(_time_s * 0.09) * 6.0
	right_light.position.y = (_view_size.y * 0.25) + cos(_time_s * 0.08 + 0.6) * 7.0

func _update_background_dolly() -> void:
	# Very slow forward movement for a calmer, cooler backdrop.
	var push: float = min(_time_s * 0.0024, 0.26)
	var zoom: float = 1.0 + push + (0.01 * sin(_time_s * 0.12))
	scale = _base_scale * zoom
	position = (_view_size * (1.0 - zoom)) * 0.5 + Vector2(
		sin(_time_s * 0.05) * 5.0,
		cos(_time_s * 0.045) * 4.0
	)

func _make_color_ramp(colors: Array[Color], offsets: Array[float]) -> GradientTexture1D:
	var grad := Gradient.new()
	grad.colors = PackedColorArray(colors)
	grad.offsets = PackedFloat32Array(offsets)
	var tex := GradientTexture1D.new()
	tex.gradient = grad
	return tex

func _make_square_outline_texture(size_px: int, border_thickness: float, glow_width: float) -> ImageTexture:
	var img := Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center: float = (float(size_px) - 1.0) * 0.5
	var half: float = float(size_px) * 0.36
	var half_thickness: float = border_thickness * 0.5
	for y in range(size_px):
		for x in range(size_px):
			var dx: float = abs(float(x) - center)
			var dy: float = abs(float(y) - center)
			var maxd: float = max(dx, dy)
			var edge_dist: float = abs(maxd - half)
			if edge_dist > half_thickness + glow_width:
				continue
			var alpha: float = 1.0
			if edge_dist > half_thickness:
				alpha = 1.0 - ((edge_dist - half_thickness) / glow_width)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

func _make_light_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.34),
		Color(1.0, 1.0, 1.0, 0.0)
	])
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.width = 256
	tex.height = 256
	tex.gradient = grad
	return tex

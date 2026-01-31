extends Node2D
class_name LaserShot

const LIFE: float = 0.12
const LaserShader = preload("res://scripts/weapons/projectiles/LaserGlow.gdshader")
const LASER_SFX_SOURCES := [
	"res://assets/audio/laser/laser_theremin_01.ogg",
	"res://assets/audio/laser/laser_theremin_02.ogg",
	"res://assets/audio/laser/laser_theremin_03.ogg",
	"res://assets/audio/laser/laser_theremin_04.ogg",
	"res://assets/audio/laser/laser_theremin_05.ogg",
	"res://assets/audio/laser/laser_theremin_06.ogg",
	"res://assets/audio/laser/laser_theremin_07.ogg",
	"res://assets/audio/laser/laser_theremin_08.ogg"
]

var start_pos: Vector2
var end_pos: Vector2
var time_left: float = LIFE
var origin_node: Node2D = null
var target_node: Node2D = null
var origin_offset: Vector2 = Vector2.ZERO
var rng := RandomNumberGenerator.new()
static var sfx_cache: Array[AudioStream] = []
static var sfx_checked := false
var laser_sfx: Array[AudioStream] = []

func _ready() -> void:
	rng.randomize()
	var mat = ShaderMaterial.new()
	mat.shader = LaserShader
	material = mat
	if not sfx_checked:
		sfx_checked = true
		for source_path in LASER_SFX_SOURCES:
			var stream := _load_imported_audio(source_path)
			if stream != null:
				sfx_cache.append(stream)
	laser_sfx = sfx_cache
	_play_laser_sfx()
	add_to_group("projectiles")

func setup(
	p_start: Vector2,
	p_end: Vector2,
	p_origin_node: Node2D = null,
	p_origin_offset: Vector2 = Vector2.ZERO,
	p_target_node: Node2D = null
) -> void:
	start_pos = p_start
	end_pos = p_end
	origin_node = p_origin_node
	origin_offset = p_origin_offset
	target_node = p_target_node
	global_position = start_pos
	queue_redraw()

func _process(delta: float) -> void:
	time_left -= delta
	if time_left <= 0.0:
		queue_free()
	else:
		if origin_node != null and is_instance_valid(origin_node):
			start_pos = origin_node.global_position + origin_offset
			global_position = start_pos
		if target_node != null and is_instance_valid(target_node):
			end_pos = target_node.global_position
		queue_redraw()

func _draw() -> void:
	if time_left <= 0.0:
		return
	var t := time_left / LIFE
	var color := Color(0.4, 1.0, 1.0, 0.6 * t)
	var core := Color(0.8, 1.0, 1.0, 0.9 * t)
	draw_line(Vector2.ZERO, to_local(end_pos), color, 3.0)
	draw_line(Vector2.ZERO, to_local(end_pos), core, 1.0)

func _play_laser_sfx() -> void:
	if laser_sfx.is_empty():
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = laser_sfx[rng.randi_range(0, laser_sfx.size() - 1)]
	player.volume_db = -6.0
	player.pitch_scale = rng.randf_range(0.95, 1.05)
	player.max_distance = 650.0
	player.attenuation = 1.0
	player.global_position = global_position
	var world := get_tree().get_first_node_in_group("world")
	if world != null:
		world.add_child(player)
	else:
		get_tree().current_scene.add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

func _load_imported_audio(source_path: String) -> AudioStream:
	var import_path := source_path + ".import"
	var cfg := ConfigFile.new()
	if cfg.load(import_path) != OK:
		return null
	var remap_path := cfg.get_value("remap", "path", "") as String
	if remap_path.is_empty():
		return null
	return ResourceLoader.load(remap_path) as AudioStream

extends RefCounted

enum WeaponType { LASER, STUN, HOMING, SPREAD }

var grid_pos: Vector2i
var dir: Vector2i
var weapon_type: WeaponType = WeaponType.LASER
var level: int = 1
var range: float = 180.0

func _init(p_grid_pos: Vector2i, p_dir: Vector2i, p_weapon_type: WeaponType) -> void:
	grid_pos = p_grid_pos
	dir = p_dir
	weapon_type = p_weapon_type

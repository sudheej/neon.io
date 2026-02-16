extends Node2D

const WeaponSlot = preload("res://src/domain/weapons/WeaponSlot.gd")
const PlayerShapeScript = preload("res://src/presentation/player/PlayerShape.gd")

enum BoostType {
	XP,
	AMMO,
	HEALTH
}

const MIN_RADIUS: float = 4.0
const MAX_RADIUS: float = 10.0
const PICKUP_PADDING: float = 2.0
const ORB_LIFETIME: float = 20.0
const INVALIDATE_DURATION: float = 0.18

var boost_type: int = BoostType.XP
var weapon_type: int = WeaponSlot.WeaponType.LASER
var amount: float = 0.0
var initial_amount: float = 0.0
var orb_id: String = ""

var _life_timer: float = 0.0
var _pulse_phase: float = 0.0
var _base_color: Color = Color(0.95, 0.88, 0.3, 1.0)
var _invalidating: bool = false
var _invalidate_timer: float = 0.0

func configure(type_id: int, value: float, weapon_id: int = WeaponSlot.WeaponType.LASER) -> void:
	boost_type = type_id
	weapon_type = weapon_id
	amount = maxf(value, 0.0)
	initial_amount = maxf(amount, 0.001)
	_base_color = _resolve_color()
	queue_redraw()

func _ready() -> void:
	add_to_group("boost_orbs")

func _process(delta: float) -> void:
	if _invalidating:
		_invalidate_timer = maxf(_invalidate_timer - delta, 0.0)
		var t = 1.0 - (_invalidate_timer / maxf(INVALIDATE_DURATION, 0.001))
		scale = Vector2(1.0 + 0.06 * t, maxf(1.0 - t * 1.35, 0.03))
		modulate.a = 1.0 - t
		if _invalidate_timer <= 0.0:
			queue_free()
			return
		queue_redraw()
		return
	_life_timer += delta
	_pulse_phase += delta * _pulse_speed()
	if _life_timer >= ORB_LIFETIME or amount <= 0.0:
		queue_free()
		return
	queue_redraw()

func get_pickup_radius() -> float:
	return _current_radius() + PICKUP_PADDING

func get_boost_type() -> int:
	return boost_type

func get_weapon_type() -> int:
	return weapon_type

func get_amount() -> float:
	return amount

func is_pickable() -> bool:
	return (not _invalidating) and amount > 0.0

func is_entity_in_pickup_range(entity: Node2D) -> bool:
	if entity == null or not is_instance_valid(entity):
		return false
	var pickup_radius = get_pickup_radius()
	if entity.has_node("PlayerShape"):
		var shape = entity.get_node("PlayerShape")
		var cells = shape.get("cells")
		if cells is Dictionary and shape.has_method("grid_to_local"):
			var half_cell = PlayerShapeScript.CELL_SIZE * 0.5
			var orb_pos = global_position
			var pickup_radius_sq = pickup_radius * pickup_radius
			for grid_pos in (cells as Dictionary).keys():
				var center = entity.global_position + shape.grid_to_local(grid_pos)
				var dx = absf(orb_pos.x - center.x)
				var dy = absf(orb_pos.y - center.y)
				var clamped_x = maxf(dx - half_cell, 0.0)
				var clamped_y = maxf(dy - half_cell, 0.0)
				if clamped_x * clamped_x + clamped_y * clamped_y <= pickup_radius_sq:
					return true
	return entity.global_position.distance_to(global_position) <= pickup_radius

func try_consume(entity: Node, invalidate_on_failed: bool = false) -> bool:
	if entity == null or not is_instance_valid(entity):
		return false
	if _invalidating:
		return false
	var consumed: float = 0.0
	match boost_type:
		BoostType.XP:
			consumed = _consume_xp(entity)
		BoostType.AMMO:
			consumed = _consume_ammo(entity)
		BoostType.HEALTH:
			consumed = _consume_health(entity)
	if consumed <= 0.0:
		if invalidate_on_failed:
			_start_invalidate_fx()
			return true
		return false
	amount = maxf(amount - consumed, 0.0)
	if amount <= 0.0:
		_start_invalidate_fx()
	else:
		queue_redraw()
	return true

func _consume_xp(entity: Node) -> float:
	if not entity.has_method("add_xp"):
		return 0.0
	entity.add_xp(amount)
	return amount

func _consume_health(entity: Node) -> float:
	var health_val = entity.get("health")
	var max_health_val = entity.get("max_health")
	if health_val == null or max_health_val == null:
		return 0.0
	var hp = float(health_val)
	var max_hp = float(max_health_val)
	var missing = maxf(max_hp - hp, 0.0)
	if missing <= 0.0:
		return 0.0
	var consumed = minf(amount, missing)
	entity.set("health", hp + consumed)
	return consumed

func _consume_ammo(entity: Node) -> float:
	if not entity.has_node("WeaponSystem"):
		return 0.0
	var system = entity.get_node("WeaponSystem")
	if system == null or not system.has_method("add_weapon_ammo"):
		return 0.0
	var request = int(floor(amount))
	if request <= 0:
		return 0.0
	var gained = int(system.add_weapon_ammo(weapon_type, request))
	return float(gained)

func _draw() -> void:
	if amount <= 0.0 and not _invalidating:
		return
	var radius = _current_radius()
	var pulse = 0.5 + 0.5 * sin(_pulse_phase)
	var glow_alpha = 0.12 + 0.2 * pulse * _value_norm()
	var shell_alpha = 0.35 + 0.25 * pulse
	var core_alpha = 0.72 + 0.24 * pulse
	draw_circle(Vector2.ZERO, radius * 2.0, Color(_base_color.r, _base_color.g, _base_color.b, glow_alpha))
	draw_circle(Vector2.ZERO, radius * 1.3, Color(_base_color.r, _base_color.g, _base_color.b, shell_alpha))
	draw_circle(Vector2.ZERO, radius * 0.55, Color(1.0, 1.0, 1.0, core_alpha))
	draw_arc(Vector2.ZERO, radius * 1.1, 0.0, TAU, 44, Color(_base_color.r, _base_color.g, _base_color.b, 0.45 + 0.2 * pulse), 1.3)
	_draw_symbol(radius)

func _draw_symbol(radius: float) -> void:
	var symbol := ""
	match boost_type:
		BoostType.XP:
			symbol = "$"
		BoostType.HEALTH:
			symbol = "+"
		_:
			return
	var font = ThemeDB.fallback_font
	var size = int(clampf(radius * 1.3, 9.0, 14.0))
	var text_size = font.get_string_size(symbol, HORIZONTAL_ALIGNMENT_CENTER, -1, size)
	var pos = Vector2(-text_size.x * 0.5, text_size.y * 0.34)
	draw_string(font, pos, symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.06, 0.08, 0.1, 0.95))

func _resolve_color() -> Color:
	if boost_type == BoostType.XP:
		return Color(0.98, 0.88, 0.28, 1.0)
	if boost_type == BoostType.HEALTH:
		return Color(1.0, 0.32, 0.34, 1.0)
	match weapon_type:
		WeaponSlot.WeaponType.LASER:
			return Color(0.2, 0.95, 1.0, 1.0)
		WeaponSlot.WeaponType.STUN:
			return Color(0.2, 1.0, 0.4, 1.0)
		WeaponSlot.WeaponType.HOMING:
			return Color(1.0, 0.6, 0.15, 1.0)
		WeaponSlot.WeaponType.SPREAD:
			return Color(0.75, 0.4, 1.0, 1.0)
		_:
			return Color(0.9, 0.9, 0.95, 1.0)

func _pulse_speed() -> float:
	return lerpf(2.4, 7.2, _value_norm())

func _current_radius() -> float:
	return lerpf(MIN_RADIUS, MAX_RADIUS, _value_norm())

func _value_norm() -> float:
	var max_val = _display_cap()
	if max_val <= 0.0:
		return 0.0
	return clampf(amount / max_val, 0.0, 1.0)

func _display_cap() -> float:
	match boost_type:
		BoostType.XP:
			return 34.0
		BoostType.AMMO:
			return 18.0
		BoostType.HEALTH:
			return 20.0
		_:
			return 20.0

func _start_invalidate_fx() -> void:
	if _invalidating:
		return
	_invalidating = true
	_invalidate_timer = INVALIDATE_DURATION

extends Node2D

const SessionConfig = preload("res://src/infrastructure/network/SessionConfig.gd")
const WORLD_SCENE := "res://scenes/World.tscn"
const LOBBY_SCENE := "res://scenes/Lobby.tscn"
const UI_MODES: PackedStringArray = ["offline_ai", "mixed", "human_only", "training"]

const MODE_SUBTITLES := {
	"offline_ai": "Offline AI skirmish",
	"mixed": "Mixed queue with humans + AI",
	"human_only": "Human-only matchmaking",
	"training": "Training mode coming soon"
}

@onready var menu_layer: CanvasLayer = $ModeSelect
@onready var subtitle_label: Label = $ModeSelect/Root/VBox/TitleWrap/TitlePanel/TitleVBox/ModeSubtitle
@onready var mode_cards: Array[PanelContainer] = [
	$ModeSelect/Root/VBox/CardsWrap/Cards/OfflineCard,
	$ModeSelect/Root/VBox/CardsWrap/Cards/MixedCard,
	$ModeSelect/Root/VBox/CardsWrap/Cards/HumanCard,
	$ModeSelect/Root/VBox/CardsWrap/Cards/TrainingCard
]
@onready var border_fx: Array[Panel] = [
	$ModeSelect/Root/VBox/CardsWrap/Cards/OfflineCard/BorderFx,
	$ModeSelect/Root/VBox/CardsWrap/Cards/MixedCard/BorderFx,
	$ModeSelect/Root/VBox/CardsWrap/Cards/HumanCard/BorderFx,
	$ModeSelect/Root/VBox/CardsWrap/Cards/TrainingCard/BorderFx
]
@onready var hit_areas: Array[Button] = [
	$ModeSelect/Root/VBox/CardsWrap/Cards/OfflineCard/HitArea,
	$ModeSelect/Root/VBox/CardsWrap/Cards/MixedCard/HitArea,
	$ModeSelect/Root/VBox/CardsWrap/Cards/HumanCard/HitArea,
	$ModeSelect/Root/VBox/CardsWrap/Cards/TrainingCard/HitArea
]

var _selected_index: int = 0
var _hover_index: int = -1
var _launching: bool = false
var _blink_running: bool = false

func _ready() -> void:
	_apply_session_overrides()
	if _should_auto_start():
		_start_with_mode(SessionConfig.selected_mode)
		return
	for i in range(hit_areas.size()):
		hit_areas[i].pressed.connect(_on_card_pressed.bind(i))
		hit_areas[i].mouse_entered.connect(_on_card_hovered.bind(i))
		hit_areas[i].mouse_exited.connect(_on_card_unhovered.bind(i))
	_selected_index = maxi(UI_MODES.find(SessionConfig.selected_mode), 0)
	_refresh_menu(true)

func _unhandled_input(event: InputEvent) -> void:
	if _launching or _blink_running:
		return
	if event is not InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_UP, KEY_LEFT:
			_selected_index = posmod(_selected_index - 1, UI_MODES.size())
			_refresh_menu()
		KEY_DOWN, KEY_RIGHT:
			_selected_index = posmod(_selected_index + 1, UI_MODES.size())
			_refresh_menu()
		KEY_1:
			_selected_index = 0
			_refresh_menu()
		KEY_2:
			_selected_index = 1
			_refresh_menu()
		KEY_3:
			_selected_index = 2
			_refresh_menu()
		KEY_4:
			_selected_index = 3
			_refresh_menu()
		KEY_ENTER, KEY_KP_ENTER:
			_confirm_selected_mode()
		_:
			pass

func _on_card_pressed(index: int) -> void:
	if _launching or _blink_running:
		return
	_selected_index = clampi(index, 0, UI_MODES.size() - 1)
	_refresh_menu()

func _on_card_hovered(index: int) -> void:
	if _launching or _blink_running:
		return
	_hover_index = index
	_refresh_menu()

func _on_card_unhovered(index: int) -> void:
	if _hover_index == index:
		_hover_index = -1
		_refresh_menu()

func _confirm_selected_mode() -> void:
	if _launching or _blink_running:
		return
	_blink_running = true
	await _blink_selected_border()
	_blink_running = false
	_start_with_mode(UI_MODES[_selected_index])

func _blink_selected_border() -> void:
	var idx := _selected_index
	var fx := border_fx[idx]
	if fx == null:
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	for _i in range(3):
		tween.tween_property(fx, "modulate:a", 1.0, 0.08)
		tween.tween_property(fx, "modulate:a", 0.15, 0.08)
	await tween.finished

func _apply_session_overrides() -> void:
	SessionConfig.network_enabled = false
	SessionConfig.network_role = "offline"
	SessionConfig.transport = "local"
	SessionConfig.requeue_on_lobby_entry = false
	SessionConfig.local_actor_id = "player"
	var env_mode: String = OS.get_environment("NEON_MODE")
	if UI_MODES.has(env_mode):
		SessionConfig.selected_mode = env_mode
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--mode="):
			var value: String = arg.get_slice("=", 1)
			if UI_MODES.has(value):
				SessionConfig.selected_mode = value

func _should_auto_start() -> bool:
	var args = OS.get_cmdline_args()
	if OS.has_feature("dedicated_server"):
		return true
	if DisplayServer.get_name() == "headless":
		return true
	if OS.get_environment("NEON_SERVER") == "1":
		return true
	if OS.get_environment("NEON_AUTO_START") == "1":
		return true
	if OS.has_environment("NEON_MODE") and not OS.get_environment("NEON_MODE").is_empty():
		return true
	if OS.has_environment("NEON_NETWORK_ROLE") and not OS.get_environment("NEON_NETWORK_ROLE").is_empty():
		return true
	return args.has("--server") or args.has("--skip-mode-select")

func _refresh_menu(force: bool = false) -> void:
	if menu_layer != null:
		menu_layer.visible = true
	var mode_name := UI_MODES[_selected_index]
	if subtitle_label != null:
		subtitle_label.text = String(MODE_SUBTITLES.get(mode_name, ""))
	for i in range(mode_cards.size()):
		var card := mode_cards[i]
		var selected := i == _selected_index
		var hovered := i == _hover_index
		if card == null:
			continue
		card.pivot_offset = card.size * 0.5
		var target_scale := Vector2.ONE
		var target_alpha := 0.66
		var target_border_alpha := 0.08
		if selected:
			target_scale = Vector2(1.08, 1.08)
			target_alpha = 1.0
			target_border_alpha = 0.78
		elif hovered:
			target_scale = Vector2(1.03, 1.03)
			target_alpha = 0.9
			target_border_alpha = 0.35
		card.z_index = 12 if selected else (8 if hovered else 0)
		if force:
			card.scale = target_scale
			card.modulate = Color(1.0, 1.0, 1.0, target_alpha)
			if border_fx[i] != null:
				border_fx[i].modulate = Color(1.0, 1.0, 1.0, target_border_alpha)
			continue
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "scale", target_scale, 0.13)
		tween.parallel().tween_property(card, "modulate:a", target_alpha, 0.13)
		if border_fx[i] != null and not _blink_running:
			tween.parallel().tween_property(border_fx[i], "modulate:a", target_border_alpha, 0.13)

func _start_with_mode(mode_name: String) -> void:
	if _launching:
		return
	if mode_name == "training":
		if subtitle_label != null:
			subtitle_label.text = "Training mode is coming soon"
		return
	_launching = true
	SessionConfig.selected_mode = mode_name
	if menu_layer != null:
		menu_layer.visible = false
	if mode_name == "offline_ai":
		SessionConfig.configure_offline(mode_name)
		call_deferred("_deferred_change_scene", WORLD_SCENE)
		return
	if _should_launch_world_direct():
		call_deferred("_deferred_change_scene", WORLD_SCENE)
		return
	call_deferred("_deferred_change_scene", LOBBY_SCENE)

func _deferred_change_scene(scene_path: String) -> void:
	if scene_path.is_empty():
		return
	get_tree().change_scene_to_file(scene_path)

func _should_launch_world_direct() -> bool:
	var args = OS.get_cmdline_args()
	if args.has("--server"):
		return true
	var env_server = OS.get_environment("NEON_SERVER").to_lower()
	if env_server == "1" or env_server == "true":
		return true
	var env_role = OS.get_environment("NEON_NETWORK_ROLE").to_lower()
	if env_role == "server":
		return true
	return false

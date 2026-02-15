extends Node2D

const SessionConfig = preload("res://src/infrastructure/network/SessionConfig.gd")
const WORLD_SCENE := "res://scenes/World.tscn"
const LOBBY_SCENE := "res://scenes/Lobby.tscn"
const MODES: PackedStringArray = ["offline_ai", "mixed", "human_only"]

@onready var menu_layer: CanvasLayer = $ModeSelect
@onready var mode_label: Label = $ModeSelect/Panel/Margin/VBox/Mode
@onready var help_label: Label = $ModeSelect/Panel/Margin/VBox/Help

var _selected_index: int = 0
var _launching: bool = false

func _ready() -> void:
	_apply_session_overrides()
	if _should_auto_start():
		_start_with_mode(SessionConfig.selected_mode)
		return
	_selected_index = maxi(MODES.find(SessionConfig.selected_mode), 0)
	_refresh_menu()

func _unhandled_input(event: InputEvent) -> void:
	if _launching:
		return
	if event is not InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_UP:
			_selected_index = posmod(_selected_index - 1, MODES.size())
			_refresh_menu()
		KEY_DOWN:
			_selected_index = posmod(_selected_index + 1, MODES.size())
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
		KEY_ENTER, KEY_KP_ENTER:
			_start_with_mode(MODES[_selected_index])
		_:
			pass

func _apply_session_overrides() -> void:
	SessionConfig.network_enabled = false
	SessionConfig.network_role = "offline"
	SessionConfig.transport = "local"
	SessionConfig.requeue_on_lobby_entry = false
	SessionConfig.local_actor_id = "player"
	var env_mode: String = OS.get_environment("NEON_MODE")
	if env_mode == "offline_ai" or env_mode == "mixed" or env_mode == "human_only":
		SessionConfig.selected_mode = env_mode
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--mode="):
			var value: String = arg.get_slice("=", 1)
			if value == "offline_ai" or value == "mixed" or value == "human_only":
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

func _refresh_menu() -> void:
	if menu_layer != null:
		menu_layer.visible = true
	if mode_label != null:
		mode_label.text = "Selected Mode: %s" % MODES[_selected_index]
	if help_label != null:
		help_label.text = "[UP/DOWN] or [1/2/3] select\n[ENTER] start"

func _start_with_mode(mode_name: String) -> void:
	if _launching:
		return
	_launching = true
	SessionConfig.selected_mode = mode_name
	if menu_layer != null:
		menu_layer.visible = false
	if mode_name == "offline_ai":
		SessionConfig.configure_offline(mode_name)
		get_tree().change_scene_to_file(WORLD_SCENE)
		return
	get_tree().change_scene_to_file(LOBBY_SCENE)

extends CanvasLayer

const MENU_BGM_PATH := "res://assets/audio/bgm/menu_background.mp3"
const GAMEPLAY_BGM_PATH := "res://assets/audio/bgm/background.mp3"
const DEFAULT_VOLUME_LINEAR := 0.5
const SILENT_DB := -80.0
const UI_MARGIN_X := 24.0
const UI_MARGIN_Y := 36.0
const GEAR_BUTTON_SIZE := Vector2(56.0, 56.0)
const POPUP_SIZE := Vector2(220.0, 120.0)

var _player: AudioStreamPlayer = null
var _ui_root: Control = null
var _gear_panel: PanelContainer = null
var _popup_panel: PanelContainer = null
var _gear_button: Button = null
var _slider: HSlider = null
var _mute_button: Button = null

var _menu_stream: AudioStream = null
var _gameplay_stream: AudioStream = null
var _current_context: String = ""
var _volume_linear: float = DEFAULT_VOLUME_LINEAR
var _muted: bool = false
var _audio_enabled: bool = false
var _menu_open: bool = false

func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	_audio_enabled = _is_audio_client_enabled()
	if not _audio_enabled:
		visible = false
		set_process(false)
		return
	_build_audio_player()
	_build_controls()
	_load_streams()
	_apply_volume()
	_refresh_context(true)
	set_process(true)

func _process(_delta: float) -> void:
	var next_enabled := _is_audio_client_enabled()
	if next_enabled != _audio_enabled:
		_audio_enabled = next_enabled
		visible = _audio_enabled
		if not _audio_enabled:
			if _player != null:
				_player.stop()
			return
		if _player == null:
			_build_audio_player()
		if _gear_panel == null:
			_build_controls()
		if _menu_stream == null or _gameplay_stream == null:
			_load_streams()
		_apply_volume()
	_layout_controls()
	_refresh_context(false)

func _build_audio_player() -> void:
	if _player != null:
		return
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	add_child(_player)

func _build_controls() -> void:
	if _gear_panel != null:
		return
	_ui_root = Control.new()
	_ui_root.name = "MusicUiRoot"
	_ui_root.anchor_left = 0.0
	_ui_root.anchor_top = 0.0
	_ui_root.anchor_right = 0.0
	_ui_root.anchor_bottom = 0.0
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui_root)

	var gear_style := StyleBoxFlat.new()
	gear_style.bg_color = Color(0, 0, 0, 0)
	gear_style.content_margin_left = 4.0
	gear_style.content_margin_top = 4.0
	gear_style.content_margin_right = 4.0
	gear_style.content_margin_bottom = 4.0

	_gear_panel = PanelContainer.new()
	_gear_panel.name = "SettingsButton"
	_gear_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_gear_panel.add_theme_stylebox_override("panel", gear_style)
	_ui_root.add_child(_gear_panel)

	_gear_button = Button.new()
	_gear_button.custom_minimum_size = Vector2(48.0, 48.0)
	_gear_button.text = "⚙"
	_gear_button.tooltip_text = "Open audio settings"
	_gear_button.add_theme_font_size_override("font_size", 30)
	_gear_button.flat = true
	_gear_button.pressed.connect(_on_toggle_pressed)
	_gear_panel.add_child(_gear_button)

	var popup_style := StyleBoxFlat.new()
	popup_style.bg_color = Color(0.02, 0.08, 0.14, 0.97)
	popup_style.border_width_left = 2
	popup_style.border_width_top = 2
	popup_style.border_width_right = 2
	popup_style.border_width_bottom = 2
	popup_style.border_color = Color(0.5, 0.9, 1.0, 0.95)
	popup_style.corner_radius_top_left = 6
	popup_style.corner_radius_top_right = 6
	popup_style.corner_radius_bottom_right = 6
	popup_style.corner_radius_bottom_left = 6
	popup_style.content_margin_left = 10.0
	popup_style.content_margin_top = 10.0
	popup_style.content_margin_right = 10.0
	popup_style.content_margin_bottom = 10.0

	_popup_panel = PanelContainer.new()
	_popup_panel.name = "AudioPopup"
	_popup_panel.visible = false
	_popup_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_popup_panel.add_theme_stylebox_override("panel", popup_style)
	_ui_root.add_child(_popup_panel)

	var popup_vbox := VBoxContainer.new()
	popup_vbox.add_theme_constant_override("separation", 8)
	_popup_panel.add_child(popup_vbox)

	var title := Label.new()
	title.text = "Audio"
	title.add_theme_font_size_override("font_size", 14)
	popup_vbox.add_child(title)

	_slider = HSlider.new()
	_slider.custom_minimum_size = Vector2(160.0, 0.0)
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.01
	_slider.value = _volume_linear
	_slider.tooltip_text = "Music volume"
	_slider.value_changed.connect(_on_volume_changed)
	popup_vbox.add_child(_slider)

	_mute_button = Button.new()
	_mute_button.custom_minimum_size = Vector2(0.0, 28.0)
	_mute_button.tooltip_text = "Mute music"
	_mute_button.pressed.connect(_on_mute_pressed)
	popup_vbox.add_child(_mute_button)
	_update_mute_button()
	_update_controls_visibility()
	_layout_controls()

func _load_streams() -> void:
	_menu_stream = _load_music_stream(MENU_BGM_PATH)
	_gameplay_stream = _load_music_stream(GAMEPLAY_BGM_PATH)

func _refresh_context(force: bool) -> void:
	if not _audio_enabled:
		return
	var next_context := _detect_context()
	if not force and next_context == _current_context and _player != null and _player.playing:
		return
	_current_context = next_context
	var stream := _get_stream_for_context(next_context)
	if stream == null or _player == null:
		return
	if not force and _player.stream == stream and _player.playing:
		return
	_player.stream = stream
	_player.play()

func _detect_context() -> String:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return "menu"
	var scene_path := tree.current_scene.scene_file_path
	if scene_path.ends_with("World.tscn"):
		return "gameplay"
	return "menu"

func _get_stream_for_context(context: String) -> AudioStream:
	if context == "gameplay":
		return _gameplay_stream
	return _menu_stream

func _on_volume_changed(value: float) -> void:
	_volume_linear = clampf(value, 0.0, 1.0)
	_apply_volume()

func _on_toggle_pressed() -> void:
	_menu_open = not _menu_open
	_update_controls_visibility()
	_layout_controls()

func _on_mute_pressed() -> void:
	_muted = not _muted
	_apply_volume()
	_update_mute_button()

func _apply_volume() -> void:
	if _player == null:
		return
	if _muted:
		_player.volume_db = SILENT_DB
		return
	if _volume_linear <= 0.001:
		_player.volume_db = SILENT_DB
		return
	_player.volume_db = linear_to_db(_volume_linear)

func _update_mute_button() -> void:
	if _mute_button == null:
		return
	_mute_button.text = "Unmute Music" if _muted else "Mute Music"

func _update_controls_visibility() -> void:
	if _gear_panel == null or _popup_panel == null:
		return
	_gear_panel.custom_minimum_size = GEAR_BUTTON_SIZE
	_popup_panel.custom_minimum_size = POPUP_SIZE
	_popup_panel.visible = _menu_open

func _layout_controls() -> void:
	if _ui_root == null or _gear_panel == null:
		return
	var viewport_rect := get_viewport().get_visible_rect()
	_ui_root.position = Vector2.ZERO
	_ui_root.size = viewport_rect.size
	_gear_panel.position = viewport_rect.size - GEAR_BUTTON_SIZE - Vector2(UI_MARGIN_X, UI_MARGIN_Y)
	_gear_panel.size = GEAR_BUTTON_SIZE
	if _popup_panel != null:
		_popup_panel.position = Vector2(
			_gear_panel.position.x - POPUP_SIZE.x + GEAR_BUTTON_SIZE.x,
			_gear_panel.position.y - POPUP_SIZE.y - 8.0
		)
		_popup_panel.size = POPUP_SIZE

func _load_music_stream(source_path: String) -> AudioStream:
	var stream := _load_imported_audio(source_path)
	if stream == null:
		stream = ResourceLoader.load(source_path) as AudioStream
	return _make_looping_stream(stream)

func _make_looping_stream(stream: AudioStream) -> AudioStream:
	if stream == null:
		return null
	var duplicated: AudioStream = stream.duplicate(true) as AudioStream
	if duplicated == null:
		duplicated = stream
	for property_info in duplicated.get_property_list():
		if String(property_info.name) == "loop":
			duplicated.set("loop", true)
			break
	return duplicated

func _load_imported_audio(source_path: String) -> AudioStream:
	var import_path := source_path + ".import"
	var cfg := ConfigFile.new()
	if cfg.load(import_path) != OK:
		return null
	var remap_path := cfg.get_value("remap", "path", "") as String
	if remap_path.is_empty():
		return null
	return ResourceLoader.load(remap_path) as AudioStream

func _is_audio_client_enabled() -> bool:
	if OS.has_feature("dedicated_server"):
		return false
	if DisplayServer.get_name() == "headless":
		return false
	if OS.get_environment("NEON_SERVER") == "1":
		return false
	return true

func _input(event: InputEvent) -> void:
	if not _audio_enabled or not _menu_open:
		return
	if event is InputEventMouseButton and event.pressed:
		var mouse_position := get_viewport().get_mouse_position()
		var inside_button := Rect2(_gear_panel.position, _gear_panel.size).has_point(mouse_position)
		var inside_popup := _popup_panel != null and _popup_panel.visible and Rect2(_popup_panel.position, _popup_panel.size).has_point(mouse_position)
		if not inside_button and not inside_popup:
			_menu_open = false
			_update_controls_visibility()

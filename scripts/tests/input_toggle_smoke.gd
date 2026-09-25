extends SceneTree

const WorldScene = preload("res://src/presentation/scenes/World.tscn")

func _initialize() -> void:
	var world := WorldScene.instantiate()
	get_root().add_child(world)
	await process_frame
	world.input_enabled = true
	world.game_mode = "offline_ai"
	world.dedicated_server = false

	var mute_event := InputEventAction.new()
	mute_event.action = "toggle_mute"
	mute_event.pressed = true
	mute_event.strength = 1.0
	if not world.input_enabled:
		_fail("world input unexpectedly disabled")
		return
	if not mute_event.is_action_pressed("toggle_mute"):
		_fail("synthetic mute action was not recognized")
		return
	world._input(mute_event)
	if not world.mute_toggle_was_pressed:
		_fail("mute event did not latch the polling fallback")
		return

	var pause_event := InputEventKey.new()
	pause_event.keycode = KEY_P
	pause_event.physical_keycode = KEY_P
	pause_event.pressed = true
	if not bool(world._handle_pause_input(pause_event)):
		_fail("pause key was not handled")
		return
	if not world.game_paused or not world.pause_toggle_was_pressed:
		_fail("pause event did not latch the polling fallback")
		return

	# SceneTree pause is global. Transition preparation must prevent a restarted
	# or newly-entered session from inheriting a frozen tree.
	world._prepare_scene_transition()
	if get_root().get_tree().paused or world.game_paused or world.pause_toggle_was_pressed:
		_fail("scene transition retained pause state")
		return

	# Also cover teardown that bypasses the normal buttons, as test harnesses and
	# host-driven scene replacement can remove a paused world directly.
	world._toggle_pause()
	if not get_root().get_tree().paused:
		_fail("second pause did not engage")
		return
	world.queue_free()
	await process_frame
	if get_root().get_tree().paused:
		_fail("paused world teardown left SceneTree paused")
		return

	# Restore global process/audio state before exiting the smoke test.
	get_root().get_tree().paused = false
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		AudioServer.set_bus_mute(master_bus, false)
	print("[input_toggle_smoke] PASS")
	quit(0)

func _fail(message: String) -> void:
	get_root().get_tree().paused = false
	push_error("input_toggle_smoke failed: %s" % message)
	quit(1)

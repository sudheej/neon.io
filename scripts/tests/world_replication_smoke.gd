extends SceneTree

const SessionConfig = preload("res://src/infrastructure/network/SessionConfig.gd")

func _initialize() -> void:
	SessionConfig.configure_online_client("mixed", "127.0.0.1", 7000, "sess_replica", "player_replica")
	SessionConfig.transport = "local"
	SessionConfig.local_actor_id = "player"
	SessionConfig.auto_requeue_on_death = false

	var world_scene: PackedScene = load("res://scenes/World.tscn")
	if world_scene == null:
		push_error("world_replication_smoke failed: missing world scene")
		quit(1)
		return
	var world = world_scene.instantiate()
	world.set("event_audio_loaded", true)
	get_root().add_child(world)

	await process_frame
	await process_frame

	var enemies_root = world.get_node_or_null("Enemies")
	if enemies_root != null and enemies_root.get_child_count() != 0:
		push_error("world_replication_smoke failed: online client spawned local enemies")
		quit(1)
		return

	world.call("_on_network_state_received", {
		"tick": 1,
		"data": {
			"time": 1.0,
			"actors": [
				{
					"id": "player",
					"position": {"x": 10.0, "y": 10.0},
					"health": 40.0,
					"max_health": 40.0,
					"is_ai": false
				},
				{
					"id": "remote_1",
					"position": {"x": 120.0, "y": 64.0},
					"health": 30.0,
					"max_health": 40.0,
					"is_ai": false
				}
			]
		}
	})

	await process_frame

	var remote: Variant = world.call("_find_actor_by_id", "remote_1")
	if remote == null:
		push_error("world_replication_smoke failed: missing replicated actor")
		quit(1)
		return
	if remote is Node2D:
		var pos := (remote as Node2D).global_position
		if not pos.is_equal_approx(Vector2(120.0, 64.0)):
			push_error("world_replication_smoke failed: unexpected replicated actor position")
			quit(1)
			return

	world.call("_on_network_state_received", {
		"tick": 2,
		"data": {
			"time": 1.1,
			"actors_upsert": [
				{
					"id": "remote_1",
					"position": {"x": 144.0, "y": 80.0},
					"health": 27.0
				}
			]
		}
	})

	await process_frame

	remote = world.call("_find_actor_by_id", "remote_1")
	if remote == null:
		push_error("world_replication_smoke failed: replicated actor disappeared after delta")
		quit(1)
		return
	if remote is Node2D:
		var delta_pos := (remote as Node2D).global_position
		if not delta_pos.is_equal_approx(Vector2(144.0, 80.0)):
			push_error("world_replication_smoke failed: delta position not applied")
			quit(1)
			return

	world.call("_on_network_state_received", {
		"tick": 3,
		"data": {
			"time": 1.2,
			"actors_remove": ["remote_1"]
		}
	})

	await process_frame
	await process_frame

	remote = world.call("_find_actor_by_id", "remote_1")
	if remote != null:
		push_error("world_replication_smoke failed: replicated actor not removed")
		quit(1)
		return

	world.queue_free()
	await process_frame

	print("[world_replication_smoke] PASS")
	quit(0)

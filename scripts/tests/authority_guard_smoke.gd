extends SceneTree

const GameWorld = preload("res://src/domain/world/GameWorld.gd")
const CommandQueue = preload("res://src/input/CommandQueue.gd")
const GameCommand = preload("res://src/domain/commands/Command.gd")

class DummyActor:
	extends Node2D
	var actor_id: String = "smoke_actor"
	var move_count: int = 0
	var last_move: Vector2 = Vector2.ZERO

	func _ready() -> void:
		add_to_group("combatants")

	func set_move_command(dir: Vector2) -> void:
		move_count += 1
		last_move = dir

func _initialize() -> void:
	var root := Node2D.new()
	get_root().add_child(root)

	var actor := DummyActor.new()
	root.add_child(actor)

	var world := GameWorld.new()
	world.command_queue_path = NodePath("CommandQueue")
	world.world_path = NodePath("..")
	world.max_commands_per_second_per_actor = 2
	root.add_child(world)

	var queue := CommandQueue.new()
	queue.name = "CommandQueue"
	world.add_child(queue)

	await process_frame

	var now_ms: int = Time.get_ticks_msec()
	world.submit_command(_net_move("smoke_actor", Vector2.RIGHT, "p1", 1, now_ms))
	world.submit_command(_net_move("smoke_actor", Vector2.LEFT, "p1", 1, now_ms + 1)) # replay seq
	world.submit_command(_net_move("smoke_actor", Vector2.DOWN, "p2", 2, now_ms + 2)) # owner mismatch
	world.submit_command(_net_move("smoke_actor", Vector2.UP, "p1", 3, now_ms + 10000)) # future ts
	world.submit_command(_net_move("smoke_actor", Vector2(0.5, 0.0), "p1", 4, now_ms + 3))
	world.submit_command(_net_move("smoke_actor", Vector2(0.8, 0.0), "p1", 5, now_ms + 4)) # rate-limit

	world.call("_physics_process", 0.016)

	if actor.move_count != 2:
		push_error("authority_guard_smoke failed: move_count=%d" % actor.move_count)
		quit(1)
		return

	print("[authority_guard_smoke] PASS moves=%d last=%s" % [actor.move_count, actor.last_move])
	quit(0)

func _net_move(actor_id: String, dir: Vector2, player_id: String, seq: int, timestamp_ms: int) -> GameCommand:
	var cmd := GameCommand.move(actor_id, dir)
	cmd.payload["__net"] = {
		"player_id": player_id,
		"seq": seq,
		"timestamp_ms": timestamp_ms,
		"session_id": "sess_smoke"
	}
	return cmd

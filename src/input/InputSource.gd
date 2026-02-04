extends Node
class_name InputSource

@export var actor_id: String = "player"
@export var command_queue_path: NodePath

var _queue = null

func _ready() -> void:
	if command_queue_path != NodePath(""):
		_queue = get_node_or_null(command_queue_path)

func set_command_queue(queue) -> void:
	_queue = queue

func emit_command(command) -> void:
	if _queue == null:
		return
	_queue.enqueue(command)

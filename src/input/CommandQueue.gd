extends Node
class_name CommandQueue

var _queue: Array = []

func enqueue(command) -> void:
	if command == null:
		return
	_queue.append(command)

func drain() -> Array:
	var pending = _queue
	_queue = []
	return pending

func clear() -> void:
	_queue.clear()

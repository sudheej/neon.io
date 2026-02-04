extends Node
class_name NetworkAdapter

signal command_received(command)

func _ready() -> void:
	add_to_group("network_adapter")

func send_state(_state: Dictionary) -> void:
	pass

func send_event(_event: Dictionary) -> void:
	pass

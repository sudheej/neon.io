extends Node
class_name AgentBridge

signal command_received(command)

func _ready() -> void:
	add_to_group("agent_bridge")

func push_command(command) -> void:
	command_received.emit(command)

func send_state(_state: Dictionary) -> void:
	pass

func send_event(_event: Dictionary) -> void:
	pass

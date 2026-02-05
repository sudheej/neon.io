extends "res://src/input/InputSource.gd"
class_name AgentInputSource

const GameCommand = preload("res://src/domain/commands/Command.gd")

@export var agent_bridge_path: NodePath

var _bridge: Node = null

func _ready() -> void:
	super._ready()
	_bridge = get_node_or_null(agent_bridge_path)
	if _bridge != null and _bridge.has_signal("command_received"):
		_bridge.connect("command_received", Callable(self, "_on_agent_command"))

func _on_agent_command(command) -> void:
	if command == null:
		return
	if typeof(command) == TYPE_DICTIONARY:
		var cmd = GameCommand.new()
		cmd.type = int(command.get("type", GameCommand.Type.MOVE))
		cmd.actor_id = String(command.get("actor_id", actor_id))
		cmd.payload = command.get("payload", {})
		emit_command(cmd)
		return
	if command.has_method("get"):
		if command.get("actor_id", "") == "":
			command.actor_id = actor_id
	emit_command(command)

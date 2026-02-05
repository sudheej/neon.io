extends Node
class_name LocalAgentStub

const GameCommand = preload("res://src/domain/commands/Command.gd")

@export var enabled: bool = false
@export var actor_id: String = "player"
@export var command_interval: float = 0.35
@export var move_radius: float = 1.0
@export var agent_bridge_path: NodePath = NodePath("..")

var time_accum: float = 0.0
var phase: float = 0.0

func _process(delta: float) -> void:
	if not enabled:
		return
	time_accum += delta
	phase = fmod(phase + delta, TAU)
	if time_accum < command_interval:
		return
	time_accum = 0.0
	var bridge = get_node_or_null(agent_bridge_path) as Node
	if bridge == null:
		return
	var cmd = GameCommand.move(actor_id, Vector2(cos(phase), sin(phase)) * move_radius)
	if bridge.has_method("push_command"):
		bridge.push_command(cmd)

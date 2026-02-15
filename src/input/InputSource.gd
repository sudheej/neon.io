extends Node
class_name InputSource

@export var actor_id: String = "player"
@export var command_queue_path: NodePath
@export var network_adapter_path: NodePath

var _queue = null
var _network_adapter: Node = null

func _ready() -> void:
	if command_queue_path != NodePath(""):
		_queue = get_node_or_null(command_queue_path)
	if network_adapter_path != NodePath(""):
		_network_adapter = get_node_or_null(network_adapter_path)
	if _network_adapter == null:
		_network_adapter = get_tree().get_first_node_in_group("network_adapter")

func set_command_queue(queue) -> void:
	_queue = queue

func emit_command(command) -> void:
	_resolve_network_adapter()
	if _should_send_over_network() and _network_adapter.has_method("send_command"):
		_network_adapter.send_command(command)
		return
	if _queue != null:
		_queue.enqueue(command)

func _should_send_over_network() -> bool:
	_resolve_network_adapter()
	if _network_adapter == null:
		return false
	if not _network_adapter.has_method("is_online"):
		return false
	if not bool(_network_adapter.call("is_online")):
		return false
	if _network_adapter.has_method("net_is_connected") and not bool(_network_adapter.call("net_is_connected")):
		return false
	var adapter_role: String = String(_network_adapter.get("role"))
	return adapter_role == "client"

func _resolve_network_adapter() -> void:
	if _network_adapter != null and is_instance_valid(_network_adapter):
		return
	if network_adapter_path != NodePath(""):
		_network_adapter = get_node_or_null(network_adapter_path)
		if _network_adapter != null:
			return
	_network_adapter = get_tree().get_first_node_in_group("network_adapter")

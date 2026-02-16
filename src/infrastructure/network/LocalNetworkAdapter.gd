extends "res://src/infrastructure/network/NetworkAdapter.gd"
class_name LocalNetworkAdapter

func _ready() -> void:
	if transport != "enet":
		transport = "local"
	super._ready()

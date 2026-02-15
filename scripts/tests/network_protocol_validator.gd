extends SceneTree

const NetProtocol = preload("res://src/infrastructure/network/NetProtocol.gd")

const EXAMPLES_DIR := "res://docs/network/examples"

func _initialize() -> void:
	var dir := DirAccess.open(EXAMPLES_DIR)
	if dir == null:
		push_error("cannot open %s" % EXAMPLES_DIR)
		quit(1)
		return

	var failures: Array[String] = []
	var sample_count := 0
	dir.list_dir_begin()
	while true:
		var file_name := dir.get_next()
		if file_name.is_empty():
			break
		if dir.current_is_dir():
			continue
		if not file_name.ends_with(".json"):
			continue
		sample_count += 1
		var full_path := "%s/%s" % [EXAMPLES_DIR, file_name]
		var raw := FileAccess.get_file_as_string(full_path)
		var parsed = JSON.parse_string(raw)
		if typeof(parsed) != TYPE_DICTIONARY:
			failures.append("%s: invalid json object" % file_name)
			continue
		var result: Dictionary = NetProtocol.validate_message(parsed)
		if not bool(result.get("ok", false)):
			failures.append("%s: %s" % [file_name, String(result.get("error", "unknown"))])
	dir.list_dir_end()

	if failures.is_empty():
		print("[network_protocol_validator] PASS (%s examples)" % sample_count)
		quit(0)
		return

	for failure in failures:
		push_error("[network_protocol_validator] %s" % failure)
	quit(1)

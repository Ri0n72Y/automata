class_name Scene01ProgramSource
extends RefCounted

const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")

const HEADER := "automata_scene01_program 1"


func encode(program: Scene01Program) -> String:
	if program == null:
		return HEADER + "\n"
	var lines: Array[String] = [HEADER, "default_vehicle %s" % String(program.vehicle_id)]
	var ordered := _ordered_nodes(program)
	var command_index_by_node: Dictionary = {}
	var command_index := 0
	for node in ordered:
		if int(node.get("type", -1)) == ProgramScript.NodeType.START:
			continue
		command_index += 1
		command_index_by_node[int(node.get("id", ProgramScript.NO_NODE_ID))] = command_index
	for node in ordered:
		match int(node.get("type", -1)):
			ProgramScript.NodeType.START:
				pass
			ProgramScript.NodeType.SELECT_VEHICLE:
				lines.append("select_vehicle %s" % String(node.get("vehicle_id", &"")))
			ProgramScript.NodeType.MOVE_TO:
				var target: Vector2i = node.get("target_anchor", Vector2i(-1, -1))
				lines.append("move_to %d %d" % [target.x, target.y])
			ProgramScript.NodeType.GRAB_DROP:
				lines.append("grab_drop")
			ProgramScript.NodeType.REPEAT:
				var target_id := int(node.get("repeat_target_id", ProgramScript.NO_NODE_ID))
				lines.append("repeat %d %d" % [
					int(node.get("repeat_count", 1)),
					int(command_index_by_node.get(target_id, 0)),
				])
	return "\n".join(lines) + "\n"


func parse(source: String) -> Dictionary:
	var diagnostics: Array[Dictionary] = []
	var program := ProgramScript.new()
	program.reset()
	var command_node_ids: Array[int] = []
	var pending_repeats: Array[Dictionary] = []
	var saw_header := false
	var saw_default_vehicle := false
	var lines := source.split("\n", false)
	for index in range(lines.size()):
		var line_number := index + 1
		var text := String(lines[index]).strip_edges()
		if text.is_empty() or text.begins_with("#"):
			continue
		var tokens := text.split(" ", false)
		if not saw_header:
			if text != HEADER:
				return _result(null, [_diagnostic(line_number, &"source_header_invalid", "Expected '%s'." % HEADER)])
			saw_header = true
			continue
		if tokens[0] == "default_vehicle":
			if saw_default_vehicle or tokens.size() != 2:
				diagnostics.append(_diagnostic(line_number, &"default_vehicle_invalid", "default_vehicle requires exactly one vehicle id."))
				continue
			program.vehicle_id = StringName(tokens[1])
			saw_default_vehicle = true
			continue
		if not saw_default_vehicle:
			diagnostics.append(_diagnostic(line_number, &"default_vehicle_required", "default_vehicle must appear before commands."))
			continue
		var node_id := ProgramScript.NO_NODE_ID
		match tokens[0]:
			"select_vehicle":
				if tokens.size() != 2:
					diagnostics.append(_diagnostic(line_number, &"select_vehicle_syntax", "select_vehicle requires one vehicle id."))
					continue
				node_id = program.append_node(ProgramScript.NodeType.SELECT_VEHICLE)
				program.set_select_vehicle(node_id, StringName(tokens[1]))
			"move_to":
				if tokens.size() != 3 or not tokens[1].is_valid_int() or not tokens[2].is_valid_int():
					diagnostics.append(_diagnostic(line_number, &"move_to_syntax", "move_to requires integer x and y."))
					continue
				node_id = program.append_node(ProgramScript.NodeType.MOVE_TO)
				program.set_move_target(node_id, Vector2i(int(tokens[1]), int(tokens[2])))
			"grab_drop":
				if tokens.size() != 1:
					diagnostics.append(_diagnostic(line_number, &"grab_drop_syntax", "grab_drop takes no arguments."))
					continue
				node_id = program.append_node(ProgramScript.NodeType.GRAB_DROP)
			"repeat":
				if tokens.size() != 3 or not tokens[1].is_valid_int() or not tokens[2].is_valid_int():
					diagnostics.append(_diagnostic(line_number, &"repeat_syntax", "repeat requires count and target command number."))
					continue
				node_id = program.append_node(ProgramScript.NodeType.REPEAT)
				pending_repeats.append({"node_id": node_id, "count": int(tokens[1]), "target": int(tokens[2]), "line": line_number})
			_:
				diagnostics.append(_diagnostic(line_number, &"unknown_command", "Unknown program command '%s'." % tokens[0]))
				continue
		command_node_ids.append(node_id)

	if not saw_header:
		diagnostics.append(_diagnostic(1, &"source_header_required", "Program source header is required."))
	if not saw_default_vehicle:
		diagnostics.append(_diagnostic(1, &"default_vehicle_required", "default_vehicle is required."))
	for repeat in pending_repeats:
		var target_number := int(repeat["target"])
		if target_number < 1 or target_number > command_node_ids.size():
			diagnostics.append(_diagnostic(int(repeat["line"]), &"repeat_target_source_invalid", "repeat target command does not exist."))
			continue
		program.set_repeat(int(repeat["node_id"]), int(repeat["count"]), command_node_ids[target_number - 1])
	return _result(program if diagnostics.is_empty() else null, diagnostics)


func _ordered_nodes(program: Scene01Program) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var current_id := program.start_node_id
	var visited: Dictionary = {}
	while current_id != ProgramScript.NO_NODE_ID and not visited.has(current_id):
		visited[current_id] = true
		var node := program.get_node_data(current_id)
		if node.is_empty():
			break
		result.append(node)
		current_id = int(node.get("next_id", ProgramScript.NO_NODE_ID))
	return result


func _diagnostic(line: int, code: StringName, message: String) -> Dictionary:
	return {"line": line, "code": code, "message": message}


func _result(program: Scene01Program, diagnostics: Array[Dictionary]) -> Dictionary:
	return {"program": program, "diagnostics": diagnostics}

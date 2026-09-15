class_name Scene01ProgramSource
extends RefCounted

const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")

const HEADER := "automata_scene01_program 2"


func encode(program: Scene01Program) -> String:
	if program == null:
		return HEADER + "\n"
	var lines: Array[String] = [HEADER]
	var ordered := program.get_execution_order()
	var command_index_by_node: Dictionary = {}
	var command_index := 0
	for node in ordered:
		if int(node.get("type", -1)) == ProgramScript.NodeType.START:
			continue
		command_index += 1
		command_index_by_node[int(node.get("id", ProgramScript.NO_NODE_ID))] = command_index
	for node in ordered:
		var vehicle_id := String(node.get("vehicle_id", &""))
		match int(node.get("type", -1)):
			ProgramScript.NodeType.START:
				pass
			ProgramScript.NodeType.MOVE_TO:
				var target: Vector2i = node.get("target_anchor", Vector2i(-1, -1))
				lines.append("[%s:moveTo] %d %d" % [vehicle_id, target.x, target.y])
			ProgramScript.NodeType.GRAB_DROP:
				lines.append("[%s:grabDrop]" % vehicle_id)
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
	var lines := source.split("\n", true)
	for index in range(lines.size()):
		var line_number := index + 1
		var text := String(lines[index]).strip_edges()
		if text.is_empty() or text.begins_with("#"):
			continue
		if not saw_header:
			if text != HEADER:
				return _result(null, [_diagnostic(line_number, &"source_header_invalid", "Expected '%s'." % HEADER)])
			saw_header = true
			continue
		var tokens := text.split(" ", false)
		var node_id := ProgramScript.NO_NODE_ID
		if tokens[0] == "repeat":
			node_id = _parse_repeat(program, tokens, line_number, pending_repeats, diagnostics)
		else:
			node_id = _parse_vehicle_command(program, tokens, line_number, diagnostics)
		if node_id != ProgramScript.NO_NODE_ID:
			command_node_ids.append(node_id)

	if not saw_header:
		diagnostics.append(_diagnostic(1, &"source_header_required", "Program source header is required."))
	for repeat in pending_repeats:
		var target_number := int(repeat["target"])
		if target_number < 1 or target_number > command_node_ids.size():
			diagnostics.append(_diagnostic(int(repeat["line"]), &"repeat_target_source_invalid", "repeat target command does not exist."))
			continue
		program.set_repeat(int(repeat["node_id"]), int(repeat["count"]), command_node_ids[target_number - 1])
	return _result(program if diagnostics.is_empty() else null, diagnostics)


func _parse_vehicle_command(
	program: Scene01Program,
	tokens: PackedStringArray,
	line_number: int,
	diagnostics: Array[Dictionary]
) -> int:
	var head := String(tokens[0])
	if not head.begins_with("[") or not head.ends_with("]"):
		diagnostics.append(_diagnostic(line_number, &"command_binding_required", "Vehicle commands use [vehicle:command]."))
		return ProgramScript.NO_NODE_ID
	var binding := head.substr(1, head.length() - 2).split(":", false)
	if binding.size() != 2 or String(binding[0]).is_empty() or String(binding[1]).is_empty():
		diagnostics.append(_diagnostic(line_number, &"command_binding_invalid", "Vehicle command binding is invalid."))
		return ProgramScript.NO_NODE_ID
	var vehicle_id := StringName(binding[0])
	var action := String(binding[1])
	var node_id := ProgramScript.NO_NODE_ID
	match action:
		"moveTo":
			if tokens.size() != 3 or not tokens[1].is_valid_int() or not tokens[2].is_valid_int():
				diagnostics.append(_diagnostic(line_number, &"move_to_syntax", "moveTo requires integer x and y."))
				return ProgramScript.NO_NODE_ID
			node_id = program.append_node(ProgramScript.NodeType.MOVE_TO)
			program.set_move_target(node_id, Vector2i(int(tokens[1]), int(tokens[2])))
		"grabDrop":
			if tokens.size() != 1:
				diagnostics.append(_diagnostic(line_number, &"grab_drop_syntax", "grabDrop takes no arguments."))
				return ProgramScript.NO_NODE_ID
			node_id = program.append_node(ProgramScript.NodeType.GRAB_DROP)
		_:
			diagnostics.append(_diagnostic(line_number, &"unknown_command", "Unknown vehicle command '%s'." % action))
			return ProgramScript.NO_NODE_ID
	program.set_command_vehicle(node_id, vehicle_id)
	return node_id


func _parse_repeat(
	program: Scene01Program,
	tokens: PackedStringArray,
	line_number: int,
	pending_repeats: Array[Dictionary],
	diagnostics: Array[Dictionary]
) -> int:
	if tokens.size() != 3 or not tokens[1].is_valid_int() or not tokens[2].is_valid_int():
		diagnostics.append(_diagnostic(line_number, &"repeat_syntax", "repeat requires count and target command number."))
		return ProgramScript.NO_NODE_ID
	var node_id := program.append_node(ProgramScript.NodeType.REPEAT)
	pending_repeats.append({
		"node_id": node_id,
		"count": int(tokens[1]),
		"target": int(tokens[2]),
		"line": line_number,
	})
	return node_id


func _diagnostic(line: int, code: StringName, message: String) -> Dictionary:
	return {"line": line, "code": code, "message": message}


func _result(program: Scene01Program, diagnostics: Array[Dictionary]) -> Dictionary:
	return {"program": program, "diagnostics": diagnostics}

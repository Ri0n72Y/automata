class_name Scene01ProgramSource
extends RefCounted

const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const HEADER := "automata_scene01_program 2"

func parse(source: String) -> Dictionary:
	var diagnostics: Array[Dictionary] = []
	var program := ProgramScript.new()
	var pending_repeats: Array[Dictionary] = []
	var command_indices: Array[int] = []
	var saw_header := false
	var lines := source.split("\n", true)
	for index in range(lines.size()):
		var line := String(lines[index]).strip_edges()
		var line_number := index + 1
		if line.is_empty() or line.begins_with("#"):
			continue
		if not saw_header:
			if line != HEADER:
				return _result(null, [_diagnostic(line_number, &"source_header_invalid", "Expected '%s'." % HEADER)])
			saw_header = true
			continue
		var tokens := line.split(" ", false)
		if String(tokens[0]) == "repeat":
			var id := _parse_repeat(program, tokens, line_number, pending_repeats, diagnostics)
			if id >= 0:
				continue
		else:
			var id := _parse_command(program, tokens, line_number, diagnostics)
			if id >= 0:
				command_indices.append(id)
	if not saw_header:
		diagnostics.append(_diagnostic(1, &"source_header_required", "Program source header is required."))
	for repeat in pending_repeats:
		var target := int(repeat.target)
		if target < 1 or target > command_indices.size():
			diagnostics.append(_diagnostic(int(repeat.line), &"repeat_target_invalid", "Repeat target does not exist."))
			continue
		program.set_repeat(int(repeat.id), int(repeat.count), target - 1)
	return _result(program if diagnostics.is_empty() else null, diagnostics)

func _parse_command(program: Scene01Program, tokens: PackedStringArray, line: int, diagnostics: Array[Dictionary]) -> int:
	var binding := String(tokens[0]).trim_prefix("[").trim_suffix("]").split(":", false)
	if binding.size() != 2:
		diagnostics.append(_diagnostic(line, &"command_binding_invalid", "Expected [vehicle:command]."))
		return -1
	var id := -1
	match String(binding[1]):
		"moveTo":
			if tokens.size() != 3:
				diagnostics.append(_diagnostic(line, &"move_to_syntax", "moveTo requires x y."))
				return -1
			id = program.append_node(ProgramScript.NodeType.MOVE_TO)
			program.set_move_target(id, Vector2i(int(tokens[1]), int(tokens[2])))
		"grabDrop":
			id = program.append_node(ProgramScript.NodeType.GRAB_DROP)
		_:
			diagnostics.append(_diagnostic(line, &"unknown_command", "Unknown command."))
			return -1
	program.set_command_vehicle(id, StringName(binding[0]))
	return id

func _parse_repeat(program: Scene01Program, tokens: PackedStringArray, line: int, pending: Array[Dictionary], diagnostics: Array[Dictionary]) -> int:
	if tokens.size() != 3:
		diagnostics.append(_diagnostic(line, &"repeat_syntax", "repeat requires count and target."))
		return -1
	var id := program.append_node(ProgramScript.NodeType.REPEAT)
	pending.append({"id": id, "count": int(tokens[1]), "target": int(tokens[2]), "line": line})
	return id

func _diagnostic(line: int, code: StringName, message: String) -> Dictionary:
	return {"line": line, "code": code, "message": message}

func _result(program: Scene01Program, diagnostics: Array[Dictionary]) -> Dictionary:
	return {"program": program, "diagnostics": diagnostics}

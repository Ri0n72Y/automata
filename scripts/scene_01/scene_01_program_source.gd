class_name Scene01ProgramSource
extends RefCounted

const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const HEADER := "automata_scene01_program 2"


func parse(source: String) -> Dictionary:
	var diagnostics: Array[Dictionary] = []
	var program := ProgramScript.new()
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
		if String(tokens[0]) == "repeat":
			_parse_repeat(program, tokens, line_number, pending_repeats, diagnostics)
		else:
			_parse_vehicle_command(program, tokens, line_number, diagnostics)

	if not saw_header:
		diagnostics.append(_diagnostic(1, &"source_header_required", "Program source header is required."))
	_resolve_repeats(program, pending_repeats, diagnostics)
	return _result(program if diagnostics.is_empty() else null, diagnostics)


func _parse_vehicle_command(
	program: Scene01Program,
	tokens: PackedStringArray,
	line_number: int,
	diagnostics: Array[Dictionary]
) -> void:
	var head := String(tokens[0])
	if not head.begins_with("[") or not head.ends_with("]"):
		diagnostics.append(_diagnostic(line_number, &"command_binding_required", "Vehicle commands use [vehicle:command]."))
		return
	var binding := head.substr(1, head.length() - 2).split(":", false)
	if binding.size() != 2 or String(binding[0]).is_empty() or String(binding[1]).is_empty():
		diagnostics.append(_diagnostic(line_number, &"command_binding_invalid", "Vehicle command binding is invalid."))
		return
	var vehicle_id := StringName(binding[0])
	var action := String(binding[1])
	var statement_index := ProgramScript.NO_STATEMENT_INDEX
	match action:
		"moveTo":
			if tokens.size() != 3 or not tokens[1].is_valid_int() or not tokens[2].is_valid_int():
				diagnostics.append(_diagnostic(line_number, &"move_to_syntax", "moveTo requires integer x and y."))
				return
			statement_index = program.append_statement(ProgramScript.StatementType.MOVE_TO)
			program.set_move_target(statement_index, Vector2i(int(tokens[1]), int(tokens[2])))
		"grabDrop":
			if tokens.size() != 1:
				diagnostics.append(_diagnostic(line_number, &"grab_drop_syntax", "grabDrop takes no arguments."))
				return
			statement_index = program.append_statement(ProgramScript.StatementType.GRAB_DROP)
		_:
			diagnostics.append(_diagnostic(line_number, &"unknown_command", "Unknown vehicle command '%s'." % action))
			return
	program.set_statement_vehicle(statement_index, vehicle_id)


func _parse_repeat(
	program: Scene01Program,
	tokens: PackedStringArray,
	line_number: int,
	pending_repeats: Array[Dictionary],
	diagnostics: Array[Dictionary]
) -> void:
	if tokens.size() != 3 or not tokens[1].is_valid_int() or not tokens[2].is_valid_int():
		diagnostics.append(_diagnostic(line_number, &"repeat_syntax", "repeat requires integer count and target statement number."))
		return
	var statement_index := program.append_statement(ProgramScript.StatementType.REPEAT)
	pending_repeats.append({
		"statement_index": statement_index,
		"count": int(tokens[1]),
		"target_number": int(tokens[2]),
		"line": line_number,
	})


func _resolve_repeats(
	program: Scene01Program,
	pending_repeats: Array[Dictionary],
	diagnostics: Array[Dictionary]
) -> void:
	for repeat in pending_repeats:
		var repeat_index := int(repeat["statement_index"])
		var target_index := int(repeat["target_number"]) - 1
		if target_index < 0 or target_index >= repeat_index:
			diagnostics.append(_diagnostic(int(repeat["line"]), &"repeat_target_source_invalid", "repeat target must reference an earlier vehicle statement."))
			continue
		var target := program.get_statement(target_index)
		var target_type := int(target.get("type", -1))
		if target_type != ProgramScript.StatementType.MOVE_TO and target_type != ProgramScript.StatementType.GRAB_DROP:
			diagnostics.append(_diagnostic(int(repeat["line"]), &"repeat_target_source_invalid", "repeat target must reference an earlier vehicle statement."))
			continue
		program.set_repeat(repeat_index, int(repeat["count"]), target_index)


func _diagnostic(line: int, code: StringName, message: String) -> Dictionary:
	return {"line": line, "code": code, "message": message}


func _result(program: Scene01Program, diagnostics: Array[Dictionary]) -> Dictionary:
	return {"program": program, "diagnostics": diagnostics}

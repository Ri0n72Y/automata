class_name Scene01ProgramSource
extends RefCounted

const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const HEADER := "automata_scene01_program 2"
const ROTATION_NAMES := ["clockwise", "counterclockwise"]
const ROTATION_VALUES := {
	"clockwise": 1,
	"counterclockwise": -1,
}

func parse(source: String) -> Dictionary:
	var diagnostics: Array[Dictionary] = []
	var statement_lines: Array[int] = []
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
				return _result(null, [_diagnostic(line_number, &"source_header_invalid", "第一行必须是 '%s'。" % HEADER)], statement_lines)
			saw_header = true
			continue
		var tokens := text.split(" ", false)
		if String(tokens[0]) == "repeat":
			_parse_repeat(program, tokens, line_number, pending_repeats, diagnostics, statement_lines)
		else:
			_parse_vehicle_command(program, tokens, line_number, diagnostics, statement_lines)
	if not saw_header:
		diagnostics.append(_diagnostic(1, &"source_header_required", "程序源码缺少固定首行。"))
	_resolve_repeats(program, pending_repeats, diagnostics)
	return _result(program if diagnostics.is_empty() else null, diagnostics, statement_lines)

func _parse_vehicle_command(
	program: Scene01Program,
	tokens: PackedStringArray,
	line_number: int,
	diagnostics: Array[Dictionary],
	statement_lines: Array[int]
) -> void:
	var head := String(tokens[0])
	if not head.begins_with("[") or not head.ends_with("]"):
		diagnostics.append(_diagnostic(line_number, &"command_binding_required", "车辆命令必须使用 [vehicle:command] 格式。"))
		return
	var binding := head.substr(1, head.length() - 2).split(":", false)
	if binding.size() != 2 or String(binding[0]).is_empty() or String(binding[1]).is_empty():
		diagnostics.append(_diagnostic(line_number, &"command_binding_invalid", "车辆命令绑定格式无效。"))
		return
	var vehicle_id := StringName(binding[0])
	var action := String(binding[1])
	var statement_index := ProgramScript.NO_STATEMENT_INDEX
	match action:
		"moveTo":
			if tokens.size() != 3 or not tokens[1].is_valid_int() or not tokens[2].is_valid_int():
				diagnostics.append(_diagnostic(line_number, &"move_to_syntax", "moveTo 的 x、y 参数必须是整数。"))
				return
			statement_index = program.append_statement(ProgramScript.StatementType.MOVE_TO)
			program.set_move_target(statement_index, Vector2i(int(tokens[1]), int(tokens[2])))
		"grabDrop":
			if tokens.size() != 1:
				diagnostics.append(_diagnostic(line_number, &"grab_drop_syntax", "grabDrop 不接受参数。"))
				return
			statement_index = program.append_statement(ProgramScript.StatementType.GRAB_DROP)
		"rotate":
			var rotation_name := String(tokens[1]).to_lower() if tokens.size() == 2 else ""
			if not ROTATION_VALUES.has(rotation_name):
				diagnostics.append(_diagnostic(line_number, &"rotate_syntax", "rotate 参数必须为 clockwise（顺时针）或 counterclockwise（逆时针）。"))
				return
			statement_index = program.append_statement(ProgramScript.StatementType.ROTATE)
			program.set_turn_direction(statement_index, int(ROTATION_VALUES[rotation_name]))
		_:
			diagnostics.append(_diagnostic(line_number, &"unknown_command", "未知车辆命令：'%s'。" % action))
			return
	program.set_statement_vehicle(statement_index, vehicle_id)
	statement_lines.append(line_number)

func _parse_repeat(
	program: Scene01Program,
	tokens: PackedStringArray,
	line_number: int,
	pending_repeats: Array[Dictionary],
	diagnostics: Array[Dictionary],
	statement_lines: Array[int]
) -> void:
	if tokens.size() != 3 or not tokens[1].is_valid_int() or not tokens[2].is_valid_int():
		diagnostics.append(_diagnostic(line_number, &"repeat_syntax", "repeat 需要整数次数和目标语句编号。"))
		return
	var statement_index := program.append_statement(ProgramScript.StatementType.REPEAT)
	statement_lines.append(line_number)
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
			diagnostics.append(_diagnostic(int(repeat["line"]), &"repeat_target_source_invalid", "repeat 目标必须指向之前的车辆命令。"))
			continue
		var target_type := int(program.get_statement(target_index).get("type", -1))
		if target_type != ProgramScript.StatementType.MOVE_TO and target_type != ProgramScript.StatementType.GRAB_DROP and target_type != ProgramScript.StatementType.ROTATE:
			diagnostics.append(_diagnostic(int(repeat["line"]), &"repeat_target_source_invalid", "repeat 目标必须指向之前的车辆命令。"))
			continue
		program.set_repeat(repeat_index, int(repeat["count"]), target_index)

func _diagnostic(line: int, code: StringName, message: String) -> Dictionary:
	return {"line": line, "code": code, "message": message}

func _result(program: Scene01Program, diagnostics: Array[Dictionary], statement_lines: Array[int]) -> Dictionary:
	return {"program": program, "diagnostics": diagnostics, "statement_lines": statement_lines}

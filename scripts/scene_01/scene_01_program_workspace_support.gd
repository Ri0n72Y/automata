class_name Scene01ProgramWorkspaceSupport
extends RefCounted

const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const SourceScript := preload("res://scripts/scene_01/scene_01_program_source.gd")
const SAVE_PATH := "user://scene_01_program.txt"
const HEADER := SourceScript.HEADER

var _source_codec := SourceScript.new()

func parse(source: String) -> Dictionary:
	return _source_codec.parse(source)

func repeat_options(program: Scene01Program) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if program == null:
		return result
	var statements := program.get_statements()
	for index in range(statements.size()):
		var statement: Dictionary = statements[index]
		var statement_type := int(statement.get("type", -1))
		if statement_type == ProgramScript.StatementType.REPEAT:
			result.clear()
			continue
		if statement_type != ProgramScript.StatementType.MOVE_TO and statement_type != ProgramScript.StatementType.GRAB_DROP:
			continue
		var vehicle_id := String(statement.get("vehicle_id", &""))
		var command_name := "MoveTo" if statement_type == ProgramScript.StatementType.MOVE_TO else "GrabDrop"
		var source_number := index + 1
		result.append({
			"source_number": source_number,
			"label": "#%d [%s] %s" % [source_number, vehicle_id, command_name],
		})
	return result

func save_source(source: String) -> int:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(source)
	file.close()
	return OK

func load_source() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {"ok": false, "missing": true, "error": ERR_FILE_NOT_FOUND, "source": ""}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {"ok": false, "missing": false, "error": FileAccess.get_open_error(), "source": ""}
	var source := file.get_as_text()
	file.close()
	return {"ok": true, "missing": false, "error": OK, "source": source}

func export_source(source: String) -> void:
	DisplayServer.clipboard_set(source)

func diagnostic_text(diagnostic: Dictionary) -> String:
	return "第 %d 行 · %s：%s" % [
		int(diagnostic.get("line", 0)),
		String(diagnostic.get("code", &"source_invalid")),
		String(diagnostic.get("message", "源码无效")),
	]

func reason_text(reason: StringName) -> String:
	match reason:
		&"program_capability_rejected": return "当前装配缺少程序所需能力"
		&"statements_required": return "程序至少需要一条语句"
		&"command_vehicle_required": return "命令缺少车辆"
		&"move_target_required": return "MoveTo 缺少目标格"
		&"move_target_out_of_bounds": return "MoveTo 目标超出网格"
		&"move_target_not_walkable": return "MoveTo 目标不可通行"
		&"invalid_repeat_count": return "Repeat 次数必须为 1–100"
		&"invalid_repeat_target": return "Repeat 需要指向之前的车辆命令"
		&"nested_repeat_unsupported": return "DSL v2 的 Repeat 区间不能包含另一个 Repeat"
		&"move_blocked": return "车辆移动被阻挡"
		&"no_path": return "目标没有可用路径"
		&"program_vehicle_missing": return "程序车辆不存在"
		&"lifecycle_start_rejected": return "场景当前无法开始运行"
		&"program_already_running": return "程序正在运行"
		_:
			return "GrabDrop 当前无法执行" if String(reason).begins_with("grab_drop_") else String(reason)

class_name Scene01ProgramUI
extends CanvasLayer

const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const ProgramSourceScript := preload("res://scripts/scene_01/scene_01_program_source.gd")
const RunnerScript := preload("res://scripts/scene_01/scene_01_program_runner.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const VehicleActorScript := preload("res://scripts/vehicles/vehicle_actor.gd")

const SAVE_PATH := "user://scene_01_program.txt"

@onready var _vehicle_option: OptionButton = %VehicleOption
@onready var _target_x: SpinBox = %TargetX
@onready var _target_y: SpinBox = %TargetY
@onready var _repeat_count: SpinBox = %RepeatCount
@onready var _repeat_target_option: OptionButton = %RepeatTargetOption
@onready var _source_editor: CodeEdit = %SourceEditor
@onready var _add_move_button: Button = %AddMoveButton
@onready var _add_grab_button: Button = %AddGrabButton
@onready var _add_repeat_button: Button = %AddRepeatButton
@onready var _clear_button: Button = %ClearButton
@onready var _save_button: Button = %SaveButton
@onready var _load_button: Button = %LoadButton
@onready var _export_button: Button = %ExportButton
@onready var _run_button: Button = %RunButton
@onready var _status_label: Label = %StatusLabel

var _runner: RunnerScript
var _vehicle_manager: VehicleManagerScript
var _source_codec := ProgramSourceScript.new()
var _program: Scene01Program
var _editing_enabled := true
var _suppress_source_signal := false


func _ready() -> void:
	_runner = get_parent().get_node("SceneRoot/Scene01ProgramRunner") as RunnerScript
	_vehicle_manager = get_parent().get_node("SceneRoot/RobotRoot/Scene01VehicleManager") as VehicleManagerScript
	_bind_ui()
	_bind_runner()
	call_deferred("_initialize_editor")


func _initialize_editor() -> void:
	_populate_vehicles()
	_set_source_text_internal(ProgramSourceScript.HEADER + "\n")
	_parse_current_source(false)


func get_program() -> Scene01Program:
	return _program


func get_source_text() -> String:
	return _source_editor.text if _source_editor != null else ""


func set_source_text(source: String) -> void:
	_set_source_text_internal(source)
	_parse_current_source(true)


func _bind_ui() -> void:
	_vehicle_option.item_selected.connect(_on_vehicle_selected)
	_source_editor.text_changed.connect(_on_source_changed)
	_add_move_button.pressed.connect(_on_add_move)
	_add_grab_button.pressed.connect(_on_add_grab)
	_add_repeat_button.pressed.connect(_on_add_repeat)
	_clear_button.pressed.connect(_on_clear)
	_save_button.pressed.connect(_on_save)
	_load_button.pressed.connect(_on_load)
	_export_button.pressed.connect(_on_export)
	_run_button.pressed.connect(_on_run)


func _bind_runner() -> void:
	_runner.execution_started.connect(_on_execution_started)
	_runner.statement_started.connect(_on_statement_started)
	_runner.execution_completed.connect(_on_execution_completed)
	_runner.execution_failed.connect(_on_execution_failed)
	_runner.execution_reset.connect(_on_execution_reset)


func _populate_vehicles() -> void:
	_vehicle_option.clear()
	for vehicle_node in _vehicle_manager.get_vehicles():
		var vehicle := vehicle_node as VehicleActorScript
		if vehicle == null or vehicle.definition == null:
			continue
		_vehicle_option.add_item(vehicle.definition.display_name)
		_vehicle_option.set_item_metadata(_vehicle_option.item_count - 1, vehicle.get_vehicle_id())
	if _vehicle_option.item_count > 0:
		_vehicle_option.select(0)


func _selected_vehicle_id() -> StringName:
	if _vehicle_option.item_count <= 0:
		return &""
	return StringName(_vehicle_option.get_item_metadata(_vehicle_option.selected))


func _on_vehicle_selected(_index: int) -> void:
	_status_label.text = "新增命令车辆：%s" % String(_selected_vehicle_id())


func _on_source_changed() -> void:
	if _suppress_source_signal:
		return
	_parse_current_source(true)


func _on_add_move() -> void:
	_append_source_line("[%s:moveTo] %d %d" % [
		String(_selected_vehicle_id()),
		int(_target_x.value),
		int(_target_y.value),
	])


func _on_add_grab() -> void:
	_append_source_line("[%s:grabDrop]" % String(_selected_vehicle_id()))


func _on_add_repeat() -> void:
	if _program == null or _repeat_target_option.item_count <= 0:
		_status_label.text = "Repeat 需要一个之前的车辆命令"
		return
	var target_statement := int(_repeat_target_option.get_item_metadata(_repeat_target_option.selected))
	_append_source_line("repeat %d %d" % [int(_repeat_count.value), target_statement])


func _on_clear() -> void:
	_set_source_text_internal(ProgramSourceScript.HEADER + "\n")
	_parse_current_source(false)
	_status_label.text = "源码已清空"


func _on_save() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		_status_label.text = "保存失败：%d" % FileAccess.get_open_error()
		return
	file.store_string(_source_editor.text)
	file.close()
	_status_label.text = "源码已保存"


func _on_load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_status_label.text = "没有已保存源码"
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		_status_label.text = "源码读取失败：%d" % FileAccess.get_open_error()
		return
	var source := file.get_as_text()
	file.close()
	_set_source_text_internal(source)
	_parse_current_source(true)
	if _program != null:
		_status_label.text = "源码已读取"


func _on_export() -> void:
	DisplayServer.clipboard_set(_source_editor.text)
	_status_label.text = "Blueprint 已复制到剪贴板"


func _on_run() -> void:
	var parsed := _parse_current_source(true)
	if not bool(parsed.get("ok", false)):
		return
	var snapshot := parsed.get("program") as Scene01Program
	if snapshot == null:
		_status_label.text = "源码没有生成可运行程序"
		return
	if _runner.start_program(snapshot):
		return
	if _runner.get_last_error() != &"":
		_status_label.text = "运行前拒绝：%s" % _reason_text(_runner.get_last_error())


func _on_execution_started() -> void:
	_set_editing_enabled(false)
	_status_label.text = "全局程序运行中 · 编辑器已锁定"


func _on_statement_started(statement_index: int, _statement_type: int) -> void:
	_status_label.text = "运行语句 #%d" % (statement_index + 1)


func _on_execution_completed() -> void:
	_set_editing_enabled(true)
	_parse_current_source(false)
	_status_label.text = "程序完成"


func _on_execution_failed(statement_index: int, reason: StringName) -> void:
	_set_editing_enabled(true)
	_parse_current_source(false)
	var prefix := "运行前" if statement_index < 0 else "语句 #%d" % (statement_index + 1)
	_status_label.text = "%s 失败：%s" % [prefix, _reason_text(reason)]


func _on_execution_reset() -> void:
	_set_editing_enabled(true)
	_parse_current_source(false)
	_status_label.text = "程序已重置"


func _append_source_line(line: String) -> void:
	var source := _source_editor.text
	if source.strip_edges().is_empty():
		source = ProgramSourceScript.HEADER + "\n"
	if not source.ends_with("\n"):
		source += "\n"
	source += line + "\n"
	_set_source_text_internal(source)
	_parse_current_source(false)
	_move_caret_to_end()
	_status_label.text = "已添加：%s" % line


func _set_source_text_internal(source: String) -> void:
	_suppress_source_signal = true
	_source_editor.text = source
	_suppress_source_signal = false
	_move_caret_to_end()


func _move_caret_to_end() -> void:
	if _source_editor == null:
		return
	var line_index := maxi(0, _source_editor.get_line_count() - 1)
	_source_editor.set_caret_line(line_index)
	_source_editor.set_caret_column(_source_editor.get_line(line_index).length())


func _parse_current_source(show_status: bool) -> Dictionary:
	var parsed := _source_codec.parse(_source_editor.text)
	var diagnostics: Array = parsed.get("diagnostics", [])
	if not diagnostics.is_empty():
		_program = null
		_refresh_repeat_controls()
		if show_status:
			_status_label.text = _diagnostic_text(diagnostics[0])
		return {"ok": false, "program": null, "diagnostics": diagnostics}
	_program = parsed.get("program") as Scene01Program
	_refresh_repeat_controls()
	if show_status:
		_status_label.text = "源码有效 · %d 条语句" % _statement_count(_program)
	return {"ok": _program != null, "program": _program, "diagnostics": diagnostics}


func _refresh_repeat_controls() -> void:
	_repeat_target_option.clear()
	if _program != null:
		var statements := _program.get_statements()
		for index in range(statements.size()):
			var statement: Dictionary = statements[index]
			var statement_type := int(statement.get("type", -1))
			if statement_type != ProgramScript.StatementType.MOVE_TO and statement_type != ProgramScript.StatementType.GRAB_DROP:
				continue
			var vehicle_id := String(statement.get("vehicle_id", &""))
			var command_name := "MoveTo" if statement_type == ProgramScript.StatementType.MOVE_TO else "GrabDrop"
			var source_number := index + 1
			_repeat_target_option.add_item("#%d [%s] %s" % [source_number, vehicle_id, command_name])
			_repeat_target_option.set_item_metadata(_repeat_target_option.item_count - 1, source_number)
	_add_repeat_button.disabled = not _editing_enabled or _repeat_target_option.item_count <= 0
	_repeat_target_option.disabled = not _editing_enabled or _repeat_target_option.item_count <= 0


func _statement_count(program: Scene01Program) -> int:
	return program.get_statement_count() if program != null else 0


func _set_editing_enabled(enabled: bool) -> void:
	_editing_enabled = enabled
	_vehicle_option.disabled = not enabled
	_target_x.editable = enabled
	_target_y.editable = enabled
	_repeat_count.editable = enabled
	_source_editor.editable = enabled
	_add_move_button.disabled = not enabled
	_add_grab_button.disabled = not enabled
	_clear_button.disabled = not enabled
	_save_button.disabled = not enabled
	_load_button.disabled = not enabled
	_export_button.disabled = not enabled
	_run_button.disabled = not enabled
	_refresh_repeat_controls()


func _diagnostic_text(diagnostic: Dictionary) -> String:
	return "第 %d 行 · %s：%s" % [
		int(diagnostic.get("line", 0)),
		String(diagnostic.get("code", &"source_invalid")),
		String(diagnostic.get("message", "源码无效")),
	]


func _reason_text(reason: StringName) -> String:
	match reason:
		&"program_capability_rejected": return "当前装配缺少程序所需能力"
		&"statements_required": return "程序至少需要一条语句"
		&"command_vehicle_required": return "命令缺少车辆"
		&"move_target_required": return "MoveTo 缺少目标格"
		&"move_target_out_of_bounds": return "MoveTo 目标超出网格"
		&"move_target_not_walkable": return "MoveTo 目标不可通行"
		&"invalid_repeat_count": return "Repeat 次数必须为 1–100"
		&"invalid_repeat_target": return "Repeat 需要指向之前的车辆命令"
		&"move_blocked": return "车辆移动被阻挡"
		&"no_path": return "目标没有可用路径"
		&"program_vehicle_missing": return "程序车辆不存在"
		&"lifecycle_start_rejected": return "场景当前无法开始运行"
		&"program_already_running": return "程序正在运行"
		_:
			return "GrabDrop 当前无法执行" if String(reason).begins_with("grab_drop_") else String(reason)

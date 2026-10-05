class_name Scene01ProgramUI
extends VBoxContainer

signal editing_enabled_changed(enabled: bool)

const SupportScript := preload("res://scripts/scene_01/scene_01_program_workspace_support.gd")
const SourceEditorScript := preload("res://scripts/scene_01/scene_01_program_source_editor.gd")
const RunnerScript := preload("res://scripts/scene_01/scene_01_program_runner.gd")

@onready var _source_editor: SourceEditorScript = %SourceEditor
@onready var _repeat_target_option: OptionButton = %RepeatTargetOption
@onready var _add_repeat_button: Button = %AddRepeatButton
@onready var _status_label: Label = %StatusLabel
@onready var _runner: RunnerScript = _scene_host().get_node("SceneRoot/Scene01ProgramRunner") as RunnerScript

var _support := SupportScript.new()
var _program: Scene01Program
var _statement_lines: Array[int] = []
var _editing_enabled := true


func _ready() -> void:
	_bind_ui()
	_bind_runner()
	call_deferred("_initialize_editor")


func _initialize_editor() -> void:
	_parse_current_source(false)


func get_program() -> Scene01Program:
	return _program.duplicate_program() if _program != null else null


func get_source_text() -> String:
	return _source_editor.text


func set_source_text(source: String) -> void:
	_set_source_text_internal(source)
	_parse_current_source(true)


func insert_statement(statement: String) -> void:
	if not _editing_enabled:
		return
	_source_editor.insert_statement_line(statement)
	_parse_current_source(false)
	_status_label.text = "已插入：%s" % statement


func focus_source_editor() -> void:
	_source_editor.grab_focus()


func _bind_ui() -> void:
	_source_editor.program_text_changed.connect(func(): _parse_current_source(true))
	_add_repeat_button.pressed.connect(_on_add_repeat)
	%ClearButton.pressed.connect(_on_clear)
	%SaveButton.pressed.connect(_on_save)
	%LoadButton.pressed.connect(_on_load)
	%ExportButton.pressed.connect(_on_export)
	%RunButton.pressed.connect(_on_run)


func _bind_runner() -> void:
	_runner.execution_started.connect(_on_execution_started)
	_runner.statement_started.connect(_on_statement_started)
	_runner.execution_completed.connect(_on_execution_completed)
	_runner.execution_failed.connect(_on_execution_failed)
	_runner.execution_reset.connect(_on_execution_reset)


func _on_add_repeat() -> void:
	if _program == null or _repeat_target_option.item_count <= 0:
		_status_label.text = "重复命令需要一个之前的车辆命令"
		return
	insert_statement("repeat %d %d" % [
		int(%RepeatCount.value),
		int(_repeat_target_option.get_item_metadata(_repeat_target_option.selected)),
	])


func _on_clear() -> void:
	_set_source_text_internal(SupportScript.HEADER + "\n")
	_parse_current_source(false)
	_status_label.text = "源码已清空"


func _on_save() -> void:
	var result := _support.save_source(_source_editor.text)
	_status_label.text = "源码已保存" if result == OK else "保存失败：%d" % result


func _on_load() -> void:
	var loaded := _support.load_source()
	if not bool(loaded.get("ok", false)):
		_status_label.text = "没有已保存源码" if bool(loaded.get("missing", false)) else "源码读取失败：%d" % int(loaded.get("error", FAILED))
		return
	_set_source_text_internal(String(loaded.get("source", "")))
	_parse_current_source(true)
	if _program != null:
		_status_label.text = "源码已读取"


func _on_export() -> void:
	_support.export_source(_source_editor.text)
	_status_label.text = "程序源码已复制到剪贴板"


func _on_run() -> void:
	var parsed := _parse_current_source(true)
	if bool(parsed.get("ok", false)):
		var snapshot := parsed.get("program") as Scene01Program
		if snapshot != null:
			_runner.start_program(snapshot)


func _on_execution_started() -> void:
	_set_editing_enabled(false)
	_status_label.text = "程序运行中 · 编辑器已锁定"


func _on_statement_started(statement_index: int, _statement_type: int) -> void:
	var line := _source_line(statement_index)
	_status_label.text = "运行第 %d 行" % line if line > 0 else "运行第 %d 条语句" % (statement_index + 1)


func _on_execution_completed() -> void:
	_set_editing_enabled(true)
	_parse_current_source(false)
	_status_label.text = "程序完成"


func _on_execution_failed(statement_index: int, reason: StringName) -> void:
	_set_editing_enabled(true)
	_parse_current_source(false)
	var line := _source_line(statement_index)
	var prefix := "运行前" if statement_index < 0 else ("第 %d 行" % line if line > 0 else "语句 #%d" % (statement_index + 1))
	_status_label.text = "%s 失败：%s" % [prefix, _support.reason_text(reason)]


func _on_execution_reset() -> void:
	_set_editing_enabled(true)
	_parse_current_source(false)
	_status_label.text = "程序已重置"


func _set_source_text_internal(source: String) -> void:
	_source_editor.set_program_text(source)


func _parse_current_source(show_status: bool) -> Dictionary:
	var parsed := _support.parse(_source_editor.text)
	var diagnostics: Array = parsed.get("diagnostics", [])
	_program = null if not diagnostics.is_empty() else parsed.get("program") as Scene01Program
	_statement_lines.clear()
	for value in parsed.get("statement_lines", []):
		_statement_lines.append(int(value))
	_refresh_repeat_controls()
	if show_status:
		_status_label.text = _support.diagnostic_text(diagnostics[0]) if not diagnostics.is_empty() else "语法有效 · %d 条语句" % (_program.get_statement_count() if _program != null else 0)
	return {"ok": _program != null, "program": _program, "diagnostics": diagnostics}


func _source_line(statement_index: int) -> int:
	return _statement_lines[statement_index] if statement_index >= 0 and statement_index < _statement_lines.size() else 0


func _refresh_repeat_controls() -> void:
	_repeat_target_option.clear()
	for option in _support.repeat_options(_program):
		_repeat_target_option.add_item(String(option.get("label", "")))
		_repeat_target_option.set_item_metadata(_repeat_target_option.item_count - 1, int(option.get("source_number", 0)))
	var unavailable := not _editing_enabled or _repeat_target_option.item_count <= 0
	_add_repeat_button.disabled = unavailable
	_repeat_target_option.disabled = unavailable


func _set_editing_enabled(enabled: bool) -> void:
	if _editing_enabled == enabled:
		return
	_editing_enabled = enabled
	%RepeatCount.editable = enabled
	_source_editor.editable = enabled
	for button in [%ClearButton, %SaveButton, %LoadButton, %ExportButton, %RunButton]:
		button.disabled = not enabled
	_refresh_repeat_controls()
	editing_enabled_changed.emit(enabled)


func _scene_host() -> Node:
	var cursor: Node = self
	while cursor != null:
		if cursor.has_node("SceneRoot"):
			return cursor
		cursor = cursor.get_parent()
	assert(false, "Program authoring content must live under the Scene 01 root.")
	return self

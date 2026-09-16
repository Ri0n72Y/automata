class_name Scene01ProgramUI
extends CanvasLayer

const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const SupportScript := preload("res://scripts/scene_01/scene_01_program_workspace_support.gd")
const RunnerScript := preload("res://scripts/scene_01/scene_01_program_runner.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const VehicleActorScript := preload("res://scripts/vehicles/vehicle_actor.gd")

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
var _support := SupportScript.new()
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
	_set_source_text_internal(SupportScript.HEADER + "\n")
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
	return &"" if _vehicle_option.item_count <= 0 else StringName(_vehicle_option.get_item_metadata(_vehicle_option.selected))

func _on_vehicle_selected(_index: int) -> void:
	_status_label.text = "新增命令车辆：%s" % String(_selected_vehicle_id())

func _on_source_changed() -> void:
	if not _suppress_source_signal:
		_parse_current_source(true)

func _on_add_move() -> void:
	_append_source_line("[%s:moveTo] %d %d" % [String(_selected_vehicle_id()), int(_target_x.value), int(_target_y.value)])

func _on_add_grab() -> void:
	_append_source_line("[%s:grabDrop]" % String(_selected_vehicle_id()))

func _on_add_repeat() -> void:
	if _program == null or _repeat_target_option.item_count <= 0:
		_status_label.text = "Repeat 需要一个之前的车辆命令"
		return
	_append_source_line("repeat %d %d" % [int(_repeat_count.value), int(_repeat_target_option.get_item_metadata(_repeat_target_option.selected))])

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
	_status_label.text = "Blueprint 已复制到剪贴板"

func _on_run() -> void:
	var parsed := _parse_current_source(true)
	if not bool(parsed.get("ok", false)):
		return
	var snapshot := parsed.get("program") as Scene01Program
	if snapshot != null and _runner.start_program(snapshot):
		return
	if _runner.get_last_error() != &"":
		_status_label.text = "运行前拒绝：%s" % _support.reason_text(_runner.get_last_error())

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
	_status_label.text = "%s 失败：%s" % [prefix, _support.reason_text(reason)]

func _on_execution_reset() -> void:
	_set_editing_enabled(true)
	_parse_current_source(false)
	_status_label.text = "程序已重置"

func _append_source_line(line: String) -> void:
	var source := _source_editor.text
	if source.strip_edges().is_empty():
		source = SupportScript.HEADER + "\n"
	if not source.ends_with("\n"):
		source += "\n"
	_set_source_text_internal(source + line + "\n")
	_parse_current_source(false)
	_status_label.text = "已添加：%s" % line

func _set_source_text_internal(source: String) -> void:
	_suppress_source_signal = true
	_source_editor.text = source
	_suppress_source_signal = false
	var line_index := maxi(0, _source_editor.get_line_count() - 1)
	_source_editor.set_caret_line(line_index)
	_source_editor.set_caret_column(_source_editor.get_line(line_index).length())

func _parse_current_source(show_status: bool) -> Dictionary:
	var parsed := _support.parse(_source_editor.text)
	var diagnostics: Array = parsed.get("diagnostics", [])
	_program = null if not diagnostics.is_empty() else parsed.get("program") as Scene01Program
	_refresh_repeat_controls()
	if show_status:
		_status_label.text = _support.diagnostic_text(diagnostics[0]) if not diagnostics.is_empty() else "源码有效 · %d 条语句" % (_program.get_statement_count() if _program != null else 0)
	return {"ok": _program != null, "program": _program, "diagnostics": diagnostics}

func _refresh_repeat_controls() -> void:
	_repeat_target_option.clear()
	for option in _support.repeat_options(_program):
		_repeat_target_option.add_item(String(option.get("label", "")))
		_repeat_target_option.set_item_metadata(_repeat_target_option.item_count - 1, int(option.get("source_number", 0)))
	var unavailable := not _editing_enabled or _repeat_target_option.item_count <= 0
	_add_repeat_button.disabled = unavailable
	_repeat_target_option.disabled = unavailable

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

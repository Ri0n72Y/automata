class_name Scene01ProgramUI
extends CanvasLayer
const SupportScript := preload("res://scripts/scene_01/scene_01_program_workspace_support.gd")
const RunnerScript := preload("res://scripts/scene_01/scene_01_program_runner.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const VehicleActorScript := preload("res://scripts/vehicles/vehicle_actor.gd")
const LayoutMetrics := preload("res://scripts/scene_01/scene_01_ui_layout_metrics.gd")
@onready var _program_panel: PanelContainer = %ProgramPanel
@onready var _title: Label = %ProgramTitle
@onready var _expanded_content: VBoxContainer = %ExpandedContent
@onready var _collapse_button: Button = %WorkspaceCollapseButton
@onready var _builder_scroll: ScrollContainer = %BuilderScroll
@onready var _vehicle_option: OptionButton = %VehicleOption
@onready var _repeat_target_option: OptionButton = %RepeatTargetOption
@onready var _source_editor: CodeEdit = %SourceEditor
@onready var _add_repeat_button: Button = %AddRepeatButton
@onready var _status_label: Label = %StatusLabel
@onready var _runner: RunnerScript = get_parent().get_node("SceneRoot/Scene01ProgramRunner") as RunnerScript
@onready var _vehicle_manager: VehicleManagerScript = get_parent().get_node("SceneRoot/RobotRoot/Scene01VehicleManager") as VehicleManagerScript
var _support := SupportScript.new()
var _program: Scene01Program
var _statement_lines: Array[int] = []
var _editing_enabled := true
var _suppress_source_signal := false
func _ready() -> void:
	_bind_ui()
	_bind_runner()
	get_viewport().size_changed.connect(_apply_workspace_layout)
	set_command_builder_expanded(false)
	set_workspace_collapsed(true)
	call_deferred("_initialize_editor")
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _program_panel.get_global_rect().has_point(event.position):
			get_viewport().gui_release_focus()
func _initialize_editor() -> void:
	_populate_vehicles()
	%FacingOption.clear()
	for facing in SupportScript.FACING_NAMES:
		%FacingOption.add_item(String(facing).capitalize())
	_set_source_text_internal(SupportScript.HEADER + "\n")
	_parse_current_source(false)
func get_program() -> Scene01Program:
	return _program.duplicate_program() if _program != null else null
func get_source_text() -> String:
	return _source_editor.text
func set_source_text(source: String) -> void:
	_set_source_text_internal(source)
	_parse_current_source(true)
func set_workspace_collapsed(collapsed: bool) -> void:
	_title.visible = not collapsed
	_expanded_content.visible = not collapsed
	_collapse_button.text = "P +" if collapsed else "−"
	_collapse_button.tooltip_text = "打开 PROGRAM" if collapsed else "折叠 PROGRAM"
	_apply_workspace_layout()
	if collapsed:
		get_viewport().gui_release_focus()
func set_command_builder_expanded(expanded: bool) -> void:
	_builder_scroll.visible = expanded
	%BuilderToggleButton.text = "− ADD COMMAND" if expanded else "+ ADD COMMAND"
func _apply_workspace_layout() -> void:
	var viewport_width := float(get_viewport().get_visible_rect().size.x)
	var width := LayoutMetrics.program_rail_width(viewport_width) if _expanded_content.visible else LayoutMetrics.PROGRAM_COLLAPSED_WIDTH
	_program_panel.offset_left = _program_panel.offset_right - width
func _bind_ui() -> void:
	_collapse_button.pressed.connect(func(): set_workspace_collapsed(_expanded_content.visible))
	%BuilderToggleButton.pressed.connect(func(): set_command_builder_expanded(not _builder_scroll.visible))
	_vehicle_option.item_selected.connect(func(_index): _status_label.text = "新增命令车辆：%s" % String(_selected_vehicle_id()))
	_source_editor.text_changed.connect(func(): _parse_current_source(true) if not _suppress_source_signal else null)
	%AddMoveButton.pressed.connect(_on_add_move)
	%AddFaceButton.pressed.connect(_on_add_face)
	%AddGrabButton.pressed.connect(_on_add_grab)
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
func _populate_vehicles() -> void:
	_vehicle_option.clear()
	for vehicle_node in _vehicle_manager.get_vehicles():
		var vehicle := vehicle_node as VehicleActorScript
		if vehicle != null and vehicle.definition != null:
			_vehicle_option.add_item(vehicle.definition.display_name)
			_vehicle_option.set_item_metadata(_vehicle_option.item_count - 1, vehicle.get_vehicle_id())
	if _vehicle_option.item_count > 0:
		_vehicle_option.select(0)
func _selected_vehicle_id() -> StringName:
	return &"" if _vehicle_option.item_count <= 0 else StringName(_vehicle_option.get_item_metadata(_vehicle_option.selected))
func _on_add_move() -> void:
	_append_source_line("[%s:moveTo] %d %d" % [String(_selected_vehicle_id()), int(%TargetX.value), int(%TargetY.value)])
func _on_add_face() -> void:
	_append_source_line("[%s:face] %s" % [String(_selected_vehicle_id()), String(SupportScript.FACING_NAMES[%FacingOption.selected])])
func _on_add_grab() -> void:
	_append_source_line("[%s:grabDrop]" % String(_selected_vehicle_id()))
func _on_add_repeat() -> void:
	if _program == null or _repeat_target_option.item_count <= 0:
		_status_label.text = "Repeat 需要一个之前的车辆命令"
		return
	_append_source_line("repeat %d %d" % [int(%RepeatCount.value), int(_repeat_target_option.get_item_metadata(_repeat_target_option.selected))])
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
	if bool(parsed.get("ok", false)):
		var snapshot := parsed.get("program") as Scene01Program
		if snapshot != null:
			_runner.start_program(snapshot)
func _on_execution_started() -> void:
	_set_editing_enabled(false)
	_status_label.text = "全局程序运行中 · 编辑器已锁定"
func _on_statement_started(statement_index: int, _statement_type: int) -> void:
	var line := _source_line(statement_index)
	_status_label.text = "运行第 %d 行" % line if line > 0 else "运行语句 #%d" % (statement_index + 1)
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
	_editing_enabled = enabled
	_vehicle_option.disabled = not enabled
	%FacingOption.disabled = not enabled
	%TargetX.editable = enabled
	%TargetY.editable = enabled
	%RepeatCount.editable = enabled
	_source_editor.editable = enabled
	for button in [%AddMoveButton, %AddFaceButton, %AddGrabButton, %ClearButton, %SaveButton, %LoadButton, %ExportButton, %RunButton]:
		button.disabled = not enabled
	_refresh_repeat_controls()

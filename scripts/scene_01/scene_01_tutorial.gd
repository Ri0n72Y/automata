class_name Scene01Tutorial
extends Node
signal step_changed(previous_step: int, current_step: int)
signal visibility_changed(is_visible: bool)
signal presentation_changed()
const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const RunnerScript := preload("res://scripts/scene_01/scene_01_program_runner.gd")
const ObservableScript := preload("res://scripts/scene_01/scene_01_observable_state.gd")
const CompileGateScript := preload("res://scripts/scene_01/scene_01_assembly_compile_gate.gd")
const AssemblyAdapterScript := preload("res://scripts/scene_01/scene_01_assembly_definition_adapter.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const AssemblyCapabilitiesScript := preload("res://scripts/assembly/assembly_capabilities.gd")
enum Step { SELECT_ARM, MANUAL_PICKUP, MANUAL_DROP, PROGRAM_RUN, MULTI_VEHICLE, DONE }
var _step := Step.SELECT_ARM
var _visible := true
var _manual_pickup_seen := false
var _manual_drop_seen := false
var _completed_arm_program := false
var _completed_multi_vehicle_program := false
var _run_seen_arm_move := false
var _run_seen_arm_grab := false
var _run_seen_transport_move := false
var _run_arm_grab_active := false
var _run_box_incremented := false
@onready var _observable: ObservableScript = %Scene01ObservableState
@onready var _runner: RunnerScript = %Scene01ProgramRunner
@onready var _compile_gate: CompileGateScript = %Scene01AssemblyCompileGate
@onready var _selection: Node = %VehicleSelectionController
@onready var _scene_controller: Node = get_parent().get_parent()
func _ready() -> void:
	_selection.selection_changed.connect(_on_selection_changed)
	_observable.arm_has_item_changed.connect(_on_arm_has_item_changed)
	_observable.standard_box_count_changed.connect(_on_standard_box_count_changed)
	_runner.execution_started.connect(_on_program_started)
	_runner.command_started.connect(_on_program_command_started)
	_runner.execution_completed.connect(_on_program_completed)
	_runner.execution_failed.connect(_on_program_stopped)
	_runner.execution_reset.connect(_on_program_reset)
	_scene_controller.lifecycle_reset_completed.connect(_on_lifecycle_reset_completed)
	call_deferred("_evaluate_progress")
func get_step() -> int:
	return _step
func is_visible() -> bool:
	return _visible
func skip_tutorial() -> void:
	if _visible:
		_visible = false
		visibility_changed.emit(false)
func reopen_tutorial() -> void:
	_evaluate_progress()
	if not _visible:
		_visible = true
		visibility_changed.emit(true)
	presentation_changed.emit()
func get_capability_summary() -> String:
	return "%s\n%s" % [
		_capability_line(VehicleManagerScript.ARM_VEHICLE_ID, "机械臂小车", true),
		_capability_line(VehicleManagerScript.TRANSPORT_VEHICLE_ID, "运输平台", false),
	]
func _capability_line(vehicle_id: StringName, label: String, is_arm: bool) -> String:
	var result = _compile_gate.get_compile_result(vehicle_id)
	if result == null or not result.is_success():
		return "%s：首次运行后由装配编译确认" % label
	var parts := PackedStringArray(["编译通过"])
	if result.has_capability(AssemblyCapabilitiesScript.CAN_MOVE):
		parts.append("可移动")
	if is_arm and result.has_capability(AssemblyCapabilitiesScript.GRAB_DROP):
		parts.append("可抓取")
	if not is_arm and _has_interface(result, AssemblyAdapterScript.TRAY_INTERFACE_KIND):
		parts.append("可承载")
	return "%s：%s" % [label, " / ".join(parts)]
func _has_interface(result, kind: StringName) -> bool:
	for interface_value in result.get_interaction_interfaces():
		if interface_value != null and interface_value.kind == kind:
			return true
	return false
func _on_selection_changed(_vehicle_id: StringName, _has_selection: bool) -> void:
	_evaluate_progress()
func _on_arm_has_item_changed(_previous_value: bool, current_value: bool) -> void:
	if current_value and _runner.get_state() != RunnerScript.STATE_RUNNING:
		_manual_pickup_seen = true
	_evaluate_progress()
func _on_standard_box_count_changed(previous_count: int, current_count: int) -> void:
	if current_count <= previous_count:
		return
	if _runner.get_state() == RunnerScript.STATE_RUNNING:
		if _run_arm_grab_active:
			_run_box_incremented = true
	else:
		_manual_drop_seen = true
	_evaluate_progress()
func _on_program_started() -> void:
	_clear_run_profile()
	presentation_changed.emit()
func _on_program_command_started(_statement_index: int, command_type: int, vehicle_id: StringName) -> void:
	_run_arm_grab_active = false
	if vehicle_id == VehicleManagerScript.ARM_VEHICLE_ID:
		if command_type == ProgramScript.StatementType.MOVE_TO:
			_run_seen_arm_move = true
		elif command_type == ProgramScript.StatementType.GRAB_DROP:
			_run_seen_arm_grab = true
			_run_arm_grab_active = true
	elif vehicle_id == VehicleManagerScript.TRANSPORT_VEHICLE_ID and command_type == ProgramScript.StatementType.MOVE_TO:
		_run_seen_transport_move = true
func _on_program_completed() -> void:
	var arm_delivery := _run_seen_arm_move and _run_seen_arm_grab and _run_box_incremented
	_completed_arm_program = _completed_arm_program or arm_delivery
	_completed_multi_vehicle_program = _completed_multi_vehicle_program or (arm_delivery and _run_seen_transport_move)
	_clear_run_profile()
	_evaluate_progress()
	presentation_changed.emit()
func _on_program_stopped(_statement_index: int, _reason: StringName) -> void:
	_clear_run_profile()
func _on_program_reset() -> void:
	_clear_run_profile()
func _on_lifecycle_reset_completed() -> void:
	_manual_pickup_seen = false
	_manual_drop_seen = false
	_completed_arm_program = false
	_completed_multi_vehicle_program = false
	_clear_run_profile()
	_set_step(Step.SELECT_ARM)
	presentation_changed.emit()
func _clear_run_profile() -> void:
	_run_seen_arm_move = false
	_run_seen_arm_grab = false
	_run_seen_transport_move = false
	_run_arm_grab_active = false
	_run_box_incremented = false
func _evaluate_progress() -> void:
	var next_step := _step
	while true:
		match next_step:
			Step.SELECT_ARM:
				if _selection.get_selected_vehicle_id() == VehicleManagerScript.ARM_VEHICLE_ID or _manual_pickup_seen or _manual_drop_seen:
					next_step = Step.MANUAL_PICKUP
				else: break
			Step.MANUAL_PICKUP:
				if _manual_pickup_seen or _manual_drop_seen:
					next_step = Step.MANUAL_DROP
				else: break
			Step.MANUAL_DROP:
				if _manual_drop_seen:
					next_step = Step.PROGRAM_RUN
				else: break
			Step.PROGRAM_RUN:
				if _completed_arm_program:
					next_step = Step.MULTI_VEHICLE
				else: break
			Step.MULTI_VEHICLE:
				if _completed_multi_vehicle_program:
					next_step = Step.DONE
				else: break
			_: break
	if next_step != _step:
		_set_step(next_step)
func _set_step(value: int) -> void:
	if _step == value:
		return
	var previous := _step
	_step = value
	step_changed.emit(previous, _step)
	presentation_changed.emit()

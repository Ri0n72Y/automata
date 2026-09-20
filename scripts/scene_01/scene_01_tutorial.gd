class_name Scene01Tutorial
extends Node

signal presentation_changed()

const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const RunnerScript := preload("res://scripts/scene_01/scene_01_program_runner.gd")
const ObservableScript := preload("res://scripts/scene_01/scene_01_observable_state.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")

enum Step { SELECT_ARM, MANUAL_PICKUP, MANUAL_DROP, PROGRAM_RUN, MULTI_VEHICLE, DONE }

var _view_step := Step.SELECT_ARM
var _visible := true
var _goals := {
	Step.SELECT_ARM: false,
	Step.MANUAL_PICKUP: false,
	Step.MANUAL_DROP: false,
	Step.PROGRAM_RUN: false,
	Step.MULTI_VEHICLE: false,
}
var _run_seen_arm_move := false
var _run_seen_arm_grab := false
var _run_seen_transport_move := false
var _run_arm_grab_active := false
var _run_box_incremented := false

@onready var _observable: ObservableScript = %Scene01ObservableState
@onready var _runner: RunnerScript = %Scene01ProgramRunner
@onready var _selection: Node = %VehicleSelectionController


func _ready() -> void:
	_selection.selection_changed.connect(_on_selection_changed)
	_observable.arm_has_item_changed.connect(_on_arm_has_item_changed)
	_observable.standard_box_count_changed.connect(_on_standard_box_count_changed)
	_runner.execution_started.connect(_on_program_started)
	_runner.command_started.connect(_on_program_command_started)
	_runner.execution_completed.connect(_on_program_completed)
	_runner.execution_failed.connect(_on_program_stopped)
	_runner.execution_reset.connect(_on_program_reset)


func get_step() -> int:
	return _view_step


func is_goal_complete(step: int) -> bool:
	return bool(_goals.get(step, false))


func get_completed_goal_count() -> int:
	var completed := 0
	for value in _goals.values():
		if bool(value):
			completed += 1
	return completed


func are_all_goals_complete() -> bool:
	return get_completed_goal_count() == _goals.size()


func is_visible() -> bool:
	return _visible


func skip_tutorial() -> void:
	if _visible:
		_visible = false
		presentation_changed.emit()


func reopen_tutorial() -> void:
	if not _visible:
		_visible = true
		presentation_changed.emit()


func previous_step() -> void:
	_set_view_step(maxi(_view_step - 1, Step.SELECT_ARM))


func next_step() -> void:
	if _view_step < Step.MULTI_VEHICLE:
		_set_view_step(_view_step + 1)
	elif _view_step == Step.MULTI_VEHICLE and are_all_goals_complete():
		_set_view_step(Step.DONE)


func _set_view_step(step: int) -> void:
	if step == _view_step:
		return
	_view_step = clampi(step, Step.SELECT_ARM, Step.DONE)
	presentation_changed.emit()


func _complete_goal(step: int) -> void:
	if not _goals.has(step) or bool(_goals[step]):
		return
	_goals[step] = true
	presentation_changed.emit()


func _on_selection_changed(vehicle_id: StringName, has_selection: bool) -> void:
	if has_selection and vehicle_id == VehicleManagerScript.ARM_VEHICLE_ID:
		_complete_goal(Step.SELECT_ARM)


func _on_arm_has_item_changed(_previous_value: bool, current_value: bool) -> void:
	if current_value and _runner.get_state() != RunnerScript.STATE_RUNNING:
		_complete_goal(Step.MANUAL_PICKUP)


func _on_standard_box_count_changed(previous_count: int, current_count: int) -> void:
	if current_count <= previous_count:
		return
	if _runner.get_state() == RunnerScript.STATE_RUNNING:
		if _run_arm_grab_active:
			_run_box_incremented = true
		presentation_changed.emit()
		return
	_complete_goal(Step.MANUAL_DROP)


func _on_program_started() -> void:
	_clear_run_profile()


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
	var multi_delivery := arm_delivery and _run_seen_transport_move
	_clear_run_profile()
	if arm_delivery:
		_complete_goal(Step.PROGRAM_RUN)
	if multi_delivery:
		_complete_goal(Step.MULTI_VEHICLE)


func _on_program_stopped(_statement_index: int, _reason: StringName) -> void:
	_clear_run_profile()


func _on_program_reset() -> void:
	_clear_run_profile()


func _clear_run_profile() -> void:
	_run_seen_arm_move = false
	_run_seen_arm_grab = false
	_run_seen_transport_move = false
	_run_arm_grab_active = false
	_run_box_incremented = false

class_name Scene01ScoreTracker
extends Node

signal score_changed()

const MissionControllerScript := preload("res://scripts/scene_01/scene_01_mission_controller.gd")
const LifecycleStateScript := preload("res://scripts/scene_01/scene_01_lifecycle_state.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const CompileGateScript := preload("res://scripts/scene_01/scene_01_assembly_compile_gate.gd")
const ProgramRunnerScript := preload("res://scripts/scene_01/scene_01_program_runner.gd")
const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const MoveControllerScript := preload("res://scripts/scene_01/scene_01_lifecycle_vehicle_move_controller.gd")
const GrabDropControllerScript := preload("res://scripts/scene_01/scene_01_lifecycle_grab_drop_controller.gd")
const GrabDropResultScript := preload("res://scripts/vehicles/grab_drop_result.gd")
const VehicleActorScript := preload("res://scripts/vehicles/vehicle_actor.gd")

var _scene_controller: MissionControllerScript
var _vehicle_manager: VehicleManagerScript
var _compile_gate: CompileGateScript
var _program_runner: ProgramRunnerScript
var _move_controller: MoveControllerScript
var _grab_drop_controller: GrabDropControllerScript

var _total_cost: int = 0
var _cost_captured: bool = false
var _total_actions: int = 0
var _automated_actions: int = 0
var _program_vehicle_id: StringName = &""
var _automated_move_pending: bool = false
var _automated_grab_drop_pending: bool = false


func _ready() -> void:
	_scene_controller = get_node("../..") as MissionControllerScript
	_vehicle_manager = get_node("../RobotRoot/Scene01VehicleManager") as VehicleManagerScript
	_compile_gate = get_node("../Scene01AssemblyCompileGate") as CompileGateScript
	_program_runner = get_node("../Scene01ProgramRunner") as ProgramRunnerScript
	_move_controller = get_node("../GridRoot/VehicleMoveController") as MoveControllerScript
	_grab_drop_controller = get_node("../GridRoot/VehicleGrabDropController") as GrabDropControllerScript
	call_deferred("_bind_runtime")


func get_elapsed_time() -> float:
	return _scene_controller.get_mission_elapsed_time() if _scene_controller != null else 0.0


func has_cost() -> bool:
	return _cost_captured


func get_total_cost() -> int:
	return _total_cost


func get_total_actions() -> int:
	return _total_actions


func get_automated_actions() -> int:
	return _automated_actions


func get_manual_actions() -> int:
	return _total_actions - _automated_actions


func get_automation_rate() -> float:
	if _total_actions <= 0:
		return 0.0
	return float(_automated_actions) / float(_total_actions)


func _bind_runtime() -> void:
	_scene_controller.lifecycle_state_changed.connect(_on_lifecycle_state_changed)
	_scene_controller.lifecycle_reset_completed.connect(_on_lifecycle_reset_completed)
	_scene_controller.mission_completed.connect(_on_mission_completed)
	_program_runner.execution_started.connect(_on_program_started)
	_program_runner.node_started.connect(_on_program_node_started)
	_program_runner.execution_completed.connect(_on_program_completed)
	_program_runner.execution_failed.connect(_on_program_failed)
	_program_runner.execution_reset.connect(_on_program_reset)
	_move_controller.move_accepted.connect(_on_move_accepted)
	_grab_drop_controller.grab_drop_completed.connect(_on_grab_drop_completed)
	for vehicle_node in _vehicle_manager.get_vehicles():
		var vehicle := vehicle_node as VehicleActorScript
		if vehicle != null:
			vehicle.move_completed.connect(_on_vehicle_move_completed.bind(vehicle))


func _on_lifecycle_state_changed(_previous_state: int, current_state: int) -> void:
	if current_state == LifecycleStateScript.State.RUNNING and not _cost_captured:
		_capture_cost()


func _capture_cost() -> void:
	var total := 0
	for vehicle_node in _vehicle_manager.get_vehicles():
		var vehicle := vehicle_node as VehicleActorScript
		if vehicle == null:
			continue
		var result = _compile_gate.get_compile_result(vehicle.get_vehicle_id())
		if result == null or not result.is_success():
			push_error("Scene 01 scoring requires compiled metrics for every vehicle.")
			return
		total += result.get_metrics().get_cost()
	_total_cost = total
	_cost_captured = true
	score_changed.emit()


func _on_program_started(vehicle_id: StringName) -> void:
	_program_vehicle_id = vehicle_id
	_clear_pending_program_action()


func _on_program_node_started(_node_id: int, node_type: int) -> void:
	_clear_pending_program_action()
	_automated_move_pending = node_type == ProgramScript.NodeType.MOVE_TO
	_automated_grab_drop_pending = node_type == ProgramScript.NodeType.GRAB_DROP


func _on_move_accepted(vehicle_id: StringName, target_anchor: Vector2i) -> void:
	var vehicle := _vehicle_manager.get_vehicle_by_id(vehicle_id)
	if vehicle == null or vehicle.runtime_state == null:
		return
	if vehicle.runtime_state.anchor_cell != target_anchor:
		return
	if vehicle.runtime_state.active_move_command != null:
		return
	var automated := _automated_move_pending and vehicle_id == _program_vehicle_id
	_record_action(automated)
	if automated:
		_automated_move_pending = false


func _on_vehicle_move_completed(_target_anchor: Vector2i, vehicle: VehicleActorScript) -> void:
	var automated := (
		_automated_move_pending
		and vehicle != null
		and vehicle.get_vehicle_id() == _program_vehicle_id
	)
	_record_action(automated)
	if automated:
		_automated_move_pending = false


func _on_grab_drop_completed(vehicle_id: StringName, action: int, status: int) -> void:
	var automated := _automated_grab_drop_pending and vehicle_id == _program_vehicle_id
	if status == GrabDropResultScript.Status.ACCEPTED and action != GrabDropResultScript.Action.NONE:
		_record_action(automated)
	if automated:
		_automated_grab_drop_pending = false


func _record_action(automated: bool) -> void:
	_total_actions += 1
	if automated:
		_automated_actions += 1
	score_changed.emit()


func _on_program_completed(_vehicle_id: StringName) -> void:
	_clear_program_context()


func _on_program_failed(_node_id: int, _reason: StringName) -> void:
	_clear_program_context()


func _on_program_reset() -> void:
	_clear_program_context()


func _clear_program_context() -> void:
	_program_vehicle_id = &""
	_clear_pending_program_action()


func _clear_pending_program_action() -> void:
	_automated_move_pending = false
	_automated_grab_drop_pending = false


func _on_mission_completed(_elapsed_time: float) -> void:
	score_changed.emit()


func _on_lifecycle_reset_completed() -> void:
	_total_cost = 0
	_cost_captured = false
	_total_actions = 0
	_automated_actions = 0
	_clear_program_context()
	score_changed.emit()

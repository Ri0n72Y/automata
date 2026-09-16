class_name Scene01ScoreTracker
extends Node
signal score_changed()
const LifecycleStateScript := preload("res://scripts/scene_01/scene_01_lifecycle_state.gd")
const MissionControllerScript := preload("res://scripts/scene_01/scene_01_mission_controller.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const CompileGateScript := preload("res://scripts/scene_01/scene_01_assembly_compile_gate.gd")
const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const MoveControllerScript := preload("res://scripts/scene_01/scene_01_lifecycle_vehicle_move_controller.gd")
const VehicleActorScript := preload("res://scripts/vehicles/vehicle_actor.gd")
const AssemblyAdapterScript := preload("res://scripts/scene_01/scene_01_assembly_definition_adapter.gd")
var _scene_controller: MissionControllerScript
var _vehicle_manager: VehicleManagerScript
var _compile_gate: CompileGateScript
var _program_runner: Node
var _move_controller: MoveControllerScript
var _adapter := AssemblyAdapterScript.new()
var _component_count := 0
var _components_captured := false
var _manual_runtime := 0.0
var _automated_runtime := 0.0
var _program_running := false
var _pending_program_move_vehicle_id: StringName = &""
var _manual_moving: Dictionary = {}
var _manual_started_at: Dictionary = {}
var _automated_started_at := -1.0
var _finalized := false
func _ready() -> void:
	_scene_controller = get_node("../..") as MissionControllerScript
	_vehicle_manager = get_node("../RobotRoot/Scene01VehicleManager") as VehicleManagerScript
	_compile_gate = get_node("../Scene01AssemblyCompileGate") as CompileGateScript
	_program_runner = get_node("../Scene01ProgramRunner")
	_move_controller = get_node("../GridRoot/VehicleMoveController") as MoveControllerScript
	call_deferred("_bind_runtime")
func get_elapsed_time() -> float:
	return _scene_controller.get_mission_elapsed_time() if _scene_controller != null else 0.0
func has_component_count() -> bool:
	return _components_captured
func get_component_count() -> int:
	return _component_count
func get_manual_runtime() -> float:
	var total := _manual_runtime
	var now := get_elapsed_time()
	for started_value in _manual_started_at.values():
		total += maxf(now - float(started_value), 0.0)
	return total
func get_automated_runtime() -> float:
	var total := _automated_runtime
	if _automated_started_at >= 0.0:
		total += maxf(get_elapsed_time() - _automated_started_at, 0.0)
	return total
func get_automation_rate() -> float:
	var automated := get_automated_runtime()
	var total := automated + get_manual_runtime()
	return automated / total if total > 0.0 else 0.0
func _bind_runtime() -> void:
	_scene_controller.lifecycle_state_changed.connect(_on_lifecycle_state_changed)
	_scene_controller.lifecycle_reset_completed.connect(_on_lifecycle_reset_completed)
	_scene_controller.mission_completed.connect(_on_mission_completed)
	_program_runner.execution_started.connect(_on_program_started)
	_program_runner.command_started.connect(_on_program_command_started)
	_program_runner.execution_completed.connect(_on_program_ended)
	_program_runner.execution_failed.connect(_on_program_failed)
	_program_runner.execution_reset.connect(_on_program_reset)
	_move_controller.move_accepted.connect(_on_move_accepted)
	_move_controller.move_stopped.connect(_on_move_stopped)
	for vehicle_node in _vehicle_manager.get_vehicles():
		var vehicle := vehicle_node as VehicleActorScript
		if vehicle != null:
			vehicle.move_completed.connect(_on_vehicle_move_completed.bind(vehicle))
			vehicle.move_blocked.connect(_on_vehicle_move_blocked.bind(vehicle))
func _on_lifecycle_state_changed(_previous_state: int, current_state: int) -> void:
	var now := get_elapsed_time()
	if current_state == LifecycleStateScript.State.RUNNING:
		if not _components_captured:
			_capture_component_count()
		_start_active_segments(now)
		return
	_stop_all_segments(now)
func _capture_component_count() -> void:
	var total := 0
	for vehicle_node in _vehicle_manager.get_vehicles():
		var vehicle := vehicle_node as VehicleActorScript
		if vehicle == null:
			continue
		var compile_result = _compile_gate.get_compile_result(vehicle.get_vehicle_id())
		if compile_result == null or not compile_result.is_success():
			return
		var definition = _adapter.build_definition(vehicle)
		if definition == null:
			return
		total += definition.get_components().size()
	_component_count = total
	_components_captured = true
	score_changed.emit()
func _on_move_accepted(vehicle_id: StringName, _target_anchor: Vector2i) -> void:
	if _finalized:
		return
	if vehicle_id == _pending_program_move_vehicle_id:
		_pending_program_move_vehicle_id = &""
		return
	var vehicle := _vehicle_manager.get_vehicle_by_id(vehicle_id)
	if vehicle == null or vehicle.runtime_state == null or vehicle.runtime_state.active_move_command == null:
		return
	var now := get_elapsed_time()
	if _program_running:
		_stop_automated(now)
	_manual_moving[vehicle_id] = true
	if _scene_controller.is_gameplay_running():
		_start_manual(vehicle_id, now)
func _on_move_stopped(vehicle_id: StringName) -> void:
	_finish_manual_move(vehicle_id, get_elapsed_time())
func _on_vehicle_move_completed(_target: Vector2i, vehicle: VehicleActorScript) -> void:
	if vehicle != null:
		_finish_manual_move(vehicle.get_vehicle_id(), get_elapsed_time())
func _on_vehicle_move_blocked(vehicle: VehicleActorScript) -> void:
	if vehicle != null:
		_finish_manual_move(vehicle.get_vehicle_id(), get_elapsed_time())
func _finish_manual_move(vehicle_id: StringName, now: float) -> void:
	var was_manual := _manual_moving.has(vehicle_id)
	_stop_manual(vehicle_id, now)
	_manual_moving.erase(vehicle_id)
	if was_manual and _manual_moving.is_empty() and _program_running and not _finalized and _scene_controller.is_gameplay_running():
		_start_automated(now)
func _on_program_started() -> void:
	if _finalized:
		return
	_program_running = true
	_pending_program_move_vehicle_id = &""
	if _scene_controller.is_gameplay_running() and _manual_moving.is_empty():
		_start_automated(get_elapsed_time())
func _on_program_command_started(_statement_index: int, command_type: int, vehicle_id: StringName) -> void:
	_pending_program_move_vehicle_id = vehicle_id if command_type == ProgramScript.StatementType.MOVE_TO else &""
func _on_program_ended() -> void:
	_end_program_runtime()
func _on_program_failed(_statement_index: int, _reason: StringName) -> void:
	_end_program_runtime()
func _on_program_reset() -> void:
	_end_program_runtime()
func _end_program_runtime() -> void:
	_stop_automated(get_elapsed_time())
	_program_running = false
	_pending_program_move_vehicle_id = &""
func _start_active_segments(now: float) -> void:
	if _finalized:
		return
	for vehicle_id_value in _manual_moving.keys():
		_start_manual(StringName(vehicle_id_value), now)
	if _program_running and _manual_moving.is_empty():
		_start_automated(now)
func _start_manual(vehicle_id: StringName, now: float) -> void:
	if not _manual_started_at.has(vehicle_id):
		_manual_started_at[vehicle_id] = now
func _stop_manual(vehicle_id: StringName, now: float) -> void:
	if not _manual_started_at.has(vehicle_id):
		return
	_manual_runtime += maxf(now - float(_manual_started_at[vehicle_id]), 0.0)
	_manual_started_at.erase(vehicle_id)
func _start_automated(now: float) -> void:
	if _automated_started_at < 0.0:
		_automated_started_at = now
func _stop_automated(now: float) -> void:
	if _automated_started_at < 0.0:
		return
	_automated_runtime += maxf(now - _automated_started_at, 0.0)
	_automated_started_at = -1.0
func _stop_all_segments(now: float) -> void:
	_stop_automated(now)
	for vehicle_id_value in _manual_started_at.keys():
		_stop_manual(StringName(vehicle_id_value), now)
func _on_mission_completed(elapsed_time: float) -> void:
	_stop_all_segments(elapsed_time)
	_finalized = true
	score_changed.emit()
func _on_lifecycle_reset_completed() -> void:
	_component_count = 0
	_components_captured = false
	_manual_runtime = 0.0
	_automated_runtime = 0.0
	_program_running = false
	_pending_program_move_vehicle_id = &""
	_manual_moving.clear()
	_manual_started_at.clear()
	_automated_started_at = -1.0
	_finalized = false
	score_changed.emit()

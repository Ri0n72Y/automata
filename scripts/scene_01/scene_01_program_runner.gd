class_name Scene01ProgramRunner
extends Node
signal execution_started()
signal statement_started(statement_index: int, statement_type: int)
signal command_started(statement_index: int, command_type: int, vehicle_id: StringName)
signal execution_completed()
signal execution_failed(statement_index: int, reason: StringName)
signal execution_reset()
const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const PreflightScript := preload("res://scripts/scene_01/scene_01_program_preflight.gd")
const CommandExecutorScript := preload("res://scripts/scene_01/scene_01_program_command_executor.gd")
const MissionControllerScript := preload("res://scripts/scene_01/scene_01_mission_controller.gd")
const MoveControllerScript := preload("res://scripts/scene_01/scene_01_lifecycle_vehicle_move_controller.gd")
const GrabDropControllerScript := preload("res://scripts/scene_01/scene_01_lifecycle_grab_drop_controller.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const CompileGateScript := preload("res://scripts/scene_01/scene_01_assembly_compile_gate.gd")
const STATE_IDLE := 0
const STATE_RUNNING := 1
const STATE_COMPLETED := 2
const STATE_FAILED := 3
var _preflight := PreflightScript.new()
var _command_executor := CommandExecutorScript.new()
var _scene_controller: MissionControllerScript
var _vehicle_manager: VehicleManagerScript
var _compile_gate: CompileGateScript
var _program: Scene01Program
var _state := STATE_IDLE
var _pc := 0
var _waiting_for_move := false
var _repeat_remaining: Dictionary = {}
var _requirements_vehicle_ids: Array[StringName] = []
var _last_error: StringName = &""
func _ready() -> void:
	_scene_controller = get_parent().get_parent() as MissionControllerScript
	_vehicle_manager = get_node("../RobotRoot/Scene01VehicleManager") as VehicleManagerScript
	_compile_gate = get_node("../Scene01AssemblyCompileGate") as CompileGateScript
	_command_executor.configure(
		get_node("../GridRoot/VehicleMoveController") as MoveControllerScript,
		get_node("../GridRoot/VehicleGrabDropController") as GrabDropControllerScript,
		_vehicle_manager
	)
	_command_executor.move_completed.connect(_on_move_completed)
	_command_executor.move_blocked.connect(_on_move_blocked)
	_scene_controller.lifecycle_state_changed.connect(_on_lifecycle_state_changed)
	_scene_controller.lifecycle_reset_completed.connect(_on_lifecycle_reset_completed)
func start_program(program: Scene01Program) -> bool:
	if _state == STATE_RUNNING:
		_last_error = &"program_already_running"
		return false
	var restore_baseline_on_failure := _scene_controller.is_gameplay_running()
	_clear_execution(false)
	_program = program.duplicate_program() if program != null else null
	var result := _preflight.prepare(_program, _scene_controller, _vehicle_manager, _compile_gate)
	if not bool(result.get("ok", false)):
		return _fail_start(
			StringName(result.get("reason", &"program_invalid")),
			int(result.get("statement_index", ProgramScript.NO_STATEMENT_INDEX)),
			restore_baseline_on_failure
		)
	for value in result.get("requirement_vehicle_ids", []):
		_requirements_vehicle_ids.append(StringName(value))
	if not _prepare_runtime(restore_baseline_on_failure):
		return false
	_state = STATE_RUNNING
	_pc = 0
	_last_error = &""
	execution_started.emit()
	_drain_until_wait()
	return true
func get_state() -> int:
	return _state
func get_current_statement_index() -> int:
	return _pc
func get_last_error() -> StringName:
	return _last_error
func _prepare_runtime(restore_baseline_on_failure: bool) -> bool:
	if _scene_controller.is_gameplay_running():
		if _compile_gate.prepare_scene_run():
			return true
		return _fail_start(&"program_capability_rejected", ProgramScript.NO_STATEMENT_INDEX, restore_baseline_on_failure)
	if _scene_controller.ensure_gameplay_running():
		return true
	var reason := &"lifecycle_start_rejected"
	if not _compile_gate.get_last_diagnostics().is_empty():
		reason = &"program_capability_rejected"
	return _fail_start(reason)
func _drain_until_wait() -> void:
	while _state == STATE_RUNNING and not _waiting_for_move:
		if not _scene_controller.is_gameplay_running():
			return
		if _pc >= _program.get_statement_count():
			_complete_execution()
			return
		_execute_statement()
func _execute_statement() -> void:
	var statement := _program.get_statement(_pc)
	if statement.is_empty():
		_fail_execution(_pc, &"missing_runtime_statement")
		return
	var statement_type := int(statement.get("type", -1))
	statement_started.emit(_pc, statement_type)
	if statement_type == ProgramScript.StatementType.MOVE_TO or statement_type == ProgramScript.StatementType.GRAB_DROP:
		command_started.emit(_pc, statement_type, StringName(statement.get("vehicle_id", &"")))
	match statement_type:
		ProgramScript.StatementType.MOVE_TO: _execute_move(statement)
		ProgramScript.StatementType.GRAB_DROP: _execute_grab_drop(statement)
		ProgramScript.StatementType.REPEAT: _execute_repeat(statement)
		_: _fail_execution(_pc, &"invalid_runtime_statement")
func _execute_move(statement: Dictionary) -> void:
	var result := _command_executor.execute_move(statement)
	if not bool(result.get("ok", false)):
		_fail_execution(_pc, StringName(result.get("reason", &"move_rejected")))
		return
	_waiting_for_move = bool(result.get("waiting", false))
	if not _waiting_for_move:
		_pc += 1
func _execute_grab_drop(statement: Dictionary) -> void:
	var result := _command_executor.execute_grab_drop(statement)
	if not bool(result.get("ok", false)):
		_fail_execution(_pc, StringName(result.get("reason", &"grab_drop_rejected")))
		return
	_pc += 1
func _execute_repeat(statement: Dictionary) -> void:
	var remaining := int(_repeat_remaining.get(_pc, maxi(int(statement.get("repeat_count", 1)) - 1, 0)))
	if remaining > 0:
		_repeat_remaining[_pc] = remaining - 1
		_pc = int(statement.get("repeat_target_index", ProgramScript.NO_STATEMENT_INDEX))
		return
	_repeat_remaining.erase(_pc)
	_pc += 1
func _on_move_completed() -> void:
	if _state != STATE_RUNNING or not _waiting_for_move:
		return
	_waiting_for_move = false
	_pc += 1
	call_deferred("_drain_until_wait")
func _on_move_blocked() -> void:
	if _state == STATE_RUNNING and _waiting_for_move:
		_fail_execution(_pc, &"move_blocked")
func _on_lifecycle_state_changed(_previous_state: int, _current_state: int) -> void:
	if _state == STATE_RUNNING and not _waiting_for_move and _scene_controller.is_gameplay_running():
		call_deferred("_drain_until_wait")
func _complete_execution() -> void:
	_state = STATE_COMPLETED
	_waiting_for_move = false
	_last_error = &""
	_command_executor.cancel()
	execution_completed.emit()
func _fail_start(
	reason: StringName,
	statement_index: int = ProgramScript.NO_STATEMENT_INDEX,
	restore_baseline_on_failure: bool = false
) -> bool:
	_fail_execution(statement_index, reason)
	_clear_requirements()
	if restore_baseline_on_failure:
		_restore_baseline_publication()
	return false
func _fail_execution(statement_index: int, reason: StringName) -> void:
	_state = STATE_FAILED
	_last_error = reason
	_waiting_for_move = false
	_command_executor.cancel()
	execution_failed.emit(statement_index, reason)
func _restore_baseline_publication() -> void:
	_compile_gate.clear_required_capabilities()
	if not _compile_gate.prepare_scene_run():
		push_error("Scene 01 failed to restore baseline compile publication after Program rejection.")
func _on_lifecycle_reset_completed() -> void:
	_clear_execution(true)
func _clear_execution(emit_reset: bool) -> void:
	_command_executor.cancel()
	_clear_requirements()
	_program = null
	_state = STATE_IDLE
	_pc = 0
	_waiting_for_move = false
	_repeat_remaining.clear()
	_last_error = &""
	if emit_reset:
		execution_reset.emit()
func _clear_requirements() -> void:
	for vehicle_id in _requirements_vehicle_ids:
		var empty: Array[StringName] = []
		_compile_gate.set_required_capabilities(vehicle_id, empty)
	_requirements_vehicle_ids.clear()

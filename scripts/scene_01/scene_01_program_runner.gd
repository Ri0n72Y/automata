class_name Scene01ProgramRunner
extends Node

signal execution_started(vehicle_id: StringName)
signal node_started(node_id: int, node_type: int)
signal command_started(node_id: int, node_type: int, vehicle_id: StringName)
signal execution_completed(vehicle_id: StringName)
signal execution_failed(node_id: int, reason: StringName)
signal execution_reset()

const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const PreflightScript := preload("res://scripts/scene_01/scene_01_program_preflight.gd")
const CommandExecutorScript := preload("res://scripts/scene_01/scene_01_program_command_executor.gd")
const MissionControllerScript := preload("res://scripts/scene_01/scene_01_mission_controller.gd")
const SelectionControllerScript := preload("res://scripts/input/vehicle_selection_controller.gd")
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
var _current_node_id := ProgramScript.NO_NODE_ID
var _waiting_for_move := false
var _repeat_remaining: Dictionary = {}
var _requirements_vehicle_ids: Array[StringName] = []
var _last_error: StringName = &""


func _ready() -> void:
	_scene_controller = get_parent().get_parent() as MissionControllerScript
	_vehicle_manager = get_node("../RobotRoot/Scene01VehicleManager") as VehicleManagerScript
	_compile_gate = get_node("../Scene01AssemblyCompileGate") as CompileGateScript
	_command_executor.configure(
		get_node("../GridRoot/VehicleSelectionController") as SelectionControllerScript,
		get_node("../GridRoot/VehicleMoveController") as MoveControllerScript,
		get_node("../GridRoot/VehicleGrabDropController") as GrabDropControllerScript,
		_vehicle_manager,
		_compile_gate
	)
	_command_executor.move_completed.connect(_on_move_completed)
	_command_executor.move_blocked.connect(_on_move_blocked)
	_scene_controller.lifecycle_reset_completed.connect(_on_lifecycle_reset_completed)
	set_process(false)


func start_program(program: Scene01Program) -> bool:
	if _state == STATE_RUNNING:
		_last_error = &"program_already_running"
		return false
	_clear_execution(false)
	_program = program.duplicate_program() if program != null else null
	var result := _preflight.prepare(_program, _scene_controller, _vehicle_manager, _compile_gate)
	if not bool(result.get("ok", false)):
		return _fail_start(
			StringName(result.get("reason", &"program_invalid")),
			int(result.get("node_id", ProgramScript.NO_NODE_ID))
		)
	for vehicle_value in result.get("requirement_vehicle_ids", []):
		_requirements_vehicle_ids.append(StringName(vehicle_value))
	if not _scene_controller.ensure_gameplay_running():
		return _fail_start(&"lifecycle_start_rejected")
	_state = STATE_RUNNING
	_current_node_id = _program.start_node_id
	_last_error = &""
	set_process(true)
	execution_started.emit(&"")
	return true


func get_state() -> int:
	return _state


func get_current_node_id() -> int:
	return _current_node_id


func get_last_error() -> StringName:
	return _last_error


func _process(_delta: float) -> void:
	if _state != STATE_RUNNING or _waiting_for_move or not _scene_controller.is_gameplay_running():
		return
	if _current_node_id == ProgramScript.NO_NODE_ID:
		_complete_execution()
		return
	_execute_current_node()


func _execute_current_node() -> void:
	var node := _program.get_node_data(_current_node_id)
	if node.is_empty():
		_fail_execution(_current_node_id, &"missing_runtime_node")
		return
	var node_id := _current_node_id
	var node_type := int(node.get("type", -1))
	node_started.emit(node_id, node_type)
	if node_type == ProgramScript.NodeType.MOVE_TO or node_type == ProgramScript.NodeType.GRAB_DROP:
		command_started.emit(node_id, node_type, StringName(node.get("vehicle_id", &"")))
	match node_type:
		ProgramScript.NodeType.START:
			_advance(node)
		ProgramScript.NodeType.MOVE_TO:
			_execute_move(node)
		ProgramScript.NodeType.GRAB_DROP:
			_execute_grab_drop(node)
		ProgramScript.NodeType.REPEAT:
			_execute_repeat(node)
		_:
			_fail_execution(node_id, &"invalid_runtime_node")


func _execute_move(node: Dictionary) -> void:
	var result := _command_executor.execute_move(node)
	if not bool(result.get("ok", false)):
		_fail_execution(_current_node_id, StringName(result.get("reason", &"move_rejected")))
		return
	_waiting_for_move = bool(result.get("waiting", false))
	if not _waiting_for_move:
		_advance(node)


func _execute_grab_drop(node: Dictionary) -> void:
	var result := _command_executor.execute_grab_drop(node)
	if not bool(result.get("ok", false)):
		_fail_execution(_current_node_id, StringName(result.get("reason", &"grab_drop_rejected")))
		return
	_advance(node)


func _execute_repeat(node: Dictionary) -> void:
	var node_id := int(node.get("id", ProgramScript.NO_NODE_ID))
	var remaining := int(_repeat_remaining.get(
		node_id,
		maxi(int(node.get("repeat_count", 1)) - 1, 0)
	))
	if remaining > 0:
		_repeat_remaining[node_id] = remaining - 1
		_current_node_id = int(node.get("repeat_target_id", ProgramScript.NO_NODE_ID))
		return
	_repeat_remaining.erase(node_id)
	_advance(node)


func _advance(node: Dictionary) -> void:
	_current_node_id = int(node.get("next_id", ProgramScript.NO_NODE_ID))


func _on_move_completed() -> void:
	if _state != STATE_RUNNING or not _waiting_for_move:
		return
	var node := _program.get_node_data(_current_node_id)
	if int(node.get("type", -1)) != ProgramScript.NodeType.MOVE_TO:
		_fail_execution(_current_node_id, &"unexpected_move_completion")
		return
	_waiting_for_move = false
	_advance(node)


func _on_move_blocked() -> void:
	if _state == STATE_RUNNING and _waiting_for_move:
		_fail_execution(_current_node_id, &"move_blocked")


func _complete_execution() -> void:
	_state = STATE_COMPLETED
	_waiting_for_move = false
	_last_error = &""
	set_process(false)
	_command_executor.cancel()
	execution_completed.emit(&"")


func _fail_start(reason: StringName, node_id: int = ProgramScript.NO_NODE_ID) -> bool:
	_fail_execution(node_id, reason)
	_clear_requirements()
	return false


func _fail_execution(node_id: int, reason: StringName) -> void:
	_state = STATE_FAILED
	_last_error = reason
	_waiting_for_move = false
	set_process(false)
	_command_executor.cancel()
	execution_failed.emit(node_id, reason)


func _on_lifecycle_reset_completed() -> void:
	_clear_execution(true)


func _clear_execution(emit_reset: bool) -> void:
	set_process(false)
	_command_executor.cancel()
	_clear_requirements()
	_program = null
	_state = STATE_IDLE
	_current_node_id = ProgramScript.NO_NODE_ID
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

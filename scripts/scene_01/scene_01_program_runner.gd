class_name Scene01ProgramRunner
extends Node

signal execution_started(vehicle_id: StringName)
signal node_started(node_id: int, node_type: int)
signal execution_completed(vehicle_id: StringName)
signal execution_failed(node_id: int, reason: StringName)
signal execution_reset()

const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const ValidatorScript := preload("res://scripts/scene_01/scene_01_program_validator.gd")
const MissionControllerScript := preload("res://scripts/scene_01/scene_01_mission_controller.gd")
const SelectionControllerScript := preload("res://scripts/input/vehicle_selection_controller.gd")
const MoveControllerScript := preload("res://scripts/scene_01/scene_01_lifecycle_vehicle_move_controller.gd")
const GrabDropControllerScript := preload("res://scripts/scene_01/scene_01_lifecycle_grab_drop_controller.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const CompileGateScript := preload("res://scripts/scene_01/scene_01_assembly_compile_gate.gd")
const AssemblyCapabilitiesScript := preload("res://scripts/assembly/assembly_capabilities.gd")
const GrabDropResultScript := preload("res://scripts/vehicles/grab_drop_result.gd")
const VehicleActorScript := preload("res://scripts/vehicles/vehicle_actor.gd")

const STATE_IDLE := 0
const STATE_RUNNING := 1
const STATE_COMPLETED := 2
const STATE_FAILED := 3

var _validator := ValidatorScript.new()
var _scene_controller: MissionControllerScript
var _selection_controller: SelectionControllerScript
var _move_controller: MoveControllerScript
var _grab_drop_controller: GrabDropControllerScript
var _vehicle_manager: VehicleManagerScript
var _compile_gate: CompileGateScript
var _program: Scene01Program
var _vehicle: VehicleActorScript
var _state: int = STATE_IDLE
var _current_node_id: int = ProgramScript.NO_NODE_ID
var _waiting_for_move: bool = false
var _repeat_remaining: Dictionary = {}
var _requirements_vehicle_ids: Array[StringName] = []
var _last_error: StringName = &""


func _ready() -> void:
	_scene_controller = get_parent().get_parent() as MissionControllerScript
	_selection_controller = get_node("../GridRoot/VehicleSelectionController") as SelectionControllerScript
	_move_controller = get_node("../GridRoot/VehicleMoveController") as MoveControllerScript
	_grab_drop_controller = get_node("../GridRoot/VehicleGrabDropController") as GrabDropControllerScript
	_vehicle_manager = get_node("../RobotRoot/Scene01VehicleManager") as VehicleManagerScript
	_compile_gate = get_node("../Scene01AssemblyCompileGate") as CompileGateScript
	_scene_controller.lifecycle_reset_completed.connect(_on_lifecycle_reset_completed)
	set_process(false)


func start_program(program: Scene01Program) -> bool:
	if _state == STATE_RUNNING:
		_last_error = &"program_already_running"
		return false
	_clear_execution(false)
	_program = program.duplicate_program() if program != null else null
	var diagnostics := _validator.validate(_program, _scene_controller.get_grid_size())
	if not diagnostics.is_empty():
		return _fail_start(
			StringName(diagnostics[0].get("code", &"program_invalid")),
			int(diagnostics[0].get("node_id", ProgramScript.NO_NODE_ID))
		)

	if not _configure_program_requirements():
		return false
	if not _validate_move_targets():
		return false
	if not _compile_gate.prepare_scene_run():
		return _fail_start(&"program_capability_rejected")

	if not _switch_vehicle(_program.vehicle_id):
		return _fail_start(&"program_vehicle_missing")
	if not _scene_controller.ensure_gameplay_running():
		return _fail_start(&"lifecycle_start_rejected")

	_state = STATE_RUNNING
	_current_node_id = _program.start_node_id
	_last_error = &""
	set_process(true)
	execution_started.emit(_program.vehicle_id)
	return true


func get_state() -> int:
	return _state


func get_current_node_id() -> int:
	return _current_node_id


func get_last_error() -> StringName:
	return _last_error


func _process(_delta: float) -> void:
	if _state != STATE_RUNNING or _waiting_for_move:
		return
	if not _scene_controller.is_gameplay_running():
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
	match node_type:
		ProgramScript.NodeType.START:
			_advance(int(node.get("next_id", ProgramScript.NO_NODE_ID)))
		ProgramScript.NodeType.SELECT_VEHICLE:
			_execute_select_vehicle(node)
		ProgramScript.NodeType.MOVE_TO:
			_execute_move(node)
		ProgramScript.NodeType.GRAB_DROP:
			_execute_grab_drop(node)
		ProgramScript.NodeType.REPEAT:
			_execute_repeat(node)
		_:
			_fail_execution(node_id, &"invalid_runtime_node")


func _execute_select_vehicle(node: Dictionary) -> void:
	var node_id := int(node.get("id", ProgramScript.NO_NODE_ID))
	var vehicle_id := StringName(node.get("vehicle_id", &""))
	if not _switch_vehicle(vehicle_id):
		_fail_execution(node_id, &"program_vehicle_missing")
		return
	_advance(int(node.get("next_id", ProgramScript.NO_NODE_ID)))


func _execute_move(node: Dictionary) -> void:
	var node_id := int(node.get("id", ProgramScript.NO_NODE_ID))
	if not _has_runtime_capability(AssemblyCapabilitiesScript.CAN_MOVE):
		_fail_execution(node_id, &"move_capability_missing")
		return
	if not _selection_controller.select_vehicle(_vehicle):
		_fail_execution(node_id, &"program_vehicle_selection_failed")
		return
	var target: Vector2i = node.get("target_anchor", Vector2i(-1, -1))
	if not _move_controller.request_selected_vehicle_move(target):
		var reason := _move_controller.get_last_rejection_reason()
		_fail_execution(node_id, reason if reason != &"" else &"move_rejected")
		return
	if _vehicle.runtime_state.anchor_cell == target and _vehicle.runtime_state.active_move_command == null:
		_advance(int(node.get("next_id", ProgramScript.NO_NODE_ID)))
		return
	_waiting_for_move = true


func _execute_grab_drop(node: Dictionary) -> void:
	var node_id := int(node.get("id", ProgramScript.NO_NODE_ID))
	if not _has_runtime_capability(AssemblyCapabilitiesScript.GRAB_DROP):
		_fail_execution(node_id, &"grab_drop_capability_missing")
		return
	if not _selection_controller.select_vehicle(_vehicle):
		_fail_execution(node_id, &"program_vehicle_selection_failed")
		return
	var result := _grab_drop_controller.request_selected_grab_drop() as GrabDropResultScript
	if result == null:
		_fail_execution(node_id, &"grab_drop_lifecycle_rejected")
		return
	if not result.is_success():
		_fail_execution(node_id, StringName("grab_drop_%d" % result.status))
		return
	_advance(int(node.get("next_id", ProgramScript.NO_NODE_ID)))


func _execute_repeat(node: Dictionary) -> void:
	var node_id := int(node.get("id", ProgramScript.NO_NODE_ID))
	var remaining: int
	if _repeat_remaining.has(node_id):
		remaining = int(_repeat_remaining[node_id])
	else:
		remaining = maxi(int(node.get("repeat_count", 1)) - 1, 0)
	if remaining > 0:
		_repeat_remaining[node_id] = remaining - 1
		_advance(int(node.get("repeat_target_id", ProgramScript.NO_NODE_ID)))
		return
	_repeat_remaining.erase(node_id)
	_advance(int(node.get("next_id", ProgramScript.NO_NODE_ID)))


func _advance(next_id: int) -> void:
	_current_node_id = next_id


func _on_vehicle_move_completed(_target_anchor: Vector2i) -> void:
	if _state != STATE_RUNNING or not _waiting_for_move:
		return
	var node := _program.get_node_data(_current_node_id)
	if int(node.get("type", -1)) != ProgramScript.NodeType.MOVE_TO:
		_fail_execution(_current_node_id, &"unexpected_move_completion")
		return
	_waiting_for_move = false
	_advance(int(node.get("next_id", ProgramScript.NO_NODE_ID)))


func _on_vehicle_move_blocked() -> void:
	if _state == STATE_RUNNING and _waiting_for_move:
		_fail_execution(_current_node_id, &"move_blocked")


func _on_lifecycle_reset_completed() -> void:
	_clear_execution(true)


func _configure_program_requirements() -> bool:
	var requirements := _validator.required_capabilities_by_vehicle(_program)
	for vehicle_value in requirements.keys():
		var vehicle_id := StringName(vehicle_value)
		var vehicle := _vehicle_manager.get_vehicle_by_id(vehicle_id)
		if vehicle == null or vehicle.definition == null or vehicle.runtime_state == null:
			return _fail_start(&"program_vehicle_missing")
		var required: Array[StringName] = []
		for capability_value in requirements[vehicle_value]:
			required.append(StringName(capability_value))
		_compile_gate.set_required_capabilities(vehicle_id, required)
		_requirements_vehicle_ids.append(vehicle_id)
	return true


func _validate_move_targets() -> bool:
	var current_vehicle_id := _program.vehicle_id
	for node in _ordered_nodes():
		var node_type := int(node.get("type", -1))
		if node_type == ProgramScript.NodeType.SELECT_VEHICLE:
			current_vehicle_id = StringName(node.get("vehicle_id", &""))
			continue
		if node_type != ProgramScript.NodeType.MOVE_TO:
			continue
		var vehicle := _vehicle_manager.get_vehicle_by_id(current_vehicle_id)
		if vehicle == null or vehicle.definition == null:
			return _fail_start(&"program_vehicle_missing", int(node.get("id", ProgramScript.NO_NODE_ID)))
		var target: Vector2i = node.get("target_anchor", Vector2i(-1, -1))
		if not _scene_controller.is_grid_footprint_walkable(target, vehicle.definition.footprint):
			return _fail_start(
				&"move_target_not_walkable",
				int(node.get("id", ProgramScript.NO_NODE_ID))
			)
	return true


func _ordered_nodes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var current_id := _program.start_node_id
	var visited: Dictionary = {}
	while current_id != ProgramScript.NO_NODE_ID and not visited.has(current_id):
		visited[current_id] = true
		var node := _program.get_node_data(current_id)
		if node.is_empty():
			break
		result.append(node)
		current_id = int(node.get("next_id", ProgramScript.NO_NODE_ID))
	return result


func _has_runtime_capability(capability: StringName) -> bool:
	return (
		_vehicle != null
		and _compile_gate.has_vehicle_capability(_vehicle.get_vehicle_id(), capability)
	)


func _switch_vehicle(vehicle_id: StringName) -> bool:
	var vehicle := _vehicle_manager.get_vehicle_by_id(vehicle_id)
	if vehicle == null or vehicle.definition == null or vehicle.runtime_state == null:
		return false
	if not _selection_controller.select_vehicle(vehicle):
		return false
	_bind_vehicle(vehicle)
	return true


func _bind_vehicle(vehicle: VehicleActorScript) -> void:
	_unbind_vehicle()
	_vehicle = vehicle
	_vehicle.move_completed.connect(_on_vehicle_move_completed)
	_vehicle.move_blocked.connect(_on_vehicle_move_blocked)


func _unbind_vehicle() -> void:
	if _vehicle == null or not is_instance_valid(_vehicle):
		return
	if _vehicle.move_completed.is_connected(_on_vehicle_move_completed):
		_vehicle.move_completed.disconnect(_on_vehicle_move_completed)
	if _vehicle.move_blocked.is_connected(_on_vehicle_move_blocked):
		_vehicle.move_blocked.disconnect(_on_vehicle_move_blocked)


func _complete_execution() -> void:
	var vehicle_id := _program.vehicle_id if _program != null else &""
	_state = STATE_COMPLETED
	_waiting_for_move = false
	_last_error = &""
	set_process(false)
	_unbind_vehicle()
	execution_completed.emit(vehicle_id)


func _fail_start(reason: StringName, node_id: int = ProgramScript.NO_NODE_ID) -> bool:
	_state = STATE_FAILED
	_last_error = reason
	_waiting_for_move = false
	set_process(false)
	_clear_requirements()
	execution_failed.emit(node_id, reason)
	return false


func _fail_execution(node_id: int, reason: StringName) -> void:
	_state = STATE_FAILED
	_last_error = reason
	_waiting_for_move = false
	set_process(false)
	_unbind_vehicle()
	execution_failed.emit(node_id, reason)


func _clear_execution(emit_reset: bool) -> void:
	set_process(false)
	_unbind_vehicle()
	_clear_requirements()
	_program = null
	_vehicle = null
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

class_name Scene01ProgramRunner
extends Node

signal execution_started(vehicle_id: StringName)
signal node_started(node_id: int, node_type: int)
signal node_completed(node_id: int, node_type: int)
signal execution_completed(vehicle_id: StringName)
signal execution_failed(node_id: int, reason: StringName)
signal execution_reset()

const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const ValidatorScript := preload("res://scripts/scene_01/scene_01_program_validator.gd")
const AssemblyCapabilitiesScript := preload("res://scripts/assembly/assembly_capabilities.gd")
const GrabDropResultScript := preload("res://scripts/vehicles/grab_drop_result.gd")
const VehicleActorScript := preload("res://scripts/vehicles/vehicle_actor.gd")

const STATE_IDLE := 0
const STATE_RUNNING := 1
const STATE_COMPLETED := 2
const STATE_FAILED := 3

@export var scene_controller_path: NodePath = NodePath("../..")
@export var selection_controller_path: NodePath = NodePath("../GridRoot/VehicleSelectionController")
@export var move_controller_path: NodePath = NodePath("../GridRoot/VehicleMoveController")
@export var grab_drop_controller_path: NodePath = NodePath("../GridRoot/VehicleGrabDropController")
@export var vehicle_manager_path: NodePath = NodePath("../RobotRoot/Scene01VehicleManager")
@export var compile_gate_path: NodePath = NodePath("../Scene01AssemblyCompileGate")

var _validator := ValidatorScript.new()
var _scene_controller: Node
var _selection_controller: Node
var _move_controller: Node
var _grab_drop_controller: Node
var _vehicle_manager: Node
var _compile_gate: Node
var _program: Scene01Program
var _vehicle: VehicleActorScript
var _state: int = STATE_IDLE
var _current_node_id: int = ProgramScript.NO_NODE_ID
var _waiting_for_move: bool = false
var _repeat_remaining: Dictionary = {}
var _requirements_vehicle_id: StringName = &""
var _last_error: StringName = &""


func _ready() -> void:
	_scene_controller = get_node_or_null(scene_controller_path)
	_selection_controller = get_node_or_null(selection_controller_path)
	_move_controller = get_node_or_null(move_controller_path)
	_grab_drop_controller = get_node_or_null(grab_drop_controller_path)
	_vehicle_manager = get_node_or_null(vehicle_manager_path)
	_compile_gate = get_node_or_null(compile_gate_path)
	if _scene_controller != null and _scene_controller.has_signal("lifecycle_reset_completed"):
		_scene_controller.connect("lifecycle_reset_completed", Callable(self, "_on_lifecycle_reset_completed"))
	set_process(false)


func start_program(program: Scene01Program) -> bool:
	_clear_execution(false)
	if not _has_dependencies():
		return _fail_start(&"missing_program_dependency")
	_program = program.duplicate_program() if program != null else null
	var grid_size: Vector2i = _scene_controller.call("get_grid_size")
	var diagnostics := _validator.validate(_program, grid_size)
	if not diagnostics.is_empty():
		return _fail_start(StringName(diagnostics[0].get("code", &"program_invalid")), int(diagnostics[0].get("node_id", ProgramScript.NO_NODE_ID)))

	_vehicle = _vehicle_manager.call("get_vehicle_by_id", _program.vehicle_id) as VehicleActorScript
	if _vehicle == null or _vehicle.definition == null or _vehicle.runtime_state == null:
		return _fail_start(&"program_vehicle_missing")
	if not _validate_move_targets():
		return false
	if not _selection_controller.call("select_vehicle", _vehicle):
		return _fail_start(&"program_vehicle_selection_failed")

	var required := _validator.required_capabilities(_program)
	_compile_gate.call("set_required_capabilities", _program.vehicle_id, required)
	_requirements_vehicle_id = _program.vehicle_id
	if not bool(_compile_gate.call("prepare_scene_run")):
		return _fail_start(&"program_capability_rejected")
	for capability in required:
		if not bool(_compile_gate.call("has_vehicle_capability", _program.vehicle_id, capability)):
			return _fail_start(&"program_capability_rejected")
	if not bool(_scene_controller.call("ensure_gameplay_running")):
		return _fail_start(&"lifecycle_start_rejected")

	_bind_vehicle(_vehicle)
	_state = STATE_RUNNING
	_current_node_id = _program.start_node_id
	_last_error = &""
	set_process(true)
	execution_started.emit(_program.vehicle_id)
	return true


func get_state() -> int:
	return _state


func is_running() -> bool:
	return _state == STATE_RUNNING


func get_current_node_id() -> int:
	return _current_node_id


func get_last_error() -> StringName:
	return _last_error


func reset_runner() -> void:
	_clear_execution(true)


func _process(_delta: float) -> void:
	if _state != STATE_RUNNING or _waiting_for_move:
		return
	if not bool(_scene_controller.call("is_gameplay_running")):
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
			_advance(node_id, node_type, int(node.get("next_id", ProgramScript.NO_NODE_ID)))
		ProgramScript.NodeType.MOVE_TO:
			_execute_move(node)
		ProgramScript.NodeType.GRAB_DROP:
			_execute_grab_drop(node)
		ProgramScript.NodeType.REPEAT:
			_execute_repeat(node)
		_:
			_fail_execution(node_id, &"invalid_runtime_node")


func _execute_move(node: Dictionary) -> void:
	var node_id := int(node.get("id", ProgramScript.NO_NODE_ID))
	if not _has_runtime_capability(AssemblyCapabilitiesScript.CAN_MOVE):
		_fail_execution(node_id, &"move_capability_missing")
		return
	if not _selection_controller.call("select_vehicle", _vehicle):
		_fail_execution(node_id, &"program_vehicle_selection_failed")
		return
	var target: Vector2i = node.get("target_anchor", Vector2i(-1, -1))
	if not bool(_move_controller.call("request_selected_vehicle_move", target)):
		var reason: StringName = _move_controller.call("get_last_rejection_reason")
		_fail_execution(node_id, reason if reason != &"" else &"move_rejected")
		return
	if _vehicle.runtime_state.anchor_cell == target and _vehicle.runtime_state.active_move_command == null:
		_advance(node_id, ProgramScript.NodeType.MOVE_TO, int(node.get("next_id", ProgramScript.NO_NODE_ID)))
		return
	_waiting_for_move = true


func _execute_grab_drop(node: Dictionary) -> void:
	var node_id := int(node.get("id", ProgramScript.NO_NODE_ID))
	if not _has_runtime_capability(AssemblyCapabilitiesScript.GRAB_DROP):
		_fail_execution(node_id, &"grab_drop_capability_missing")
		return
	if not _selection_controller.call("select_vehicle", _vehicle):
		_fail_execution(node_id, &"program_vehicle_selection_failed")
		return
	var result: GrabDropResultScript = _grab_drop_controller.call("request_selected_grab_drop")
	if result == null:
		_fail_execution(node_id, &"grab_drop_lifecycle_rejected")
		return
	if not result.is_success():
		_fail_execution(node_id, StringName("grab_drop_%d" % result.status))
		return
	_advance(node_id, ProgramScript.NodeType.GRAB_DROP, int(node.get("next_id", ProgramScript.NO_NODE_ID)))


func _execute_repeat(node: Dictionary) -> void:
	var node_id := int(node.get("id", ProgramScript.NO_NODE_ID))
	var remaining: int
	if _repeat_remaining.has(node_id):
		remaining = int(_repeat_remaining[node_id])
	else:
		remaining = maxi(int(node.get("repeat_count", 1)) - 1, 0)
	if remaining > 0:
		_repeat_remaining[node_id] = remaining - 1
		_advance(node_id, ProgramScript.NodeType.REPEAT, int(node.get("repeat_target_id", ProgramScript.NO_NODE_ID)))
		return
	_repeat_remaining.erase(node_id)
	_advance(node_id, ProgramScript.NodeType.REPEAT, int(node.get("next_id", ProgramScript.NO_NODE_ID)))


func _advance(node_id: int, node_type: int, next_id: int) -> void:
	node_completed.emit(node_id, node_type)
	_current_node_id = next_id


func _on_vehicle_move_completed(_target_anchor: Vector2i) -> void:
	if _state != STATE_RUNNING or not _waiting_for_move:
		return
	var node := _program.get_node_data(_current_node_id)
	if int(node.get("type", -1)) != ProgramScript.NodeType.MOVE_TO:
		_fail_execution(_current_node_id, &"unexpected_move_completion")
		return
	_waiting_for_move = false
	_advance(_current_node_id, ProgramScript.NodeType.MOVE_TO, int(node.get("next_id", ProgramScript.NO_NODE_ID)))


func _on_vehicle_move_blocked() -> void:
	if _state == STATE_RUNNING and _waiting_for_move:
		_fail_execution(_current_node_id, &"move_blocked")


func _on_lifecycle_reset_completed() -> void:
	_clear_execution(true)


func _validate_move_targets() -> bool:
	for node in _program.nodes:
		if int(node.get("type", -1)) != ProgramScript.NodeType.MOVE_TO:
			continue
		var target: Vector2i = node.get("target_anchor", Vector2i(-1, -1))
		if not bool(_scene_controller.call("is_grid_footprint_walkable", target, _vehicle.definition.footprint)):
			return _fail_start(&"move_target_not_walkable", int(node.get("id", ProgramScript.NO_NODE_ID)))
	return true


func _has_runtime_capability(capability: StringName) -> bool:
	return (
		_compile_gate != null
		and _program != null
		and bool(_compile_gate.call("has_vehicle_capability", _program.vehicle_id, capability))
	)


func _bind_vehicle(vehicle: VehicleActorScript) -> void:
	_unbind_vehicle()
	_vehicle = vehicle
	if _vehicle == null:
		return
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
	set_process(false)
	_unbind_vehicle()
	_clear_requirements()
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
	_clear_requirements()
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
	if _compile_gate != null and _requirements_vehicle_id != &"":
		var empty: Array[StringName] = []
		_compile_gate.call("set_required_capabilities", _requirements_vehicle_id, empty)
	_requirements_vehicle_id = &""


func _has_dependencies() -> bool:
	return (
		_scene_controller != null
		and _selection_controller != null
		and _move_controller != null
		and _grab_drop_controller != null
		and _vehicle_manager != null
		and _compile_gate != null
		and _scene_controller.has_method("get_grid_size")
		and _scene_controller.has_method("is_grid_footprint_walkable")
		and _scene_controller.has_method("ensure_gameplay_running")
		and _scene_controller.has_method("is_gameplay_running")
		and _selection_controller.has_method("select_vehicle")
		and _move_controller.has_method("request_selected_vehicle_move")
		and _grab_drop_controller.has_method("request_selected_grab_drop")
		and _vehicle_manager.has_method("get_vehicle_by_id")
		and _compile_gate.has_method("prepare_scene_run")
		and _compile_gate.has_method("set_required_capabilities")
		and _compile_gate.has_method("has_vehicle_capability")
	)

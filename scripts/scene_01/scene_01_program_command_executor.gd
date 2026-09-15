class_name Scene01ProgramCommandExecutor
extends RefCounted

signal move_completed()
signal move_blocked()

const SelectionControllerScript := preload("res://scripts/input/vehicle_selection_controller.gd")
const MoveControllerScript := preload("res://scripts/scene_01/scene_01_lifecycle_vehicle_move_controller.gd")
const GrabDropControllerScript := preload("res://scripts/scene_01/scene_01_lifecycle_grab_drop_controller.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const CompileGateScript := preload("res://scripts/scene_01/scene_01_assembly_compile_gate.gd")
const AssemblyCapabilitiesScript := preload("res://scripts/assembly/assembly_capabilities.gd")
const GrabDropResultScript := preload("res://scripts/vehicles/grab_drop_result.gd")
const VehicleActorScript := preload("res://scripts/vehicles/vehicle_actor.gd")

var _selection_controller: SelectionControllerScript
var _move_controller: MoveControllerScript
var _grab_drop_controller: GrabDropControllerScript
var _vehicle_manager: VehicleManagerScript
var _compile_gate: CompileGateScript
var _move_vehicle: VehicleActorScript


func configure(
	selection_controller: SelectionControllerScript,
	move_controller: MoveControllerScript,
	grab_drop_controller: GrabDropControllerScript,
	vehicle_manager: VehicleManagerScript,
	compile_gate: CompileGateScript
) -> void:
	_selection_controller = selection_controller
	_move_controller = move_controller
	_grab_drop_controller = grab_drop_controller
	_vehicle_manager = vehicle_manager
	_compile_gate = compile_gate


func execute_move(node: Dictionary) -> Dictionary:
	var vehicle := _resolve_vehicle(node)
	if vehicle == null:
		return _failure(&"program_vehicle_missing")
	if not _compile_gate.has_vehicle_capability(
		vehicle.get_vehicle_id(), AssemblyCapabilitiesScript.CAN_MOVE
	):
		return _failure(&"move_capability_missing")
	if not _selection_controller.select_vehicle(vehicle):
		return _failure(&"program_vehicle_selection_failed")
	_bind_move_vehicle(vehicle)
	var target: Vector2i = node.get("target_anchor", Vector2i(-1, -1))
	if not _move_controller.request_selected_vehicle_move(target):
		var reason := _move_controller.get_last_rejection_reason()
		cancel()
		return _failure(reason if reason != &"" else &"move_rejected")
	var waiting := not (
		vehicle.runtime_state.anchor_cell == target
		and vehicle.runtime_state.active_move_command == null
	)
	if not waiting:
		cancel()
	return {"ok": true, "waiting": waiting, "reason": &""}


func execute_grab_drop(node: Dictionary) -> Dictionary:
	var vehicle := _resolve_vehicle(node)
	if vehicle == null:
		return _failure(&"program_vehicle_missing")
	if not _compile_gate.has_vehicle_capability(
		vehicle.get_vehicle_id(), AssemblyCapabilitiesScript.GRAB_DROP
	):
		return _failure(&"grab_drop_capability_missing")
	if not _selection_controller.select_vehicle(vehicle):
		return _failure(&"program_vehicle_selection_failed")
	var result := _grab_drop_controller.request_selected_grab_drop() as GrabDropResultScript
	if result == null:
		return _failure(&"grab_drop_lifecycle_rejected")
	if not result.is_success():
		return _failure(StringName("grab_drop_%d" % result.status))
	return {"ok": true, "waiting": false, "reason": &""}


func cancel() -> void:
	if _move_vehicle == null or not is_instance_valid(_move_vehicle):
		_move_vehicle = null
		return
	if _move_vehicle.move_completed.is_connected(_on_vehicle_move_completed):
		_move_vehicle.move_completed.disconnect(_on_vehicle_move_completed)
	if _move_vehicle.move_blocked.is_connected(_on_vehicle_move_blocked):
		_move_vehicle.move_blocked.disconnect(_on_vehicle_move_blocked)
	_move_vehicle = null


func _resolve_vehicle(node: Dictionary) -> VehicleActorScript:
	var vehicle_id := StringName(node.get("vehicle_id", &""))
	var vehicle := _vehicle_manager.get_vehicle_by_id(vehicle_id) as VehicleActorScript
	if vehicle == null or vehicle.definition == null or vehicle.runtime_state == null:
		return null
	return vehicle


func _bind_move_vehicle(vehicle: VehicleActorScript) -> void:
	cancel()
	_move_vehicle = vehicle
	_move_vehicle.move_completed.connect(_on_vehicle_move_completed)
	_move_vehicle.move_blocked.connect(_on_vehicle_move_blocked)


func _on_vehicle_move_completed(_target_anchor: Vector2i) -> void:
	cancel()
	move_completed.emit()


func _on_vehicle_move_blocked() -> void:
	cancel()
	move_blocked.emit()


func _failure(reason: StringName) -> Dictionary:
	return {"ok": false, "waiting": false, "reason": reason}

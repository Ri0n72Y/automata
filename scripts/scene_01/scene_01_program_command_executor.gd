class_name Scene01ProgramCommandExecutor
extends RefCounted

signal move_completed()
signal move_blocked()
signal turn_completed()

const MoveControllerScript := preload("res://scripts/scene_01/scene_01_lifecycle_vehicle_move_controller.gd")
const GrabDropControllerScript := preload("res://scripts/scene_01/scene_01_lifecycle_grab_drop_controller.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const GrabDropResultScript := preload("res://scripts/vehicles/grab_drop_result.gd")
const VehicleActorScript := preload("res://scripts/vehicles/vehicle_actor.gd")

var _move_controller: MoveControllerScript
var _grab_drop_controller: GrabDropControllerScript
var _vehicle_manager: VehicleManagerScript
var _move_vehicle: VehicleActorScript
var _turn_vehicle: VehicleActorScript

func configure(
	move_controller: MoveControllerScript,
	grab_drop_controller: GrabDropControllerScript,
	vehicle_manager: VehicleManagerScript
) -> void:
	_move_controller = move_controller
	_grab_drop_controller = grab_drop_controller
	_vehicle_manager = vehicle_manager

func execute_move(statement: Dictionary) -> Dictionary:
	var vehicle := _resolve_vehicle(statement)
	if vehicle == null:
		return _failure(&"program_vehicle_missing")
	_bind_move_vehicle(vehicle)
	var target: Vector2i = statement.get("target_anchor", Vector2i(-1, -1))
	if not _move_controller.request_vehicle_move(vehicle, target):
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

func execute_rotate(statement: Dictionary) -> Dictionary:
	var vehicle := _resolve_vehicle(statement)
	if vehicle == null:
		return _failure(&"program_vehicle_missing")
	_bind_turn_vehicle(vehicle)
	if not _grab_drop_controller.request_vehicle_turn(vehicle, int(statement.get("turn_direction", 0))):
		cancel()
		return _failure(&"turn_rejected")
	return {"ok": true, "waiting": true, "reason": &""}

func execute_grab_drop(statement: Dictionary) -> Dictionary:
	var vehicle := _resolve_vehicle(statement)
	if vehicle == null:
		return _failure(&"program_vehicle_missing")
	var result := _grab_drop_controller.request_vehicle_grab_drop(vehicle) as GrabDropResultScript
	if result == null:
		return _failure(&"grab_drop_lifecycle_rejected")
	if not result.is_success():
		return _failure(StringName("grab_drop_%d" % result.status))
	return {"ok": true, "waiting": false, "reason": &""}

func cancel() -> void:
	if _move_vehicle != null and is_instance_valid(_move_vehicle):
		if _move_vehicle.move_completed.is_connected(_on_vehicle_move_completed):
			_move_vehicle.move_completed.disconnect(_on_vehicle_move_completed)
		if _move_vehicle.move_blocked.is_connected(_on_vehicle_move_blocked):
			_move_vehicle.move_blocked.disconnect(_on_vehicle_move_blocked)
	_move_vehicle = null
	if _turn_vehicle != null and is_instance_valid(_turn_vehicle):
		if _turn_vehicle.turn_completed.is_connected(_on_vehicle_turn_completed):
			_turn_vehicle.turn_completed.disconnect(_on_vehicle_turn_completed)
	_turn_vehicle = null

func _resolve_vehicle(statement: Dictionary) -> VehicleActorScript:
	var vehicle_id := StringName(statement.get("vehicle_id", &""))
	var vehicle := _vehicle_manager.get_vehicle_by_id(vehicle_id) as VehicleActorScript
	if vehicle == null or vehicle.definition == null or vehicle.runtime_state == null:
		return null
	return vehicle

func _bind_move_vehicle(vehicle: VehicleActorScript) -> void:
	cancel()
	_move_vehicle = vehicle
	_move_vehicle.move_completed.connect(_on_vehicle_move_completed)
	_move_vehicle.move_blocked.connect(_on_vehicle_move_blocked)

func _bind_turn_vehicle(vehicle: VehicleActorScript) -> void:
	cancel()
	_turn_vehicle = vehicle
	_turn_vehicle.turn_completed.connect(_on_vehicle_turn_completed)


func _on_vehicle_turn_completed(_facing: int) -> void:
	cancel()
	turn_completed.emit()


func _on_vehicle_move_completed(_target_anchor: Vector2i) -> void:
	cancel()
	move_completed.emit()

func _on_vehicle_move_blocked() -> void:
	cancel()
	move_blocked.emit()

func _failure(reason: StringName) -> Dictionary:
	return {"ok": false, "waiting": false, "reason": reason}

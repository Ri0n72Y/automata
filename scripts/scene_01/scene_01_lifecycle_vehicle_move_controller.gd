class_name Scene01LifecycleVehicleMoveController
extends "res://scripts/input/vehicle_move_controller.gd"

const VALIDATION_PASSTHROUGH_TOKEN := -1
const REJECTION_MOVE_BUSY := &"vehicle_busy"
const REJECTION_MOVE_NO_PATH := &"no_path"
const REJECTION_NO_MOVE_CAPABILITY := &"no_move_capability"


func _physics_process(delta: float) -> void:
	if not _is_lifecycle_running():
		return
	super._physics_process(maxf(delta, 0.0) * _get_lifecycle_speed())


func _unhandled_input(event: InputEvent) -> void:
	if _is_lifecycle_paused():
		return
	super._unhandled_input(event)


func request_selected_vehicle_move(target_anchor: Vector2i) -> bool:
	var vehicle := _get_selected_vehicle()
	if vehicle == null:
		return super.request_selected_vehicle_move(target_anchor)
	if _is_lifecycle_running():
		if not _vehicle_has_move_capability(vehicle):
			return _reject_move_preflight(vehicle, target_anchor, REJECTION_NO_MOVE_CAPABILITY)
		return super.request_selected_vehicle_move(target_anchor)

	var validation_token := _begin_gameplay_command_validation()
	if validation_token == 0:
		return false
	vehicle = _get_selected_vehicle()
	if vehicle == null:
		_cancel_gameplay_command_validation(validation_token)
		return super.request_selected_vehicle_move(target_anchor)
	var rejection_reason := _get_ready_move_preflight_rejection(vehicle, target_anchor)
	if rejection_reason != &"":
		_cancel_gameplay_command_validation(validation_token)
		return _reject_move_preflight(vehicle, target_anchor, rejection_reason)
	if not _commit_gameplay_command_validation(validation_token):
		_cancel_gameplay_command_validation(validation_token)
		return false
	return super.request_selected_vehicle_move(target_anchor)


func request_selected_vehicle_stop() -> bool:
	if not _is_lifecycle_running():
		return false
	return super.request_selected_vehicle_stop()


func can_selected_vehicle_move_after_preparation() -> bool:
	var vehicle := _get_selected_vehicle()
	if vehicle == null or vehicle.definition == null or vehicle.runtime_state == null:
		return false
	if not _vehicle_has_move_capability(vehicle):
		return false
	return (
		vehicle.runtime_state.active_move_command == null
		and vehicle.runtime_state.motion_state != VehicleRuntimeStateScript.MotionState.PLANNING
		and vehicle.runtime_state.motion_state != VehicleRuntimeStateScript.MotionState.MOVING
	)


func sync_lifecycle_state() -> void:
	_sync_live_target_mode()


func _sync_live_target_mode() -> void:
	super._sync_live_target_mode()
	if not _is_lifecycle_paused():
		return
	if grid_selection_controller != null:
		var footprint := Vector2i.ONE
		var vehicle := _get_selected_vehicle()
		if vehicle != null and vehicle.definition != null:
			footprint = vehicle.definition.footprint
		grid_selection_controller.set_live_target_mode(false, footprint)
	_hide_prediction()


func _get_ready_move_preflight_rejection(
	vehicle: VehicleActorScript,
	target_anchor: Vector2i
) -> StringName:
	if vehicle == null or vehicle.definition == null or vehicle.runtime_state == null:
		return REJECTION_MOVE_BUSY
	if not _vehicle_has_move_capability(vehicle):
		return REJECTION_NO_MOVE_CAPABILITY
	if (
		vehicle.runtime_state.active_move_command != null
		or vehicle.runtime_state.motion_state == VehicleRuntimeStateScript.MotionState.PLANNING
		or vehicle.runtime_state.motion_state == VehicleRuntimeStateScript.MotionState.MOVING
	):
		return REJECTION_MOVE_BUSY
	var path := _find_path(vehicle, target_anchor)
	if path.is_empty():
		return REJECTION_MOVE_NO_PATH
	var command := MoveCommandScript.new()
	if not command.configure(target_anchor, path):
		return REJECTION_MOVE_NO_PATH
	return &""


func _vehicle_has_move_capability(vehicle: VehicleActorScript) -> bool:
	return (
		vehicle != null
		and vehicle.definition != null
		and vehicle.definition.can_move()
	)


func _reject_move_preflight(
	vehicle: VehicleActorScript,
	target_anchor: Vector2i,
	reason: StringName
) -> bool:
	var vehicle_id: StringName = &""
	if vehicle != null:
		vehicle_id = vehicle.get_vehicle_id()
	move_requested.emit(vehicle_id, target_anchor)
	_reject(vehicle_id, target_anchor, reason)
	if reason == REJECTION_NO_MOVE_CAPABILITY:
		_hide_prediction()
	else:
		refresh_target_preview()
	return false


func _begin_gameplay_command_validation() -> int:
	if controller == null or not controller.has_method("begin_gameplay_command_validation"):
		return VALIDATION_PASSTHROUGH_TOKEN
	return int(controller.call("begin_gameplay_command_validation"))


func _commit_gameplay_command_validation(token: int) -> bool:
	if controller == null or not controller.has_method("commit_gameplay_command_validation"):
		return true
	return bool(controller.call("commit_gameplay_command_validation", token))


func _cancel_gameplay_command_validation(token: int) -> void:
	if controller == null or not controller.has_method("cancel_gameplay_command_validation"):
		return
	controller.call("cancel_gameplay_command_validation", token)


func _is_lifecycle_running() -> bool:
	if controller == null or not controller.has_method("is_gameplay_running"):
		return true
	return bool(controller.call("is_gameplay_running"))


func _is_lifecycle_paused() -> bool:
	if controller == null or not controller.has_method("is_scene_paused"):
		return false
	return bool(controller.call("is_scene_paused"))


func _get_lifecycle_speed() -> float:
	if controller == null or not controller.has_method("get_simulation_speed"):
		return 1.0
	return maxf(float(controller.call("get_simulation_speed")), 0.0)

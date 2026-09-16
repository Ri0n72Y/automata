class_name Scene01LifecycleVehicleMoveController
extends "res://scripts/input/vehicle_move_controller.gd"


func _physics_process(delta: float) -> void:
	if not _is_lifecycle_running():
		return
	super._physics_process(maxf(delta, 0.0) * _get_lifecycle_speed())


func _unhandled_input(event: InputEvent) -> void:
	if _is_lifecycle_paused():
		return
	super._unhandled_input(event)


func request_selected_vehicle_move(target_anchor: Vector2i) -> bool:
	return request_vehicle_move(_get_selected_vehicle(), target_anchor)


func request_vehicle_move(vehicle: VehicleActor, target_anchor: Vector2i) -> bool:
	var vehicle_id: StringName = &""
	if vehicle != null:
		vehicle_id = vehicle.get_vehicle_id()
	move_requested.emit(vehicle_id, target_anchor)
	if vehicle == null:
		_reject(vehicle_id, target_anchor, REJECTION_NO_VEHICLE)
		return false
	if not _ensure_gameplay_running():
		return false
	if not _vehicle_has_move_capability(vehicle):
		_reject(vehicle_id, target_anchor, REJECTION_NO_MOVE_CAPABILITY)
		_sync_live_target_mode()
		return false
	if vehicle.runtime_state == null or not vehicle.runtime_state.begin_move_planning():
		_reject(vehicle_id, target_anchor, REJECTION_BUSY)
		refresh_target_preview()
		return false

	var path := _find_path(vehicle, target_anchor)
	if path.is_empty():
		vehicle.runtime_state.fail_move_planning()
		_reject(vehicle_id, target_anchor, REJECTION_NO_PATH)
		refresh_target_preview()
		return false

	var command := MoveCommandScript.new()
	if not command.configure(target_anchor, path):
		vehicle.runtime_state.fail_move_planning()
		_reject(vehicle_id, target_anchor, REJECTION_NO_PATH)
		refresh_target_preview()
		return false

	if command.state == MoveCommandScript.State.WAITING:
		vehicle.runtime_state.clear_move_command()
		_clear_grid_target()
		_last_rejection_reason = &""
		move_accepted.emit(vehicle_id, target_anchor)
		_sync_live_target_mode()
		return true

	if not vehicle.start_move(command):
		vehicle.runtime_state.fail_move_planning()
		_reject(vehicle_id, target_anchor, REJECTION_START_FAILED)
		refresh_target_preview()
		return false

	vehicle.set_physics_process(false)
	_clear_grid_target()
	_last_rejection_reason = &""
	move_accepted.emit(vehicle_id, target_anchor)
	_face_vehicle_for_final_step(vehicle)
	return true


func request_selected_vehicle_stop() -> bool:
	if not _is_lifecycle_running():
		return false
	return super.request_selected_vehicle_stop()


func sync_lifecycle_state() -> void:
	_sync_live_target_mode()


func _sync_live_target_mode() -> void:
	super._sync_live_target_mode()
	if grid_selection_controller == null or not _is_lifecycle_paused():
		return
	var vehicle := _get_selected_vehicle()
	var footprint := Vector2i.ONE
	if vehicle != null and vehicle.definition != null:
		footprint = vehicle.definition.footprint
	grid_selection_controller.set_live_target_mode(false, footprint)
	_hide_prediction()


func _face_vehicle_for_final_step(vehicle: VehicleActor) -> void:
	if vehicle == null or vehicle.runtime_state == null:
		return
	var command = vehicle.runtime_state.active_move_command
	if command == null or command.path.size() < 2:
		return
	var step: Vector2i = command.path[command.path.size() - 1] - command.path[command.path.size() - 2]
	if step == Vector2i(1, 0):
		vehicle.runtime_state.facing = VehicleRuntimeStateScript.Facing.EAST
	elif step == Vector2i(-1, 0):
		vehicle.runtime_state.facing = VehicleRuntimeStateScript.Facing.WEST
	elif step == Vector2i(0, 1):
		vehicle.runtime_state.facing = VehicleRuntimeStateScript.Facing.SOUTH
	elif step == Vector2i(0, -1):
		vehicle.runtime_state.facing = VehicleRuntimeStateScript.Facing.NORTH
	vehicle.sync_from_state()


func _ensure_gameplay_running() -> bool:
	if controller == null or not controller.has_method("ensure_gameplay_running"):
		return false
	return bool(controller.call("ensure_gameplay_running"))


func _is_lifecycle_running() -> bool:
	if controller == null or not controller.has_method("is_gameplay_running"):
		return false
	return bool(controller.call("is_gameplay_running"))


func _is_lifecycle_paused() -> bool:
	if controller == null or not controller.has_method("is_scene_paused"):
		return true
	return bool(controller.call("is_scene_paused"))


func _get_lifecycle_speed() -> float:
	if controller == null or not controller.has_method("get_simulation_speed"):
		return 0.0
	return maxf(float(controller.call("get_simulation_speed")), 0.0)

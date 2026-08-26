class_name Scene01LifecycleVehicleMoveController
extends "res://scripts/input/vehicle_move_controller.gd"

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
	if not _ensure_gameplay_running():
		return false
	if not _vehicle_has_move_capability(vehicle):
		return _reject_no_move_capability(vehicle, target_anchor)
	return super.request_selected_vehicle_move(target_anchor)


func request_selected_vehicle_stop() -> bool:
	if not _is_lifecycle_running():
		return false
	return super.request_selected_vehicle_stop()


func sync_lifecycle_state() -> void:
	_sync_live_target_mode()


func _sync_live_target_mode() -> void:
	super._sync_live_target_mode()
	if grid_selection_controller == null:
		return
	var vehicle := _get_selected_vehicle()
	if vehicle != null and not _vehicle_has_move_capability(vehicle):
		grid_selection_controller.set_live_target_mode(false, Vector2i.ONE)
		_hide_prediction()
		return
	if not _is_lifecycle_paused():
		return
	var footprint := Vector2i.ONE
	if vehicle != null and vehicle.definition != null:
		footprint = vehicle.definition.footprint
	grid_selection_controller.set_live_target_mode(false, footprint)
	_hide_prediction()


func _vehicle_has_move_capability(vehicle: VehicleActorScript) -> bool:
	return (
		vehicle != null
		and vehicle.definition != null
		and vehicle.definition.can_move()
	)


func _reject_no_move_capability(
	vehicle: VehicleActorScript,
	target_anchor: Vector2i
) -> bool:
	var vehicle_id: StringName = vehicle.get_vehicle_id() if vehicle != null else &""
	move_requested.emit(vehicle_id, target_anchor)
	_reject(vehicle_id, target_anchor, REJECTION_NO_MOVE_CAPABILITY)
	_hide_prediction()
	return false


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

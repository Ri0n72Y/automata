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
	if not _prepare_gameplay_command():
		return false
	return super.request_selected_vehicle_move(target_anchor)


func request_selected_vehicle_stop() -> bool:
	if not _is_lifecycle_running():
		return false
	return super.request_selected_vehicle_stop()


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


func _prepare_gameplay_command() -> bool:
	if controller == null or not controller.has_method("prepare_gameplay_command"):
		return true
	return bool(controller.call("prepare_gameplay_command"))


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

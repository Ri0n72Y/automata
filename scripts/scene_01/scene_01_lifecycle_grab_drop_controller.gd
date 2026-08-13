class_name Scene01LifecycleGrabDropController
extends "res://scripts/input/vehicle_grab_drop_controller.gd"


func _unhandled_input(event: InputEvent) -> void:
	if _is_lifecycle_paused():
		return
	super._unhandled_input(event)


func request_selected_grab_drop() -> GrabDropResultScript:
	if _is_lifecycle_paused():
		return _reject_for_lifecycle_pause()
	if _get_selected_vehicle() == null:
		return super.request_selected_grab_drop()
	if not _prepare_gameplay_command_validation():
		return _reject_for_run_preparation()
	if not _can_execute_selected_grab_drop():
		return super.request_selected_grab_drop()
	if not _commit_gameplay_command_start():
		return _reject_for_run_preparation()
	return super.request_selected_grab_drop()


func rotate_selected_arm(direction: int) -> bool:
	if _is_lifecycle_paused():
		return false
	var step := clampi(direction, -1, 1)
	if step == 0 or _get_selected_vehicle() == null:
		return false
	if not _prepare_gameplay_command_validation():
		return false
	var vehicle := _get_selected_vehicle()
	if not _can_rotate(vehicle):
		return false
	if not _commit_gameplay_command_start():
		return false
	return super.rotate_selected_arm(direction)


func refresh_interaction_preview() -> void:
	if _is_lifecycle_paused():
		_hide_interaction_preview()
		return
	super.refresh_interaction_preview()


func sync_lifecycle_state() -> void:
	refresh_interaction_preview()


func _can_execute_selected_grab_drop() -> bool:
	var vehicle := _get_selected_vehicle()
	if vehicle == null or vehicle.definition == null or vehicle.runtime_state == null:
		return false
	if not vehicle.definition.has_capability(VehicleDefinitionScript.CAPABILITY_CAN_GRAB):
		return false
	if (
		vehicle.runtime_state.motion_state == VehicleRuntimeStateScript.MotionState.PLANNING
		or vehicle.runtime_state.motion_state == VehicleRuntimeStateScript.MotionState.MOVING
	):
		return false
	var target: Variant = resolve_target_for_vehicle(vehicle)
	return target != null and _is_target_ready(vehicle.runtime_state, target)


func _reject_for_lifecycle_pause() -> GrabDropResultScript:
	return _emit_lifecycle_rejection(GrabDropResultScript.Status.BUSY)


func _reject_for_run_preparation() -> GrabDropResultScript:
	return _emit_lifecycle_rejection(GrabDropResultScript.Status.BUSY)


func _emit_lifecycle_rejection(status: int) -> GrabDropResultScript:
	var vehicle := _get_selected_vehicle()
	var action := GrabDropResultScript.Action.NONE
	var vehicle_id: StringName = &""
	if vehicle != null:
		vehicle_id = vehicle.get_vehicle_id()
		if vehicle.runtime_state != null:
			action = (
				GrabDropResultScript.Action.DROP
				if vehicle.runtime_state.arm_has_item
				else GrabDropResultScript.Action.GRAB
			)
	var result := GrabDropResultScript.rejected(action, status)
	grab_drop_completed.emit(vehicle_id, result.action, result.status)
	return result


func _prepare_gameplay_command_validation() -> bool:
	var scene_controller := get_node_or_null("../../..")
	if scene_controller == null or not scene_controller.has_method(
		"prepare_gameplay_command_validation"
	):
		return true
	return bool(scene_controller.call("prepare_gameplay_command_validation"))


func _commit_gameplay_command_start() -> bool:
	var scene_controller := get_node_or_null("../../..")
	if scene_controller == null or not scene_controller.has_method(
		"commit_gameplay_command_start"
	):
		return true
	return bool(scene_controller.call("commit_gameplay_command_start"))


func _is_lifecycle_paused() -> bool:
	var scene_controller := get_node_or_null("../../..")
	if scene_controller == null or not scene_controller.has_method("is_scene_paused"):
		return false
	return bool(scene_controller.call("is_scene_paused"))

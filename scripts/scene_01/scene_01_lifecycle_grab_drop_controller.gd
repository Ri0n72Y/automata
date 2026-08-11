class_name Scene01LifecycleGrabDropController
extends "res://scripts/input/vehicle_grab_drop_controller.gd"


func _unhandled_input(event: InputEvent) -> void:
	if _is_lifecycle_paused():
		return
	super._unhandled_input(event)


func request_selected_grab_drop() -> GrabDropResultScript:
	if _prepare_gameplay_command():
		return super.request_selected_grab_drop()
	var result := GrabDropResultScript.rejected(
		GrabDropResultScript.Action.NONE,
		GrabDropResultScript.Status.BUSY
	)
	var vehicle := _get_selected_vehicle()
	var vehicle_id: StringName = &""
	if vehicle != null:
		vehicle_id = vehicle.get_vehicle_id()
	grab_drop_completed.emit(vehicle_id, result.action, result.status)
	return result


func rotate_selected_arm(direction: int) -> bool:
	if not _prepare_gameplay_command():
		return false
	return super.rotate_selected_arm(direction)


func refresh_interaction_preview() -> void:
	if _is_lifecycle_paused():
		_hide_interaction_preview()
		return
	super.refresh_interaction_preview()


func sync_lifecycle_state() -> void:
	refresh_interaction_preview()


func _prepare_gameplay_command() -> bool:
	var scene_controller := get_node_or_null("../../..")
	if scene_controller == null or not scene_controller.has_method("prepare_gameplay_command"):
		return true
	return bool(scene_controller.call("prepare_gameplay_command"))


func _is_lifecycle_paused() -> bool:
	var scene_controller := get_node_or_null("../../..")
	if scene_controller == null or not scene_controller.has_method("is_scene_paused"):
		return false
	return bool(scene_controller.call("is_scene_paused"))

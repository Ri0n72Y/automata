class_name Scene01LifecycleGrabDropController
extends "res://scripts/input/vehicle_grab_drop_controller.gd"


func _unhandled_input(event: InputEvent) -> void:
	if _is_lifecycle_paused():
		return
	super._unhandled_input(event)


func request_selected_grab_drop() -> GrabDropResultScript:
	if _is_lifecycle_paused():
		var paused_result := GrabDropResultScript.rejected(
			GrabDropResultScript.Action.NONE,
			GrabDropResultScript.Status.BUSY
		)
		var paused_vehicle := _get_selected_vehicle()
		var paused_vehicle_id: StringName = &""
		if paused_vehicle != null:
			paused_vehicle_id = paused_vehicle.get_vehicle_id()
		grab_drop_completed.emit(
			paused_vehicle_id,
			paused_result.action,
			paused_result.status
		)
		return paused_result

	var result := super.request_selected_grab_drop()
	if result.status == GrabDropResultScript.Status.ACCEPTED:
		_prepare_gameplay_command()
	return result


func rotate_selected_arm(direction: int) -> bool:
	if _is_lifecycle_paused():
		return false
	var rotated := super.rotate_selected_arm(direction)
	if rotated:
		_prepare_gameplay_command()
	return rotated


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

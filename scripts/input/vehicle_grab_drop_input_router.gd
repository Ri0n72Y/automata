class_name VehicleGrabDropInputRouter
extends Node

const VehicleGrabDropControllerScript := preload("res://scripts/input/vehicle_grab_drop_controller.gd")

@export var grab_drop_controller_path: NodePath = NodePath("../VehicleGrabDropController")
@export var grid_selection_controller_path: NodePath = NodePath("../GridSelectionController")


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if _has_command_modifier(key_event) or _is_text_input_focused() or _is_move_target_mode_active():
		return

	var controller := _get_grab_drop_controller()
	if controller == null:
		return
	if event.is_action_pressed(VehicleGrabDropControllerScript.GRAB_DROP_ACTION):
		controller.request_selected_grab_drop()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(VehicleGrabDropControllerScript.ROTATE_COUNTERCLOCKWISE_ACTION):
		if controller.rotate_selected_arm(-1):
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(VehicleGrabDropControllerScript.ROTATE_CLOCKWISE_ACTION):
		if controller.rotate_selected_arm(1):
			get_viewport().set_input_as_handled()


func _get_grab_drop_controller() -> VehicleGrabDropControllerScript:
	if grab_drop_controller_path.is_empty():
		return null
	return get_node_or_null(grab_drop_controller_path) as VehicleGrabDropControllerScript


func _is_move_target_mode_active() -> bool:
	if grid_selection_controller_path.is_empty():
		return false
	var grid_selection := get_node_or_null(grid_selection_controller_path)
	return (
		grid_selection != null
		and grid_selection.has_method("is_live_target_mode")
		and bool(grid_selection.call("is_live_target_mode"))
	)


func _has_command_modifier(event: InputEventKey) -> bool:
	return event.shift_pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed


func _is_text_input_focused() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit

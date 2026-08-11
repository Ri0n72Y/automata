class_name Scene01LifecycleGridSelectionController
extends "res://scripts/input/grid_selection_controller.gd"


func _unhandled_input(event: InputEvent) -> void:
	if _is_lifecycle_running():
		super._unhandled_input(event)
		return
	if event is InputEventMouseMotion:
		super._unhandled_input(event)
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			super._unhandled_input(event)
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
			super._unhandled_input(event)


func activate_live_target_mode() -> bool:
	if not _is_lifecycle_running():
		return false
	return super.activate_live_target_mode()


func toggle_live_target_mode() -> bool:
	if not _is_lifecycle_running():
		return false
	return super.toggle_live_target_mode()


func confirm_selection() -> bool:
	if not _is_lifecycle_running():
		return false
	return super.confirm_selection()


func primary_action_from_screen_position(screen_position: Vector2) -> bool:
	if not _is_lifecycle_running():
		return false
	return super.primary_action_from_screen_position(screen_position)


func _is_lifecycle_running() -> bool:
	if controller == null or not controller.has_method("is_gameplay_running"):
		return true
	return bool(controller.call("is_gameplay_running"))

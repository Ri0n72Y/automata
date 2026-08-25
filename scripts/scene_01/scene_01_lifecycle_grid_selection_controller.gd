class_name Scene01LifecycleGridSelectionController
extends "res://scripts/input/grid_selection_controller.gd"

const GAMEPLAY_START_ACCEPTED := &"accepted"


func _unhandled_input(event: InputEvent) -> void:
	if not _is_lifecycle_paused():
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
	if not is_live_target_available():
		return super.activate_live_target_mode()
	return _activate_live_target_mode_with_lifecycle()


func toggle_live_target_mode() -> bool:
	if is_live_target_mode() or not is_live_target_available():
		return super.toggle_live_target_mode()
	return _activate_live_target_mode_with_lifecycle()


func confirm_selection() -> bool:
	if _is_lifecycle_paused():
		return false
	return super.confirm_selection()


func primary_action_from_screen_position(screen_position: Vector2) -> bool:
	if _is_lifecycle_paused():
		return false
	return super.primary_action_from_screen_position(screen_position)


func _activate_live_target_mode_with_lifecycle() -> bool:
	var start_result := _try_start_gameplay_command(
		Callable(self, "_can_selected_vehicle_move_after_preparation")
	)
	if start_result != GAMEPLAY_START_ACCEPTED:
		return false
	return super.activate_live_target_mode()


func _can_selected_vehicle_move_after_preparation() -> bool:
	var move_controller := get_node_or_null("../VehicleMoveController")
	if move_controller == null or not move_controller.has_method(
		"can_selected_vehicle_move_after_preparation"
	):
		return false
	return bool(move_controller.call("can_selected_vehicle_move_after_preparation"))


func _try_start_gameplay_command(preflight: Callable) -> StringName:
	if controller == null or not controller.has_method("try_start_gameplay_command"):
		return &"invalid_gameplay_start"
	return StringName(controller.call("try_start_gameplay_command", preflight))


func _is_lifecycle_paused() -> bool:
	if controller == null or not controller.has_method("is_scene_paused"):
		return true
	return bool(controller.call("is_scene_paused"))

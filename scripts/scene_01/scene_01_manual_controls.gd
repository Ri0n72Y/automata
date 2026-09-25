class_name Scene01ManualControls
extends CanvasLayer

@export var scene_controller_path: NodePath = NodePath("..")


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or _is_text_input_focused():
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	var handled := false
	match key_event.keycode:
		KEY_R:
			if not _has_command_modifier(key_event):
				handled = _call_scene_action("reset_scene")
		KEY_Q:
			if _has_only_shift_modifier(key_event):
				handled = _call_scene_action("preview_rotate_grid", [1])
		KEY_E:
			if _has_only_shift_modifier(key_event):
				handled = _call_scene_action("preview_rotate_grid", [-1])
		KEY_G:
			if not _has_command_modifier(key_event):
				handled = _call_scene_action("preview_toggle_grid_offset")
		KEY_HOME:
			if not _has_command_modifier(key_event):
				handled = _call_scene_action("preview_restore_grid_transform")

	if handled:
		get_viewport().set_input_as_handled()


func _call_scene_action(method_name: StringName, args: Array = []) -> bool:
	var scene_controller := _get_scene_controller()
	if scene_controller == null or not scene_controller.has_method(method_name):
		return false
	var result: Variant = scene_controller.callv(method_name, args)
	if result is bool:
		return bool(result)
	return true


func _get_scene_controller() -> Node:
	if scene_controller_path.is_empty():
		return null
	return get_node_or_null(scene_controller_path)


func _is_text_input_focused() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit


func _has_only_shift_modifier(event: InputEventKey) -> bool:
	return (
		event.shift_pressed
		and not event.ctrl_pressed
		and not event.alt_pressed
		and not event.meta_pressed
	)


func _has_command_modifier(event: InputEventKey) -> bool:
	return event.shift_pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed

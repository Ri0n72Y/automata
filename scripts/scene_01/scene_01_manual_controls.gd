class_name Scene01ManualControls
extends CanvasLayer

@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	_update_status("Static preview ready")


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
				_on_reset_pressed()
				handled = true
		KEY_Q:
			if _has_only_shift_modifier(key_event):
				_call_scene_action("preview_rotate_grid", [1])
				_update_status("GridRoot rotated +90 degrees")
				handled = true
		KEY_E:
			if _has_only_shift_modifier(key_event):
				_call_scene_action("preview_rotate_grid", [-1])
				_update_status("GridRoot rotated -90 degrees")
				handled = true
		KEY_F:
			if not _has_command_modifier(key_event):
				_on_scale_pressed()
				handled = true
		KEY_G:
			if not _has_command_modifier(key_event):
				_on_offset_pressed()
				handled = true
		KEY_HOME:
			if not _has_command_modifier(key_event):
				_on_restore_pressed()
				handled = true

	if handled:
		get_viewport().set_input_as_handled()


func _on_reset_pressed() -> void:
	_call_scene_action("reset_scene")
	_update_status("Scene state reset")


func _on_rotate_left_pressed() -> void:
	_call_scene_action("preview_rotate_grid", [-1])
	_update_status("GridRoot rotated -90 degrees")


func _on_rotate_right_pressed() -> void:
	_call_scene_action("preview_rotate_grid", [1])
	_update_status("GridRoot rotated +90 degrees")


func _on_scale_pressed() -> void:
	_call_scene_action("preview_toggle_grid_scale")
	_update_status("GridRoot scale toggled")


func _on_offset_pressed() -> void:
	_call_scene_action("preview_toggle_grid_offset")
	_update_status("GridRoot offset toggled")


func _on_restore_pressed() -> void:
	_call_scene_action("preview_restore_grid_transform")
	_update_status("GridRoot transform restored")


func _call_scene_action(method_name: StringName, args: Array = []) -> void:
	var scene := get_tree().current_scene
	if scene == null or not scene.has_method(method_name):
		_update_status("Scene action unavailable: %s" % String(method_name))
		return
	scene.callv(method_name, args)


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


func _update_status(message: String) -> void:
	if status_label != null:
		status_label.text = message

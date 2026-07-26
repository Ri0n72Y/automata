class_name Scene01ManualControls
extends CanvasLayer

@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	_update_status("Static preview ready")


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_R:
		_on_reset_pressed()
		KEY_Q:
		_call_scene_action("preview_rotate_grid", [-1])
		KEY_E:
		_call_scene_action("preview_rotate_grid", [1])
		KEY_F:
		_on_scale_pressed()
		KEY_G:
		_on_offset_pressed()
		KEY_HOME:
		_on_restore_pressed()


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


func _update_status(message: String) -> void:
	if status_label != null:
		status_label.text = message

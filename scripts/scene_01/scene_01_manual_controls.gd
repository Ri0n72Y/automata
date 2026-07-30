class_name Scene01ManualControls
extends CanvasLayer

const COLLAPSED_SIZE := Vector2(306.0, 52.0)
const EXPANDED_SIZE := Vector2(422.0, 450.0)
const BODY_PATHS := [
	NodePath("RootControl/Panel/Margin/VBox/Instructions"),
	NodePath("RootControl/Panel/Margin/VBox/ScopeNote"),
	NodePath("RootControl/Panel/Margin/VBox/RotateRow"),
	NodePath("RootControl/Panel/Margin/VBox/TransformRow"),
	NodePath("RootControl/Panel/Margin/VBox/ResetRow"),
	NodePath("RootControl/Panel/Margin/VBox/StatusLabel"),
]

@export var start_collapsed: bool = true

@onready var panel: PanelContainer = %Panel
@onready var collapse_button: Button = %CollapseButton
@onready var status_label: Label = %StatusLabel

var _collapsed: bool = true


func _ready() -> void:
	_disable_button_focus(panel)
	set_collapsed(start_collapsed)
	_update_status("Select vehicle, press M, then left-click a target")


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


func set_collapsed(collapsed: bool) -> void:
	_collapsed = collapsed
	for path in BODY_PATHS:
		var control := get_node_or_null(path) as Control
		if control != null:
			control.visible = not _collapsed
	if collapse_button != null:
		collapse_button.text = "▶" if _collapsed else "▼"
	if panel != null:
		var target_size := COLLAPSED_SIZE if _collapsed else EXPANDED_SIZE
		panel.offset_right = panel.offset_left + target_size.x
		panel.offset_bottom = panel.offset_top + target_size.y
	if _collapsed:
		get_viewport().gui_release_focus()


func is_collapsed() -> bool:
	return _collapsed


func _on_collapse_pressed() -> void:
	set_collapsed(not _collapsed)


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


func _disable_button_focus(node: Node) -> void:
	if node is Button:
		(node as Button).focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		_disable_button_focus(child)


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

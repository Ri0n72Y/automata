class_name Scene01ManualControls
extends CanvasLayer

const COLLAPSED_HEIGHT := 52.0
const EXPANDED_HEIGHT := 280.0
const BODY_PATHS := [
	NodePath("RootControl/Panel/Margin/VBox/Instructions"),
	NodePath("RootControl/Panel/Margin/VBox/ScopeNote"),
]

@export var start_collapsed: bool = true
@export var scene_controller_path: NodePath = NodePath("..")

@onready var panel: PanelContainer = %Panel
@onready var collapse_button: Button = %CollapseButton

var _collapsed: bool = true


func _ready() -> void:
	_disable_button_focus(panel)
	get_viewport().size_changed.connect(_apply_panel_layout)
	set_collapsed(start_collapsed)


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


func set_collapsed(collapsed: bool) -> void:
	_collapsed = collapsed
	for path in BODY_PATHS:
		var control := get_node_or_null(path) as Control
		if control != null:
			control.visible = not _collapsed
	if collapse_button != null:
		collapse_button.text = "▶" if _collapsed else "▼"
	_apply_panel_layout()
	if _collapsed:
		get_viewport().gui_release_focus()


func _apply_panel_layout() -> void:
	if panel == null:
		return
	var width := clampf(float(get_viewport().get_visible_rect().size.x) * 0.2, 300.0, 360.0)
	panel.offset_right = panel.offset_left + width
	panel.offset_bottom = panel.offset_top + (COLLAPSED_HEIGHT if _collapsed else EXPANDED_HEIGHT)


func is_collapsed() -> bool:
	return _collapsed


func _on_collapse_pressed() -> void:
	set_collapsed(not _collapsed)


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

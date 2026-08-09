class_name Scene01ManualControls
extends CanvasLayer

const GrabDropResultScript := preload("res://scripts/vehicles/grab_drop_result.gd")
const VehicleRuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")

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
@export var scene_controller_path: NodePath = NodePath("..")
@export var grab_drop_controller_path: NodePath = NodePath(
	"../SceneRoot/GridRoot/VehicleGrabDropController"
)

@onready var panel: PanelContainer = %Panel
@onready var collapse_button: Button = %CollapseButton
@onready var status_label: Label = %StatusLabel

var _collapsed: bool = true


func _ready() -> void:
	_disable_button_focus(panel)
	set_collapsed(start_collapsed)
	_update_status("Select vehicle, press M, then left-click a target")
	call_deferred("_connect_grab_drop_feedback")


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


func _connect_grab_drop_feedback() -> void:
	var controller := _get_grab_drop_controller()
	if controller == null:
		return
	var completed_callable := Callable(self, "_on_grab_drop_completed")
	if controller.has_signal("grab_drop_completed") and not controller.is_connected(
		"grab_drop_completed",
		completed_callable
	):
		controller.connect("grab_drop_completed", completed_callable)
	var facing_callable := Callable(self, "_on_arm_facing_changed")
	if controller.has_signal("facing_changed") and not controller.is_connected(
		"facing_changed",
		facing_callable
	):
		controller.connect("facing_changed", facing_callable)


func _on_grab_drop_completed(_vehicle_id: StringName, action: int, status: int) -> void:
	var action_name := "Grab" if action == GrabDropResultScript.Action.GRAB else "Drop"
	if action == GrabDropResultScript.Action.NONE:
		action_name = "GrabDrop"
	if status == GrabDropResultScript.Status.ACCEPTED:
		_update_status("%s accepted" % action_name)
		return
	_update_status("%s rejected: %s" % [action_name, _grab_drop_status_text(status)])


func _on_arm_facing_changed(_vehicle_id: StringName, facing: int) -> void:
	var facing_name := "Unknown"
	match facing:
		VehicleRuntimeStateScript.Facing.NORTH:
			facing_name = "North"
		VehicleRuntimeStateScript.Facing.EAST:
			facing_name = "East"
		VehicleRuntimeStateScript.Facing.SOUTH:
			facing_name = "South"
		VehicleRuntimeStateScript.Facing.WEST:
			facing_name = "West"
	_update_status("Arm facing: %s" % facing_name)


func _grab_drop_status_text(status: int) -> String:
	match status:
		GrabDropResultScript.Status.NO_CAPABILITY:
			return "no capability"
		GrabDropResultScript.Status.BUSY:
			return "vehicle busy"
		GrabDropResultScript.Status.NO_TARGET:
			return "no compatible target"
		GrabDropResultScript.Status.EMPTY:
			return "source empty"
		GrabDropResultScript.Status.FULL:
			return "target full"
		GrabDropResultScript.Status.TYPE_MISMATCH:
			return "type mismatch"
		GrabDropResultScript.Status.ALREADY_CONTAINED:
			return "item already contained"
		GrabDropResultScript.Status.GROUND_OCCUPIED:
			return "ground occupied"
		GrabDropResultScript.Status.OWNERSHIP_CONFLICT:
			return "ownership conflict"
		_:
			return "invalid target"


func _call_scene_action(method_name: StringName, args: Array = []) -> void:
	var scene_controller := _get_scene_controller()
	if scene_controller == null or not scene_controller.has_method(method_name):
		_update_status("Scene action unavailable: %s" % String(method_name))
		return
	scene_controller.callv(method_name, args)


func _get_scene_controller() -> Node:
	if scene_controller_path.is_empty():
		return null
	return get_node_or_null(scene_controller_path)


func _get_grab_drop_controller() -> Node:
	if grab_drop_controller_path.is_empty():
		return null
	return get_node_or_null(grab_drop_controller_path)


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
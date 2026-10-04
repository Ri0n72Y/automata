class_name Scene01DebugControls
extends CanvasLayer

const COLLAPSED_SIZE := Vector2(132.0, 48.0)
const EXPANDED_SIZE := Vector2(360.0, 244.0)
const BODY_PATHS := [
	NodePath("RootControl/Panel/Margin/VBox/RotateRow"),
	NodePath("RootControl/Panel/Margin/VBox/TransformRow"),
	NodePath("RootControl/Panel/Margin/VBox/ResetRow"),
	NodePath("RootControl/Panel/Margin/VBox/ShortcutNote"),
	NodePath("RootControl/Panel/Margin/VBox/StatusLabel"),
]

@export var start_collapsed: bool = true
@export var scene_controller_path: NodePath = NodePath("..")

@onready var panel: PanelContainer = %Panel
@onready var collapse_button: Button = %CollapseButton
@onready var status_label: Label = %StatusLabel

var _collapsed: bool = true


func _ready() -> void:
	_disable_button_focus(panel)
	set_collapsed(start_collapsed)
	_update_status("调试面板已就绪")


func set_collapsed(collapsed: bool) -> void:
	_collapsed = collapsed
	for path in BODY_PATHS:
		var control := get_node_or_null(path) as Control
		if control != null:
			control.visible = not _collapsed
	if collapse_button != null:
		collapse_button.text = "+" if _collapsed else "−"
	if panel != null:
		var target_size := COLLAPSED_SIZE if _collapsed else EXPANDED_SIZE
		panel.offset_left = panel.offset_right - target_size.x
		panel.offset_bottom = panel.offset_top + target_size.y
	if _collapsed:
		get_viewport().gui_release_focus()


func is_collapsed() -> bool:
	return _collapsed


func _on_collapse_pressed() -> void:
	set_collapsed(not _collapsed)


func _on_rotate_left_pressed() -> void:
	_call_scene_action("preview_rotate_grid", [-1])
	_update_status("网格已旋转 -90°")


func _on_rotate_right_pressed() -> void:
	_call_scene_action("preview_rotate_grid", [1])
	_update_status("网格已旋转 +90°")


func _on_offset_pressed() -> void:
	_call_scene_action("preview_toggle_grid_offset")
	_update_status("网格偏移状态已切换")


func _on_reset_pressed() -> void:
	_call_scene_action("reset_scene")
	_update_status("场景状态已重置")


func _on_restore_pressed() -> void:
	_call_scene_action("preview_restore_grid_transform")
	_update_status("网格变换已恢复")


func _call_scene_action(method_name: StringName, args: Array = []) -> void:
	var scene_controller := _get_scene_controller()
	if scene_controller == null or not scene_controller.has_method(method_name):
		_update_status("场景调试操作不可用")
		return
	scene_controller.callv(method_name, args)


func _get_scene_controller() -> Node:
	if scene_controller_path.is_empty():
		return null
	return get_node_or_null(scene_controller_path)


func _disable_button_focus(node: Node) -> void:
	if node is Button:
		(node as Button).focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		_disable_button_focus(child)


func _update_status(message: String) -> void:
	if status_label != null:
		status_label.text = message

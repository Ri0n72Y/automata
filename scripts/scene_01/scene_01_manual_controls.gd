class_name Scene01ManualControls
extends CanvasLayer

const GrabDropResultScript := preload("res://scripts/vehicles/grab_drop_result.gd")
const VehicleRuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")

const COLLAPSED_SIZE := Vector2(306.0, 52.0)
const EXPANDED_SIZE := Vector2(468.0, 382.0)
const BODY_PATHS := [
	NodePath("RootControl/Panel/Margin/VBox/Instructions"),
	NodePath("RootControl/Panel/Margin/VBox/ScopeNote"),
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
	_update_status("点击顶部 ▶ 开始；选择车辆后按 M 移动，机械臂可用 A/D 转向、C 抓取或放置")
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
	var action_name := "抓取" if action == GrabDropResultScript.Action.GRAB else "放置"
	if action == GrabDropResultScript.Action.NONE:
		action_name = "机械臂操作"
	if status == GrabDropResultScript.Status.ACCEPTED:
		_update_status("%s成功" % action_name)
		return
	_update_status("%s失败：%s" % [action_name, _grab_drop_status_text(status)])


func _on_arm_facing_changed(_vehicle_id: StringName, facing: int) -> void:
	var facing_name := "未知"
	match facing:
		VehicleRuntimeStateScript.Facing.NORTH:
			facing_name = "北"
		VehicleRuntimeStateScript.Facing.EAST:
			facing_name = "东"
		VehicleRuntimeStateScript.Facing.SOUTH:
			facing_name = "南"
		VehicleRuntimeStateScript.Facing.WEST:
			facing_name = "西"
	_update_status("机械臂朝向：%s" % facing_name)


func _grab_drop_status_text(status: int) -> String:
	match status:
		GrabDropResultScript.Status.NO_CAPABILITY:
			return "当前车辆没有机械臂能力"
		GrabDropResultScript.Status.BUSY:
			return "车辆正在执行任务"
		GrabDropResultScript.Status.NO_TARGET:
			return "前方没有可交互目标，或存在多个目标"
		GrabDropResultScript.Status.EMPTY:
			return "来源为空"
		GrabDropResultScript.Status.FULL:
			return "目标已满"
		GrabDropResultScript.Status.TYPE_MISMATCH:
			return "物品类型不匹配"
		GrabDropResultScript.Status.ALREADY_CONTAINED:
			return "物品已经位于目标中"
		GrabDropResultScript.Status.GROUND_OCCUPIED:
			return "地面位置已被占用"
		GrabDropResultScript.Status.OWNERSHIP_CONFLICT:
			return "物品当前由其它容器持有"
		GrabDropResultScript.Status.RUN_PREPARATION_FAILED:
			return "运行准备失败"
		_:
			return "目标无效"


func _call_scene_action(method_name: StringName, args: Array = []) -> bool:
	var scene_controller := _get_scene_controller()
	if scene_controller == null or not scene_controller.has_method(method_name):
		return false
	scene_controller.callv(method_name, args)
	return true


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

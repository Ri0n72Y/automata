class_name Scene01LifecycleControls
extends CanvasLayer

const LifecycleStateScript := preload("res://scripts/scene_01/scene_01_lifecycle_state.gd")

@export var scene_controller_path: NodePath = NodePath("..")

@onready var run_pause_button: Button = %RunPauseButton
@onready var speed_button: Button = %SpeedButton
@onready var reset_button: Button = %ResetButton


func _ready() -> void:
	_disable_button_focus(self)
	call_deferred("_bind_scene_controller")
	call_deferred("refresh")


func refresh() -> void:
	var controller := _get_scene_controller()
	if controller == null:
		return
	var state: int = LifecycleStateScript.State.READY
	if controller.has_method("get_lifecycle_state"):
		state = int(controller.call("get_lifecycle_state"))
	if run_pause_button != null:
		run_pause_button.text = "⏸" if state == LifecycleStateScript.State.RUNNING else "▶"
		run_pause_button.tooltip_text = "暂停" if state == LifecycleStateScript.State.RUNNING else "播放 / 继续"
	if speed_button != null and controller.has_method("get_simulation_speed"):
		var speed := float(controller.call("get_simulation_speed"))
		speed_button.text = _format_speed(speed)
		speed_button.tooltip_text = "切换仿真倍速"
	if reset_button != null:
		reset_button.tooltip_text = "重置 Scene 01"


func _on_run_pause_pressed() -> void:
	var controller := _get_scene_controller()
	if controller != null and controller.has_method("toggle_run_pause"):
		controller.call("toggle_run_pause")
	refresh()


func _on_speed_pressed() -> void:
	var controller := _get_scene_controller()
	if controller != null and controller.has_method("cycle_simulation_speed"):
		controller.call("cycle_simulation_speed")
	refresh()


func _on_reset_pressed() -> void:
	var controller := _get_scene_controller()
	if controller == null or not controller.has_method("reset_scene"):
		return
	if not bool(controller.call("reset_scene")):
		return
	refresh()


func _bind_scene_controller() -> void:
	var controller := _get_scene_controller()
	if controller == null:
		return
	var state_callable := Callable(self, "_on_lifecycle_state_changed")
	if controller.has_signal("lifecycle_state_changed") and not controller.is_connected(
		"lifecycle_state_changed",
		state_callable
	):
		controller.connect("lifecycle_state_changed", state_callable)
	var speed_callable := Callable(self, "_on_simulation_speed_changed")
	if controller.has_signal("simulation_speed_changed") and not controller.is_connected(
		"simulation_speed_changed",
		speed_callable
	):
		controller.connect("simulation_speed_changed", speed_callable)
	var reset_callable := Callable(self, "_on_lifecycle_reset_completed")
	if controller.has_signal("lifecycle_reset_completed") and not controller.is_connected(
		"lifecycle_reset_completed",
		reset_callable
	):
		controller.connect("lifecycle_reset_completed", reset_callable)


func _on_lifecycle_state_changed(_previous_state: int, _current_state: int) -> void:
	refresh()


func _on_simulation_speed_changed(_previous_speed: float, _current_speed: float) -> void:
	refresh()


func _on_lifecycle_reset_completed() -> void:
	refresh()


func _get_scene_controller() -> Node:
	if scene_controller_path.is_empty():
		return null
	return get_node_or_null(scene_controller_path)


func _format_speed(speed: float) -> String:
	if is_equal_approx(speed, roundf(speed)):
		return "%d×" % int(roundf(speed))
	return "%.1f×" % speed


func _disable_button_focus(node: Node) -> void:
	if node is Button:
		(node as Button).focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		_disable_button_focus(child)

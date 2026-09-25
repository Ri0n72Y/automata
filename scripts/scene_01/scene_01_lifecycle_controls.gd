class_name Scene01LifecycleControls
extends CanvasLayer

const LifecycleStateScript := preload("res://scripts/scene_01/scene_01_lifecycle_state.gd")
const SPEED_VALUES := [0.5, 1.0, 2.0, 4.0]
const PLAY_ICON: Texture2D = preload("res://assets/ui/icons/play.svg")
const PAUSE_ICON: Texture2D = preload("res://assets/ui/icons/pause.svg")

@export var scene_controller_path: NodePath = NodePath("..")

@onready var status_dot: Label = %StatusDot
@onready var state_label: Label = %StateLabel
@onready var time_label: Label = %TimeLabel
@onready var run_pause_button: Button = %RunPauseButton
@onready var speed_option: OptionButton = %SpeedOption
@onready var reset_button: Button = %ResetButton


func _ready() -> void:
	_disable_button_focus(self)
	call_deferred("_bind_scene_controller")
	call_deferred("refresh")


func _process(_delta: float) -> void:
	_refresh_time()


func refresh() -> void:
	var controller := _get_scene_controller()
	if controller == null:
		return
	var state: int = LifecycleStateScript.State.READY
	if controller.has_method("get_lifecycle_state"):
		state = int(controller.call("get_lifecycle_state"))
	_refresh_state(state)
	_refresh_speed(controller)
	_refresh_time()
	if reset_button != null:
		reset_button.tooltip_text = "重置场景"


func _refresh_state(state: int) -> void:
	if run_pause_button != null:
		run_pause_button.icon = PAUSE_ICON if state == LifecycleStateScript.State.RUNNING else PLAY_ICON
		run_pause_button.tooltip_text = "暂停" if state == LifecycleStateScript.State.RUNNING else "播放 / 继续"

	if state_label == null or status_dot == null:
		return
	match state:
		LifecycleStateScript.State.RUNNING:
			state_label.text = "运行中"
			state_label.add_theme_color_override("font_color", Color(0.04, 0.55, 0.39, 1))
			status_dot.add_theme_color_override("font_color", Color(0.04, 0.72, 0.49, 1))
		LifecycleStateScript.State.PAUSED:
			state_label.text = "已暂停"
			state_label.add_theme_color_override("font_color", Color(0.7, 0.42, 0.07, 1))
			status_dot.add_theme_color_override("font_color", Color(0.9, 0.58, 0.1, 1))
		_:
			state_label.text = "就绪"
			state_label.add_theme_color_override("font_color", Color(0.17, 0.34, 0.52, 1))
			status_dot.add_theme_color_override("font_color", Color(0.23, 0.58, 0.9, 1))


func _refresh_speed(controller: Node) -> void:
	if speed_option == null or not controller.has_method("get_simulation_speed"):
		return
	var speed := float(controller.call("get_simulation_speed"))
	var index := SPEED_VALUES.find(speed)
	if index >= 0 and speed_option.selected != index:
		speed_option.select(index)


func _refresh_time() -> void:
	if time_label == null:
		return
	var controller := _get_scene_controller()
	if controller == null:
		time_label.text = "00:00.0"
		return
	var elapsed := 0.0
	if controller.has_method("is_mission_completed") and bool(controller.call("is_mission_completed")):
		if controller.has_method("get_mission_elapsed_time"):
			elapsed = float(controller.call("get_mission_elapsed_time"))
	elif "timer" in controller:
		elapsed = float(controller.get("timer"))
	time_label.text = _format_time(elapsed)


func _on_run_pause_pressed() -> void:
	var controller := _get_scene_controller()
	if controller != null and controller.has_method("toggle_run_pause"):
		controller.call("toggle_run_pause")
	refresh()


func _on_speed_selected(index: int) -> void:
	if index < 0 or index >= SPEED_VALUES.size():
		refresh()
		return
	var controller := _get_scene_controller()
	if controller != null and controller.has_method("set_simulation_speed"):
		controller.call("set_simulation_speed", SPEED_VALUES[index])
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


func _format_time(elapsed: float) -> String:
	var safe_time := maxf(elapsed, 0.0)
	var minutes := int(floor(safe_time / 60.0))
	var seconds := int(floor(fmod(safe_time, 60.0)))
	var tenths := int(floor(fmod(safe_time * 10.0, 10.0)))
	return "%02d:%02d.%d" % [minutes, seconds, tenths]


func _disable_button_focus(node: Node) -> void:
	if node is Button:
		(node as Button).focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		_disable_button_focus(child)

class_name Scene01LifecycleController
extends "res://scripts/scene_01/scene_01_controller.gd"

signal lifecycle_state_changed(previous_state: int, current_state: int)
signal simulation_speed_changed(previous_speed: float, current_speed: float)
signal lifecycle_reset_completed()

const LifecycleStateScript := preload("res://scripts/scene_01/scene_01_lifecycle_state.gd")

var _lifecycle_state := LifecycleStateScript.new()


func _ready() -> void:
	_connect_lifecycle_signals()
	super._ready()
	_sync_lifecycle_consumers()


func _process(delta: float) -> void:
	if _lifecycle_state.is_running():
		timer += maxf(delta, 0.0) * _lifecycle_state.get_simulation_speed()


func run_scene() -> void:
	if _lifecycle_state.is_ready():
		_lifecycle_state.start()
	elif _lifecycle_state.is_paused():
		_lifecycle_state.resume()


func pause_scene() -> void:
	_lifecycle_state.pause()


func resume_scene() -> void:
	_lifecycle_state.resume()


func toggle_run_pause() -> void:
	_lifecycle_state.toggle_run_pause()


func prepare_gameplay_command() -> bool:
	if _lifecycle_state.is_paused():
		return false
	if _lifecycle_state.is_ready():
		_lifecycle_state.start()
	return _lifecycle_state.is_running()


func cycle_simulation_speed() -> float:
	return _lifecycle_state.cycle_simulation_speed()


func set_simulation_speed(speed: float) -> bool:
	return _lifecycle_state.set_simulation_speed(speed)


func get_lifecycle_state() -> int:
	return int(_lifecycle_state.get_state())


func is_gameplay_running() -> bool:
	return _lifecycle_state.is_running()


func is_scene_paused() -> bool:
	return _lifecycle_state.is_paused()


func get_simulation_speed() -> float:
	return _lifecycle_state.get_simulation_speed()


func reset_scene_state() -> void:
	super.reset_scene_state()
	_lifecycle_state.reset()
	is_running = false
	_sync_lifecycle_consumers()
	lifecycle_reset_completed.emit()


func _connect_lifecycle_signals() -> void:
	var state_callable := Callable(self, "_on_lifecycle_state_changed")
	if not _lifecycle_state.state_changed.is_connected(state_callable):
		_lifecycle_state.state_changed.connect(state_callable)
	var speed_callable := Callable(self, "_on_simulation_speed_changed")
	if not _lifecycle_state.simulation_speed_changed.is_connected(speed_callable):
		_lifecycle_state.simulation_speed_changed.connect(speed_callable)


func _on_lifecycle_state_changed(previous_state: int, current_state: int) -> void:
	is_running = _lifecycle_state.is_running()
	_sync_lifecycle_consumers()
	lifecycle_state_changed.emit(previous_state, current_state)


func _on_simulation_speed_changed(previous_speed: float, current_speed: float) -> void:
	_sync_lifecycle_consumers()
	simulation_speed_changed.emit(previous_speed, current_speed)


func _sync_lifecycle_consumers() -> void:
	if vehicle_move_controller != null and vehicle_move_controller.has_method("sync_lifecycle_state"):
		vehicle_move_controller.call("sync_lifecycle_state")
	var grab_drop_controller := get_node_or_null(
		"SceneRoot/GridRoot/VehicleGrabDropController"
	)
	if grab_drop_controller != null and grab_drop_controller.has_method("sync_lifecycle_state"):
		grab_drop_controller.call("sync_lifecycle_state")

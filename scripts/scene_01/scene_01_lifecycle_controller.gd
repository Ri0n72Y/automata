class_name Scene01LifecycleController
extends "res://scripts/scene_01/scene_01_controller.gd"

signal lifecycle_state_changed(previous_state: int, current_state: int)
signal simulation_speed_changed(previous_speed: float, current_speed: float)
signal lifecycle_reset_completed()
signal lifecycle_run_preparation_failed(reason: StringName)

const LifecycleStateScript := preload("res://scripts/scene_01/scene_01_lifecycle_state.gd")

@export var run_preparation_gate_path: NodePath = NodePath()

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
		_request_start()
	elif _lifecycle_state.is_paused():
		_lifecycle_state.resume()


func pause_scene() -> void:
	_lifecycle_state.pause()


func resume_scene() -> void:
	_lifecycle_state.resume()


func toggle_run_pause() -> void:
	if _lifecycle_state.is_ready():
		_request_start()
		return
	_lifecycle_state.toggle_run_pause()


func prepare_gameplay_command() -> bool:
	if _lifecycle_state.is_paused():
		return false
	if _lifecycle_state.is_ready():
		return _request_start()
	return _lifecycle_state.is_running()


func prepare_gameplay_command_validation() -> bool:
	if _lifecycle_state.is_paused():
		return false
	if _lifecycle_state.is_ready():
		return _prepare_scene_run()
	return _lifecycle_state.is_running()


func commit_gameplay_command_start() -> bool:
	if _lifecycle_state.is_paused():
		return false
	if _lifecycle_state.is_ready():
		return _lifecycle_state.start()
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
	_set_legacy_running_state(false)
	_sync_lifecycle_consumers()
	lifecycle_reset_completed.emit()


func _request_start() -> bool:
	if not _lifecycle_state.is_ready():
		return _lifecycle_state.is_running()
	if not _prepare_scene_run():
		return false
	return _lifecycle_state.start()


func _prepare_scene_run() -> bool:
	if run_preparation_gate_path.is_empty():
		return true
	var gate := get_node_or_null(run_preparation_gate_path)
	if gate == null:
		lifecycle_run_preparation_failed.emit(&"missing_run_preparation_gate")
		return false
	if not gate.has_method("prepare_scene_run"):
		lifecycle_run_preparation_failed.emit(&"invalid_run_preparation_gate")
		return false
	if not bool(gate.call("prepare_scene_run")):
		lifecycle_run_preparation_failed.emit(&"run_preparation_rejected")
		return false
	return true


func _connect_lifecycle_signals() -> void:
	var state_callable := Callable(self, "_on_lifecycle_state_changed")
	if not _lifecycle_state.state_changed.is_connected(state_callable):
		_lifecycle_state.state_changed.connect(state_callable)
	var speed_callable := Callable(self, "_on_simulation_speed_changed")
	if not _lifecycle_state.simulation_speed_changed.is_connected(speed_callable):
		_lifecycle_state.simulation_speed_changed.connect(speed_callable)


func _on_lifecycle_state_changed(previous_state: int, current_state: int) -> void:
	_set_legacy_running_state(_lifecycle_state.is_running())
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

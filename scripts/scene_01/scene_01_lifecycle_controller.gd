class_name Scene01LifecycleController
extends "res://scripts/scene_01/scene_01_controller.gd"

signal lifecycle_state_changed(previous_state: int, current_state: int)
signal simulation_speed_changed(previous_speed: float, current_speed: float)
signal lifecycle_reset_completed()
signal lifecycle_run_preparation_failed(reason: StringName)

const LifecycleStateScript := preload("res://scripts/scene_01/scene_01_lifecycle_state.gd")

@export var run_preparation_gate_path: NodePath = NodePath()

var _lifecycle_state := LifecycleStateScript.new()
var _scene_initialized: bool = false
var _lifecycle_mutation_in_progress: bool = false


func _ready() -> void:
	_connect_lifecycle_signals()
	super._ready()
	_sync_lifecycle_consumers()


func _process(delta: float) -> void:
	if _lifecycle_state.is_running():
		timer += maxf(delta, 0.0) * _lifecycle_state.get_simulation_speed()


func run_scene() -> void:
	if _lifecycle_mutation_in_progress:
		return
	if _lifecycle_state.is_ready():
		_request_start()
		return
	if not _lifecycle_state.is_paused():
		return
	_lifecycle_mutation_in_progress = true
	_lifecycle_state.resume()
	_lifecycle_mutation_in_progress = false


func pause_scene() -> void:
	if _lifecycle_mutation_in_progress:
		return
	_lifecycle_mutation_in_progress = true
	_lifecycle_state.pause()
	_lifecycle_mutation_in_progress = false


func resume_scene() -> void:
	if _lifecycle_mutation_in_progress:
		return
	_lifecycle_mutation_in_progress = true
	_lifecycle_state.resume()
	_lifecycle_mutation_in_progress = false


func toggle_run_pause() -> void:
	if _lifecycle_mutation_in_progress:
		return
	if _lifecycle_state.is_ready():
		_request_start()
		return
	_lifecycle_mutation_in_progress = true
	_lifecycle_state.toggle_run_pause()
	_lifecycle_mutation_in_progress = false


func ensure_gameplay_running() -> bool:
	if _lifecycle_mutation_in_progress:
		return false
	if _lifecycle_state.is_paused():
		return false
	if _lifecycle_state.is_running():
		return true
	if not _lifecycle_state.is_ready():
		return false
	return _request_start()


func cycle_simulation_speed() -> float:
	if _lifecycle_mutation_in_progress:
		return _lifecycle_state.get_simulation_speed()
	_lifecycle_mutation_in_progress = true
	var speed := _lifecycle_state.cycle_simulation_speed()
	_lifecycle_mutation_in_progress = false
	return speed


func set_simulation_speed(speed: float) -> bool:
	if _lifecycle_mutation_in_progress:
		return false
	_lifecycle_mutation_in_progress = true
	var accepted := _lifecycle_state.set_simulation_speed(speed)
	_lifecycle_mutation_in_progress = false
	return accepted


func get_lifecycle_state() -> int:
	return int(_lifecycle_state.get_state())


func is_gameplay_running() -> bool:
	return _lifecycle_state.is_running()


func is_scene_paused() -> bool:
	return _lifecycle_state.is_paused()


func is_scene_initialized() -> bool:
	return _scene_initialized


func get_simulation_speed() -> float:
	return _lifecycle_state.get_simulation_speed()


func reset_scene_state() -> bool:
	if _lifecycle_mutation_in_progress or not _scene_initialized:
		return false
	_lifecycle_mutation_in_progress = true
	var restored := super.reset_scene_state()
	if restored:
		_lifecycle_state.reset()
		_sync_lifecycle_consumers()
		lifecycle_reset_completed.emit()
	_lifecycle_mutation_in_progress = false
	return restored


func _initialize_scene_state() -> bool:
	_scene_initialized = super._initialize_scene_state()
	return _scene_initialized


func _is_scene_running() -> bool:
	return _lifecycle_state.is_running()


func _request_start() -> bool:
	if _lifecycle_mutation_in_progress:
		return false
	if not _lifecycle_state.is_ready():
		return _lifecycle_state.is_running()
	_lifecycle_mutation_in_progress = true
	var started := false
	if not _scene_initialized:
		lifecycle_run_preparation_failed.emit(&"scene_not_initialized")
	elif _prepare_scene_run():
		started = _lifecycle_state.start()
	_lifecycle_mutation_in_progress = false
	return started and _lifecycle_state.is_running()


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

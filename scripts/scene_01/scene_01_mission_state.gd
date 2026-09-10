class_name Scene01MissionState
extends RefCounted

signal state_changed(previous_state: State, current_state: State)
signal completed(elapsed_time: float)

const LifecycleStateScript := preload("res://scripts/scene_01/scene_01_lifecycle_state.gd")

enum State {
	READY,
	RUNNING,
	PAUSED,
	COMPLETED,
}

var _completed: bool = false
var _completion_elapsed_time: float = 0.0


func get_state(lifecycle_state: int) -> State:
	if _completed:
		return State.COMPLETED
	return _project_lifecycle_state(lifecycle_state)


func is_completed() -> bool:
	return _completed


func get_elapsed_time(scene_elapsed_time: float) -> float:
	if _completed:
		return _completion_elapsed_time
	return maxf(scene_elapsed_time, 0.0)


func handle_lifecycle_state_changed(previous_state: int, current_state: int) -> void:
	if _completed:
		return
	var previous := _project_lifecycle_state(previous_state)
	var current := _project_lifecycle_state(current_state)
	if previous != current:
		state_changed.emit(previous, current)


func try_complete(
	current_count: int,
	target_count: int,
	scene_elapsed_time: float,
	lifecycle_state: int
) -> bool:
	if _completed or target_count <= 0 or current_count < target_count:
		return false
	if _project_lifecycle_state(lifecycle_state) != State.RUNNING:
		return false
	var previous := get_state(lifecycle_state)
	_completed = true
	_completion_elapsed_time = maxf(scene_elapsed_time, 0.0)
	state_changed.emit(previous, State.COMPLETED)
	completed.emit(_completion_elapsed_time)
	return true


func reset(lifecycle_state: int) -> void:
	var previous := get_state(lifecycle_state)
	_completed = false
	_completion_elapsed_time = 0.0
	var current := get_state(lifecycle_state)
	if previous != current:
		state_changed.emit(previous, current)


func _project_lifecycle_state(lifecycle_state: int) -> State:
	match lifecycle_state:
		LifecycleStateScript.State.RUNNING:
			return State.RUNNING
		LifecycleStateScript.State.PAUSED:
			return State.PAUSED
		_:
			return State.READY

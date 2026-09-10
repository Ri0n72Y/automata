class_name Scene01MissionState
extends RefCounted

signal completed(elapsed_time: float)

enum State {
	READY,
	RUNNING,
	PAUSED,
	COMPLETED,
}

var _completed: bool = false
var _completion_elapsed_time: float = 0.0


func is_completed() -> bool:
	return _completed


func get_elapsed_time(scene_elapsed_time: float) -> float:
	return _completion_elapsed_time if _completed else maxf(scene_elapsed_time, 0.0)


func try_complete(current_count: int, target_count: int, scene_elapsed_time: float) -> bool:
	if _completed or target_count <= 0 or current_count < target_count:
		return false
	_completed = true
	_completion_elapsed_time = maxf(scene_elapsed_time, 0.0)
	completed.emit(_completion_elapsed_time)
	return true


func reset() -> void:
	_completed = false
	_completion_elapsed_time = 0.0

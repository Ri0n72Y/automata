class_name Scene01MissionController
extends "res://scripts/scene_01/scene_01_lifecycle_controller.gd"

signal mission_state_changed(previous_state: int, current_state: int)
signal mission_completed(elapsed_time: float)

const MissionStateScript := preload("res://scripts/scene_01/scene_01_mission_state.gd")
const StandardBoxScript := preload("res://scripts/objects/standard_box.gd")

var _mission_state := MissionStateScript.new()
var _standard_box: StandardBoxScript


func _ready() -> void:
	_connect_mission_signals()
	super._ready()
	_bind_standard_box()
	_evaluate_mission_completion()


func get_mission_state() -> int:
	return int(_mission_state.get_state(get_lifecycle_state()))


func is_mission_completed() -> bool:
	return _mission_state.is_completed()


func get_mission_target_count() -> int:
	return _standard_box.get_capacity() if _standard_box != null else 0


func get_mission_elapsed_time() -> float:
	return _mission_state.get_elapsed_time(timer)


func _on_lifecycle_state_changed(previous_state: int, current_state: int) -> void:
	if current_state == LifecycleStateScript.State.READY and _mission_state.is_completed():
		_mission_state.reset(current_state)
		super._on_lifecycle_state_changed(previous_state, current_state)
		return
	super._on_lifecycle_state_changed(previous_state, current_state)
	_mission_state.handle_lifecycle_state_changed(previous_state, current_state)
	if current_state == LifecycleStateScript.State.RUNNING:
		_evaluate_mission_completion()


func _bind_standard_box() -> void:
	_standard_box = scene_object_manager.get_standard_box() if scene_object_manager != null else null
	if _standard_box == null:
		push_error("Scene 01 mission requires StandardBox.")
		return
	var count_callable := Callable(self, "_on_standard_box_count_changed")
	if not _standard_box.count_changed.is_connected(count_callable):
		_standard_box.count_changed.connect(count_callable)


func _evaluate_mission_completion() -> void:
	if _standard_box == null:
		return
	_mission_state.try_complete(
		_standard_box.get_current_count(),
		_standard_box.get_capacity(),
		timer,
		get_lifecycle_state()
	)


func _on_standard_box_count_changed(_previous_count: int, _current_count: int) -> void:
	_evaluate_mission_completion()


func _connect_mission_signals() -> void:
	var state_callable := Callable(self, "_on_mission_state_changed")
	if not _mission_state.state_changed.is_connected(state_callable):
		_mission_state.state_changed.connect(state_callable)
	var completed_callable := Callable(self, "_on_mission_completed")
	if not _mission_state.completed.is_connected(completed_callable):
		_mission_state.completed.connect(completed_callable)


func _on_mission_state_changed(previous_state: int, current_state: int) -> void:
	mission_state_changed.emit(previous_state, current_state)


func _on_mission_completed(elapsed_time: float) -> void:
	mission_completed.emit(elapsed_time)

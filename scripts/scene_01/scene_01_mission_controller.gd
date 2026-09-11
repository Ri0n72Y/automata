class_name Scene01MissionController
extends "res://scripts/scene_01/scene_01_lifecycle_controller.gd"

signal mission_state_changed(previous_state: int, current_state: int)
signal mission_completed(elapsed_time: float)

const MissionStateScript := preload("res://scripts/scene_01/scene_01_mission_state.gd")
const StandardBoxScript := preload("res://scripts/objects/standard_box.gd")
const ObservableStateScript := preload("res://scripts/scene_01/scene_01_observable_state.gd")

@onready var _observable_state: ObservableStateScript = %Scene01ObservableState

var _mission_state := MissionStateScript.new()
var _standard_box: StandardBoxScript


func _ready() -> void:
	_mission_state.completed.connect(_on_mission_completed)
	super._ready()
	if _observable_state == null or not _observable_state.configure(
		scene_vehicle_manager,
		scene_object_manager,
		self
	):
		push_error("Scene 01 observable state failed to initialize.")
	_bind_standard_box()
	_evaluate_mission_completion()


func get_mission_state() -> int:
	if _mission_state.is_completed():
		return MissionStateScript.State.COMPLETED
	return _project_lifecycle_state(get_lifecycle_state())


func is_mission_completed() -> bool:
	return _mission_state.is_completed()


func get_mission_target_count() -> int:
	return _standard_box.get_capacity() if _standard_box != null else 0


func get_mission_elapsed_time() -> float:
	return _mission_state.get_elapsed_time(timer)


func _on_lifecycle_state_changed(previous_state: int, current_state: int) -> void:
	if current_state == LifecycleStateScript.State.READY and _mission_state.is_completed():
		_mission_state.reset()
		mission_state_changed.emit(
			MissionStateScript.State.COMPLETED,
			MissionStateScript.State.READY
		)
		super._on_lifecycle_state_changed(previous_state, current_state)
		return

	super._on_lifecycle_state_changed(previous_state, current_state)
	if not _mission_state.is_completed():
		var previous_mission_state := _project_lifecycle_state(previous_state)
		var current_mission_state := _project_lifecycle_state(current_state)
		if previous_mission_state != current_mission_state:
			mission_state_changed.emit(previous_mission_state, current_mission_state)
	if current_state == LifecycleStateScript.State.RUNNING:
		_evaluate_mission_completion()


func _bind_standard_box() -> void:
	_standard_box = scene_object_manager.get_standard_box() if scene_object_manager != null else null
	if _standard_box == null:
		push_error("Scene 01 mission requires StandardBox.")
		return
	_standard_box.count_changed.connect(_on_standard_box_count_changed)


func _evaluate_mission_completion() -> void:
	if _standard_box == null or not is_gameplay_running():
		return
	_mission_state.try_complete(
		_standard_box.get_current_count(),
		_standard_box.get_capacity(),
		timer
	)


func _on_standard_box_count_changed(_previous_count: int, _current_count: int) -> void:
	_evaluate_mission_completion()


func _on_mission_completed(elapsed_time: float) -> void:
	mission_state_changed.emit(
		_project_lifecycle_state(get_lifecycle_state()),
		MissionStateScript.State.COMPLETED
	)
	mission_completed.emit(elapsed_time)


func _project_lifecycle_state(lifecycle_state: int) -> int:
	match lifecycle_state:
		LifecycleStateScript.State.RUNNING:
			return MissionStateScript.State.RUNNING
		LifecycleStateScript.State.PAUSED:
			return MissionStateScript.State.PAUSED
		_:
			return MissionStateScript.State.READY

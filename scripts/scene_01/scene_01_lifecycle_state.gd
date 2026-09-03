class_name Scene01LifecycleState
extends RefCounted

signal state_changed(previous_state: State, current_state: State)
signal simulation_speed_changed(previous_speed: float, current_speed: float)

enum State {
	READY,
	RUNNING,
	PAUSED,
}

const DEFAULT_SIMULATION_SPEED := 1.0
const SUPPORTED_SIMULATION_SPEEDS: Array[float] = [0.5, 1.0, 2.0, 4.0]

var _state: State = State.READY
var _simulation_speed: float = DEFAULT_SIMULATION_SPEED


func get_state() -> State:
	return _state


func is_ready() -> bool:
	return _state == State.READY


func is_running() -> bool:
	return _state == State.RUNNING


func is_paused() -> bool:
	return _state == State.PAUSED


func get_simulation_speed() -> float:
	return _simulation_speed


func start() -> bool:
	if _state != State.READY:
		return false
	return _set_state(State.RUNNING)


func pause() -> bool:
	if _state != State.RUNNING:
		return false
	return _set_state(State.PAUSED)


func resume() -> bool:
	if _state != State.PAUSED:
		return false
	return _set_state(State.RUNNING)


func toggle_run_pause() -> bool:
	match _state:
		State.READY:
			return start()
		State.RUNNING:
			return pause()
		State.PAUSED:
			return resume()
		_:
			return false


func set_simulation_speed(speed: float) -> bool:
	var normalized := _normalize_supported_speed(speed)
	if normalized <= 0.0:
		return false
	if is_equal_approx(_simulation_speed, normalized):
		return true
	var previous := _simulation_speed
	_simulation_speed = normalized
	simulation_speed_changed.emit(previous, _simulation_speed)
	return true


func cycle_simulation_speed() -> float:
	var current_index := _find_speed_index(_simulation_speed)
	var next_index := posmod(current_index + 1, SUPPORTED_SIMULATION_SPEEDS.size())
	set_simulation_speed(SUPPORTED_SIMULATION_SPEEDS[next_index])
	return _simulation_speed


func reset() -> void:
	set_simulation_speed(DEFAULT_SIMULATION_SPEED)
	_set_state(State.READY)


func _set_state(next_state: State) -> bool:
	if _state == next_state:
		return false
	var previous := _state
	_state = next_state
	state_changed.emit(previous, _state)
	return true


func _normalize_supported_speed(speed: float) -> float:
	for supported_speed in SUPPORTED_SIMULATION_SPEEDS:
		if is_equal_approx(speed, supported_speed):
			return supported_speed
	return -1.0


func _find_speed_index(speed: float) -> int:
	for index in range(SUPPORTED_SIMULATION_SPEEDS.size()):
		if is_equal_approx(speed, SUPPORTED_SIMULATION_SPEEDS[index]):
			return index
	return 1

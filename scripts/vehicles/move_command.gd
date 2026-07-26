class_name MoveCommand
extends RefCounted


enum State {
	PLANNING,
	MOVING,
	WAITING,
	BLOCKED,
}

var target_anchor: Vector2i
var path: Array[Vector2i] = []
var path_index: int = 0
var state: State = State.PLANNING


func configure(target: Vector2i, planned_path: Array[Vector2i]) -> void:
	target_anchor = target
	path = planned_path.duplicate()
	path_index = 0
	state = State.MOVING if not path.is_empty() else State.BLOCKED


func get_current_anchor() -> Vector2i:
	if path.is_empty() or path_index < 0 or path_index >= path.size():
		return Vector2i.ZERO
	return path[path_index]


func get_next_anchor() -> Vector2i:
	var next_index := path_index + 1
	if state != State.MOVING or next_index < 0 or next_index >= path.size():
		return get_current_anchor()
	return path[next_index]


func advance() -> bool:
	if state != State.MOVING:
		return false
	if path_index >= path.size() - 1:
		state = State.WAITING
		return true
	path_index += 1
	if path_index >= path.size() - 1:
		state = State.WAITING
		return true
	return false


func block() -> void:
	state = State.BLOCKED


func is_finished() -> bool:
	return state == State.WAITING

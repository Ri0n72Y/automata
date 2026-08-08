extends RefCounted
class_name GrabDropResult

enum Action {
	NONE,
	GRAB,
	DROP,
}

enum Status {
	ACCEPTED,
	NO_CAPABILITY,
	BUSY,
	NO_TARGET,
	EMPTY,
	FULL,
	TYPE_MISMATCH,
	ALREADY_CONTAINED,
	GROUND_OCCUPIED,
	OWNERSHIP_CONFLICT,
	INVALID_TARGET,
}

var _action: int = Action.NONE
var _status: int = Status.INVALID_TARGET
var _item: StandardBlock

var action: int:
	get:
		return _action

var status: int:
	get:
		return _status

var item: StandardBlock:
	get:
		return _item


static func accepted(p_action: int, p_item: StandardBlock) -> GrabDropResult:
	return _create(p_action, Status.ACCEPTED, p_item)


static func rejected(p_action: int, p_status: int) -> GrabDropResult:
	if p_status == Status.ACCEPTED:
		p_status = Status.INVALID_TARGET
	return _create(p_action, p_status, null)


static func _create(p_action: int, p_status: int, p_item: StandardBlock) -> GrabDropResult:
	var result := GrabDropResult.new()
	result._action = p_action
	result._status = p_status
	result._item = p_item
	return result


func is_success() -> bool:
	return _status == Status.ACCEPTED

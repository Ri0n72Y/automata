extends RefCounted
class_name ItemTransferResult

enum Status {
	ACCEPTED,
	EMPTY,
	FULL,
	TYPE_MISMATCH,
	INVALID_TARGET,
	ALREADY_CONTAINED,
	OCCUPIED,
}

var _status: int = Status.INVALID_TARGET
var _item: StandardBlock

var status: int:
	get:
		return _status

var item: StandardBlock:
	get:
		return _item


static func accepted(value: StandardBlock = null) -> ItemTransferResult:
	return _create(Status.ACCEPTED, value)


static func rejected(value: int) -> ItemTransferResult:
	if value == Status.ACCEPTED:
		value = Status.INVALID_TARGET
	return _create(value, null)


static func _create(value: int, block: StandardBlock) -> ItemTransferResult:
	var result := ItemTransferResult.new()
	result._status = value
	result._item = block
	return result


func is_success() -> bool:
	return _status == Status.ACCEPTED

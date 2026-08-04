extends RefCounted
class_name ItemTransferResult

enum Status {
	ACCEPTED,
	EMPTY,
	FULL,
	TYPE_MISMATCH,
	INVALID_TARGET,
	ALREADY_CONTAINED,
}

var status: Status = Status.INVALID_TARGET
var item: StandardBlock


static func accepted(value: StandardBlock = null) -> ItemTransferResult:
	return _create(Status.ACCEPTED, value)


static func rejected(value: Status) -> ItemTransferResult:
	return _create(value, null)


static func _create(value: Status, block: StandardBlock) -> ItemTransferResult:
	var result := ItemTransferResult.new()
	result.status = value
	result.item = block
	return result


func is_success() -> bool:
	return status == Status.ACCEPTED

extends RefCounted
class_name InfiniteBlockPile

signal produced_count_changed(previous_count: int, current_count: int)

var produced_count: int = 0


func take_item() -> ItemTransferResult:
	var previous_count := produced_count
	produced_count += 1
	produced_count_changed.emit(previous_count, produced_count)
	return ItemTransferResult.accepted(StandardBlock.create())


func put_item(_item: Variant) -> ItemTransferResult:
	return ItemTransferResult.rejected(ItemTransferResult.Status.INVALID_TARGET)


func reset() -> void:
	if produced_count == 0:
		return
	var previous_count := produced_count
	produced_count = 0
	produced_count_changed.emit(previous_count, produced_count)

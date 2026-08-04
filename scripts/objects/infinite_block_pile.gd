extends ItemSourceInterface
class_name InfiniteBlockPile

signal produced_count_changed(previous_count: int, current_count: int)

var _produced_count: int = 0


func get_output_item_type() -> StringName:
	return StandardBlock.TYPE_ID


func is_infinite() -> bool:
	return true


func get_produced_count() -> int:
	return _produced_count


func take_item() -> ItemTransferResult:
	var previous_count := _produced_count
	_produced_count += 1
	produced_count_changed.emit(previous_count, _produced_count)
	return ItemTransferResult.accepted(StandardBlock.create())


func put_item(_item: Variant) -> ItemTransferResult:
	return ItemTransferResult.rejected(ItemTransferResult.Status.INVALID_TARGET)


func reset() -> void:
	if _produced_count == 0:
		return
	var previous_count := _produced_count
	_produced_count = 0
	produced_count_changed.emit(previous_count, _produced_count)

extends RefCounted
class_name StandardBox

signal count_changed(previous_count: int, current_count: int)

const CAPACITY: int = 8
const INITIAL_COUNT: int = 3

var _items: Array[StandardBlock] = []


func _init() -> void:
	_reset_items_without_signal()


func get_capacity() -> int:
	return CAPACITY


func get_current_count() -> int:
	return _items.size()


func is_full() -> bool:
	return get_current_count() >= CAPACITY


func is_empty() -> bool:
	return _items.is_empty()


func contains_item(item: StandardBlock) -> bool:
	return item != null and _items.has(item)


func put_item(item: Variant) -> ItemTransferResult:
	if not item is StandardBlock:
		return ItemTransferResult.rejected(ItemTransferResult.Status.TYPE_MISMATCH)
	var block := item as StandardBlock
	if not block.is_valid():
		return ItemTransferResult.rejected(ItemTransferResult.Status.TYPE_MISMATCH)
	if _items.has(block):
		return ItemTransferResult.rejected(ItemTransferResult.Status.ALREADY_CONTAINED)
	if is_full():
		return ItemTransferResult.rejected(ItemTransferResult.Status.FULL)
	var previous_count := get_current_count()
	_items.append(block)
	count_changed.emit(previous_count, get_current_count())
	return ItemTransferResult.accepted(block)


func take_item() -> ItemTransferResult:
	if is_empty():
		return ItemTransferResult.rejected(ItemTransferResult.Status.EMPTY)
	var previous_count := get_current_count()
	var block: StandardBlock = _items.pop_back()
	count_changed.emit(previous_count, get_current_count())
	return ItemTransferResult.accepted(block)


func reset() -> void:
	var previous_count := get_current_count()
	_reset_items_without_signal()
	if previous_count != get_current_count():
		count_changed.emit(previous_count, get_current_count())


func _reset_items_without_signal() -> void:
	_items.clear()
	for _index in range(INITIAL_COUNT):
		_items.append(StandardBlock.create())

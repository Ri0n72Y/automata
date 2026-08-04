extends ItemReceiverInterface
class_name StandardBox

signal count_changed(previous_count: int, current_count: int)

const CAPACITY: int = 8
const INITIAL_COUNT: int = 3

var _items: Array[StandardBlock] = []


func _init() -> void:
	_reset_items_without_signal()


func get_accepted_item_types() -> PackedStringArray:
	return PackedStringArray([StandardBlock.TYPE_ID])


func get_capacity() -> int:
	return CAPACITY


func get_current_count() -> int:
	return _items.size()


func is_full() -> bool:
	return get_current_count() >= CAPACITY


func is_empty() -> bool:
	return _items.is_empty()


func contains_item(item: StandardBlock) -> bool:
	return item != null and _items.has(item) and _owns_item(item)


func put_item(item: Variant) -> ItemTransferResult:
	if not item is StandardBlock:
		return ItemTransferResult.rejected(ItemTransferResult.Status.TYPE_MISMATCH)
	var block := item as StandardBlock
	if not block.is_valid():
		return ItemTransferResult.rejected(ItemTransferResult.Status.TYPE_MISMATCH)
	if _items.has(block) or block.is_claimed():
		return ItemTransferResult.rejected(ItemTransferResult.Status.ALREADY_CONTAINED)
	if is_full():
		return ItemTransferResult.rejected(ItemTransferResult.Status.FULL)
	if not _claim_item(block):
		return ItemTransferResult.rejected(ItemTransferResult.Status.ALREADY_CONTAINED)
	var previous_count := get_current_count()
	_items.append(block)
	count_changed.emit(previous_count, get_current_count())
	return ItemTransferResult.accepted(block)


func take_item() -> ItemTransferResult:
	if is_empty():
		return ItemTransferResult.rejected(ItemTransferResult.Status.EMPTY)
	var block: StandardBlock = _items.back()
	if not _owns_item(block):
		return ItemTransferResult.rejected(ItemTransferResult.Status.INVALID_TARGET)
	var previous_count := get_current_count()
	_items.pop_back()
	_release_item(block)
	count_changed.emit(previous_count, get_current_count())
	return ItemTransferResult.accepted(block)


func reset() -> void:
	var previous_count := get_current_count()
	_reset_items_without_signal()
	if previous_count != get_current_count():
		count_changed.emit(previous_count, get_current_count())


func _reset_items_without_signal() -> void:
	_release_all_items()
	for _index in range(INITIAL_COUNT):
		var block := StandardBlock.create()
		_claim_item(block)
		_items.append(block)


func _release_all_items() -> void:
	for block in _items:
		_release_item(block)
	_items.clear()

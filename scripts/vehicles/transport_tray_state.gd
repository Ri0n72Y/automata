extends ItemReceiverInterface
class_name TransportTrayState

signal count_changed(previous_count: int, current_count: int)

var _capacity: int = 0
var _items: Array[StandardBlock] = []
var _configured: bool = false

var capacity: int:
	get:
		return _capacity


func configure(p_capacity: int) -> bool:
	if _configured:
		push_error("Transport tray state is immutable after configuration.")
		return false
	if p_capacity <= 0:
		push_error("Transport tray capacity must be greater than zero.")
		return false
	_capacity = p_capacity
	_configured = true
	return true


func is_configured() -> bool:
	return _configured


func get_accepted_item_types() -> PackedStringArray:
	return PackedStringArray([StandardBlock.TYPE_ID])


func get_capacity() -> int:
	return _capacity


func get_current_count() -> int:
	return _items.size()


func is_full() -> bool:
	return _configured and get_current_count() >= _capacity


func is_empty() -> bool:
	return _items.is_empty()


func contains_item(item: StandardBlock) -> bool:
	return item != null and _items.has(item) and _owns_item(item)


func get_items() -> Array[StandardBlock]:
	return _items.duplicate()


func put_item(item: Variant) -> ItemTransferResult:
	if not _configured:
		return ItemTransferResult.rejected(ItemTransferResult.Status.INVALID_TARGET)
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
	if not _configured:
		return ItemTransferResult.rejected(ItemTransferResult.Status.INVALID_TARGET)
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
	_release_all_items()
	if previous_count != 0:
		count_changed.emit(previous_count, 0)


func replace_count_for_compatibility(value: int) -> bool:
	if not _configured or value < 0 or value > _capacity:
		return false
	var previous_count := get_current_count()
	_release_all_items()
	for _index in range(value):
		var block := StandardBlock.create()
		if not _claim_item(block):
			_release_all_items()
			return false
		_items.append(block)
	if previous_count != get_current_count():
		count_changed.emit(previous_count, get_current_count())
	return true


func _release_all_items() -> void:
	for block in _items:
		_release_item(block)
	_items.clear()

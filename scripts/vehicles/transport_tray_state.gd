extends ItemReceiverInterface
class_name TransportTrayState

signal count_changed(previous_count: int, current_count: int)

var _capacity: int = 0
var _items: Array[StandardBlock] = []
var _configured: bool = false
var _access_guard_ref: WeakRef
var _access_guard_method: StringName = &""
var _has_access_guard: bool = false

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


func configure_access_guard(owner: Object, method_name: StringName) -> bool:
	if owner == null or method_name == &"" or not owner.has_method(method_name):
		return false
	_access_guard_ref = weakref(owner)
	_access_guard_method = method_name
	_has_access_guard = true
	return true


func is_configured() -> bool:
	return _configured


func get_accepted_item_types() -> PackedStringArray:
	return PackedStringArray([StandardBlock.TYPE_ID])


func can_take_item() -> bool:
	return _configured and _is_interaction_available()


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
	if not _configured or not _is_interaction_available():
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
	if not _configured or not _is_interaction_available():
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
	if value == get_current_count():
		return true

	var replacement: Array[StandardBlock] = []
	for _index in range(value):
		var block := StandardBlock.create()
		if not _claim_item(block):
			_release_items(replacement)
			return false
		replacement.append(block)

	var previous_count := get_current_count()
	_release_all_items()
	_items = replacement
	count_changed.emit(previous_count, get_current_count())
	return true


func _is_interaction_available() -> bool:
	if not _has_access_guard:
		return true
	if _access_guard_ref == null:
		return false
	var guard_owner: Object = _access_guard_ref.get_ref() as Object
	if guard_owner == null or not guard_owner.has_method(_access_guard_method):
		return false
	return bool(guard_owner.call(_access_guard_method, self))


func _release_all_items() -> void:
	_release_items(_items)
	_items.clear()


func _release_items(items: Array[StandardBlock]) -> void:
	for block in items:
		_release_item(block)

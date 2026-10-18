class_name BeanTargetInventory
extends ItemReceiverInterface

## Receiver-only target bin. Accepts any bean type; correctness is decided only
## at settlement, never here. Capacity is measured in grams.

signal grams_changed(total_grams: int)

var capacity_grams: int = 1000
var _batches: Array[BeanBatch] = []


func configure(p_capacity_grams: int, interaction_cell: Vector2i) -> void:
	capacity_grams = maxi(p_capacity_grams, 0)
	set_interaction_cells([interaction_cell])


func get_accepted_item_types() -> PackedStringArray:
	return BeanBatch.ALL_BEAN_TYPES


func accepts_item_type(item_type: StringName) -> bool:
	return BeanBatch.ALL_BEAN_TYPES.has(String(item_type))


func can_take_item() -> bool:
	return false


func get_current_count() -> int:
	return get_total_grams()


func get_capacity() -> int:
	return capacity_grams


func get_total_grams() -> int:
	var total := 0
	for batch in _batches:
		total += batch.grams
	return total


func get_grams_by_type() -> Dictionary:
	var result := {}
	for bean_type in BeanBatch.ALL_BEAN_TYPES:
		result[StringName(bean_type)] = 0
	for batch in _batches:
		result[batch.bean_type] = int(result.get(batch.bean_type, 0)) + batch.grams
	return result


func get_batches() -> Array[BeanBatch]:
	return _batches.duplicate()


func put_item(item: Variant) -> ItemTransferResult:
	if not item is BeanBatch:
		return ItemTransferResult.rejected(ItemTransferResult.Status.TYPE_MISMATCH)
	var batch := item as BeanBatch
	if not batch.is_valid() or batch.is_claimed():
		return ItemTransferResult.rejected(ItemTransferResult.Status.ALREADY_CONTAINED)
	if get_total_grams() + batch.grams > capacity_grams:
		return ItemTransferResult.rejected(ItemTransferResult.Status.FULL)
	if not _claim_item(batch):
		return ItemTransferResult.rejected(ItemTransferResult.Status.ALREADY_CONTAINED)
	_batches.append(batch)
	grams_changed.emit(get_total_grams())
	return ItemTransferResult.accepted(batch)


func take_item() -> ItemTransferResult:
	return ItemTransferResult.rejected(ItemTransferResult.Status.INVALID_TARGET)


func reset() -> void:
	_batches.clear()
	grams_changed.emit(0)

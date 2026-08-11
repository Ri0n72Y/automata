extends ItemSourceInterface
class_name InfiniteBlockPile

signal produced_count_changed(previous_count: int, current_count: int)

var _produced_count: int = 0
var _pending_item_ids: Dictionary = {}


func get_output_item_type() -> StringName:
	return StandardBlock.TYPE_ID


func is_available() -> bool:
	return true


func is_infinite() -> bool:
	return true


func get_produced_count() -> int:
	return _produced_count


func take_item() -> ItemTransferResult:
	var block := StandardBlock.create()
	_commit_production()
	return ItemTransferResult.accepted(block)


func prepare_take_item() -> ItemTransferResult:
	var block := StandardBlock.create()
	if block == null or not block.is_valid():
		return ItemTransferResult.rejected(ItemTransferResult.Status.INVALID_TARGET)
	_pending_item_ids[block.get_block_id()] = true
	return ItemTransferResult.accepted(block)


func commit_prepared_take_item(item: StandardBlock) -> bool:
	if not _consume_pending_item(item):
		return false
	_commit_production()
	return true


func rollback_prepared_take_item(item: StandardBlock) -> bool:
	return _consume_pending_item(item)


func put_item(_item: Variant) -> ItemTransferResult:
	return ItemTransferResult.rejected(ItemTransferResult.Status.INVALID_TARGET)


func reset() -> void:
	_pending_item_ids.clear()
	if _produced_count == 0:
		return
	var previous_count := _produced_count
	_produced_count = 0
	produced_count_changed.emit(previous_count, _produced_count)


func _consume_pending_item(item: StandardBlock) -> bool:
	if item == null or not item.is_valid():
		return false
	var item_id: int = item.get_block_id()
	if not _pending_item_ids.has(item_id):
		return false
	_pending_item_ids.erase(item_id)
	return true


func _commit_production() -> void:
	var previous_count := _produced_count
	_produced_count += 1
	produced_count_changed.emit(previous_count, _produced_count)

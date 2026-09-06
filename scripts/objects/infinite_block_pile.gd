extends ItemSourceInterface
class_name InfiniteBlockPile


func get_output_item_type() -> StringName:
	return StandardBlock.TYPE_ID


func is_available() -> bool:
	return true


func is_infinite() -> bool:
	return true


func take_item() -> ItemTransferResult:
	var block := StandardBlock.create()
	if block == null or not block.is_valid():
		return ItemTransferResult.rejected(ItemTransferResult.Status.INVALID_TARGET)
	return ItemTransferResult.accepted(block)


func put_item(_item: Variant) -> ItemTransferResult:
	return ItemTransferResult.rejected(ItemTransferResult.Status.INVALID_TARGET)

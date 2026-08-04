extends Resource
class_name ItemReceiverInterface

@export var interaction_cells: Array[Vector2i] = []


func set_interaction_cells(cells: Array[Vector2i]) -> void:
	interaction_cells.clear()
	interaction_cells.append_array(cells)


func get_interaction_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.append_array(interaction_cells)
	return result


func get_accepted_item_types() -> PackedStringArray:
	return PackedStringArray()


func accepts_item_type(item_type: StringName) -> bool:
	return get_accepted_item_types().has(item_type)


func get_current_count() -> int:
	return 0


func get_capacity() -> int:
	return 0


func put_item(_item: Variant) -> ItemTransferResult:
	return ItemTransferResult.rejected(ItemTransferResult.Status.INVALID_TARGET)


func take_item() -> ItemTransferResult:
	return ItemTransferResult.rejected(ItemTransferResult.Status.INVALID_TARGET)


func reset() -> void:
	pass


func _claim_item(block: StandardBlock) -> bool:
	return block != null and block.try_claim(self)


func _release_item(block: StandardBlock) -> bool:
	return block != null and block.release_claim(self)


func _owns_item(block: StandardBlock) -> bool:
	return block != null and block.is_claimed_by(self)

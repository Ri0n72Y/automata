extends Resource
class_name ItemSourceInterface

@export var interaction_cells: Array[Vector2i] = []


func set_interaction_cells(cells: Array[Vector2i]) -> void:
	interaction_cells.clear()
	interaction_cells.append_array(cells)


func get_interaction_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.append_array(interaction_cells)
	return result


func get_output_item_type() -> StringName:
	return &""


func is_available() -> bool:
	return false


func is_infinite() -> bool:
	return false


func take_item() -> ItemTransferResult:
	return ItemTransferResult.rejected(ItemTransferResult.Status.INVALID_TARGET)


func prepare_take_item() -> ItemTransferResult:
	return take_item()


func commit_prepared_take_item(_item: StandardBlock) -> bool:
	return true


func rollback_prepared_take_item(_item: StandardBlock) -> bool:
	return true


func reset() -> void:
	pass

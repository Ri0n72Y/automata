extends RefCounted
class_name ItemSourceInterface

var _interaction_cells: Array[Vector2i] = []


func set_interaction_cells(cells: Array[Vector2i]) -> void:
	_interaction_cells.clear()
	_interaction_cells.append_array(cells)


func get_interaction_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	result.append_array(_interaction_cells)
	return result


func get_output_item_type() -> StringName:
	return &""


func is_available() -> bool:
	return false


func is_infinite() -> bool:
	return false


func take_item() -> ItemTransferResult:
	return ItemTransferResult.rejected(ItemTransferResult.Status.INVALID_TARGET)


func reset() -> void:
	pass

extends Node3D
class_name Scene01ItemSourceNode

@export var interaction_cells: Array[Vector2i] = []

var _source: ItemSourceInterface


func configure(source: ItemSourceInterface) -> bool:
	if source == null:
		return false
	_source = source
	_source.set_interaction_cells(interaction_cells)
	return true


func get_source_interface() -> ItemSourceInterface:
	return _source


func get_output_item_type() -> StringName:
	return _source.get_output_item_type() if _source != null else &""


func is_available() -> bool:
	return _source != null and _source.is_available()


func is_infinite() -> bool:
	return _source != null and _source.is_infinite()


func get_interaction_cells() -> Array[Vector2i]:
	if _source != null:
		return _source.get_interaction_cells()
	var empty: Array[Vector2i] = []
	return empty


func take_item() -> ItemTransferResult:
	if _source == null:
		return ItemTransferResult.rejected(ItemTransferResult.Status.INVALID_TARGET)
	return _source.take_item()

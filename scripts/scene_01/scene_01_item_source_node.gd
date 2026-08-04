extends Node3D
class_name Scene01ItemSourceNode

@export var source_resource: ItemSourceInterface


func is_configured() -> bool:
	return source_resource != null


func get_source_interface() -> ItemSourceInterface:
	return source_resource


func get_output_item_type() -> StringName:
	return source_resource.get_output_item_type() if source_resource != null else &""


func is_available() -> bool:
	return source_resource != null and source_resource.is_available()


func is_infinite() -> bool:
	return source_resource != null and source_resource.is_infinite()


func get_interaction_cells() -> Array[Vector2i]:
	if source_resource != null:
		return source_resource.get_interaction_cells()
	var empty: Array[Vector2i] = []
	return empty


func take_item() -> ItemTransferResult:
	if source_resource == null:
		return ItemTransferResult.rejected(ItemTransferResult.Status.INVALID_TARGET)
	return source_resource.take_item()

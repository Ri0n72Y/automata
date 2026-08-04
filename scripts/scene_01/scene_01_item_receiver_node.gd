extends Node3D
class_name Scene01ItemReceiverNode

@export var receiver_resource: ItemReceiverInterface


func is_configured() -> bool:
	return receiver_resource != null


func get_receiver_interface() -> ItemReceiverInterface:
	return receiver_resource


func get_accepted_item_types() -> PackedStringArray:
	return receiver_resource.get_accepted_item_types() if receiver_resource != null else PackedStringArray()


func accepts_item_type(item_type: StringName) -> bool:
	return receiver_resource != null and receiver_resource.accepts_item_type(item_type)


func get_interaction_cells() -> Array[Vector2i]:
	if receiver_resource != null:
		return receiver_resource.get_interaction_cells()
	var empty: Array[Vector2i] = []
	return empty


func get_current_count() -> int:
	return receiver_resource.get_current_count() if receiver_resource != null else 0


func get_capacity() -> int:
	return receiver_resource.get_capacity() if receiver_resource != null else 0


func put_item(item: Variant) -> ItemTransferResult:
	if receiver_resource == null:
		return ItemTransferResult.rejected(ItemTransferResult.Status.INVALID_TARGET)
	return receiver_resource.put_item(item)


func take_item() -> ItemTransferResult:
	if receiver_resource == null:
		return ItemTransferResult.rejected(ItemTransferResult.Status.INVALID_TARGET)
	return receiver_resource.take_item()

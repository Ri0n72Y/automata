extends Node3D
class_name Scene01ItemReceiverNode

@export var interaction_cells: Array[Vector2i] = []

var _receiver: ItemReceiverInterface


func configure(receiver: ItemReceiverInterface) -> bool:
	if receiver == null:
		return false
	_receiver = receiver
	_receiver.set_interaction_cells(interaction_cells)
	return true


func get_receiver_interface() -> ItemReceiverInterface:
	return _receiver


func get_accepted_item_types() -> PackedStringArray:
	return _receiver.get_accepted_item_types() if _receiver != null else PackedStringArray()


func accepts_item_type(item_type: StringName) -> bool:
	return _receiver != null and _receiver.accepts_item_type(item_type)


func get_interaction_cells() -> Array[Vector2i]:
	if _receiver != null:
		return _receiver.get_interaction_cells()
	var empty: Array[Vector2i] = []
	return empty


func get_current_count() -> int:
	return _receiver.get_current_count() if _receiver != null else 0


func get_capacity() -> int:
	return _receiver.get_capacity() if _receiver != null else 0


func put_item(item: Variant) -> ItemTransferResult:
	if _receiver == null:
		return ItemTransferResult.rejected(ItemTransferResult.Status.INVALID_TARGET)
	return _receiver.put_item(item)


func take_item() -> ItemTransferResult:
	if _receiver == null:
		return ItemTransferResult.rejected(ItemTransferResult.Status.INVALID_TARGET)
	return _receiver.take_item()

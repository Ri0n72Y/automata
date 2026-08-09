extends ItemReceiverInterface
class_name GroundBlockCellInterface

const ItemTransferResultScript := preload("res://scripts/objects/item_transfer_result.gd")
const StandardBlockScript := preload("res://scripts/objects/standard_block.gd")

var _field_ref: WeakRef
var _cell: Vector2i = Vector2i.ZERO


func configure(field: Object, cell: Vector2i) -> bool:
	if field == null:
		return false
	if (
		not field.has_method("put_item")
		or not field.has_method("take_item")
		or not field.has_method("has_item")
		or not field.has_method("can_access_cell")
	):
		return false
	_field_ref = weakref(field)
	_cell = cell
	set_interaction_cells([cell])
	return true


func get_cell() -> Vector2i:
	return _cell


func get_accepted_item_types() -> PackedStringArray:
	return PackedStringArray([StandardBlockScript.TYPE_ID])


func can_take_item() -> bool:
	var field := _get_field()
	return (
		field != null
		and bool(field.call("can_access_cell", _cell))
		and bool(field.call("has_item", _cell))
	)


func get_current_count() -> int:
	return 1 if can_take_item() else 0


func get_capacity() -> int:
	return 1


func put_item(item: Variant) -> ItemTransferResultScript:
	var field := _get_field()
	if field == null:
		return ItemTransferResultScript.rejected(ItemTransferResultScript.Status.INVALID_TARGET)
	return field.call("put_item", _cell, item) as ItemTransferResultScript


func take_item() -> ItemTransferResultScript:
	var field := _get_field()
	if field == null:
		return ItemTransferResultScript.rejected(ItemTransferResultScript.Status.INVALID_TARGET)
	return field.call("take_item", _cell) as ItemTransferResultScript


func _get_field() -> Object:
	if _field_ref == null:
		return null
	return _field_ref.get_ref()

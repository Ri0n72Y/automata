extends ItemReceiverInterface

const ItemTransferResultScript := preload("res://scripts/objects/item_transfer_result.gd")
const StandardBlockScript := preload("res://scripts/objects/standard_block.gd")

var rejection_status: int = ItemTransferResultScript.Status.INVALID_TARGET
var put_attempts: int = 0


func configure_rejection(status: int, cells: Array[Vector2i]) -> bool:
	if status == ItemTransferResultScript.Status.ACCEPTED or cells.is_empty():
		return false
	rejection_status = status
	set_interaction_cells(cells)
	return true


func get_accepted_item_types() -> PackedStringArray:
	return PackedStringArray([StandardBlockScript.TYPE_ID])


func get_capacity() -> int:
	return 1


func put_item(_item: Variant) -> ItemTransferResultScript:
	put_attempts += 1
	return ItemTransferResultScript.rejected(rejection_status)

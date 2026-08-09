extends RefCounted
class_name GroundBlockField

const GroundBlockCellInterfaceScript := preload("res://scripts/objects/ground_block_cell_interface.gd")
const ItemTransferResultScript := preload("res://scripts/objects/item_transfer_result.gd")
const StandardBlockScript := preload("res://scripts/objects/standard_block.gd")

signal cell_changed(cell: Vector2i, previous_item: StandardBlockScript, current_item: StandardBlockScript)

var _items: Dictionary = {}
var _interfaces: Dictionary = {}


func get_cell_interface(cell: Vector2i) -> GroundBlockCellInterfaceScript:
	var existing := _interfaces.get(cell) as GroundBlockCellInterfaceScript
	if existing != null:
		return existing
	var interaction := GroundBlockCellInterfaceScript.new()
	if not interaction.configure(self, cell):
		return null
	_interfaces[cell] = interaction
	return interaction


func has_item(cell: Vector2i) -> bool:
	return _items.has(cell)


func get_item(cell: Vector2i) -> StandardBlockScript:
	return _items.get(cell) as StandardBlockScript


func get_occupied_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell_variant in _items.keys():
		var cell: Vector2i = cell_variant
		cells.append(cell)
	return cells


func put_item(cell: Vector2i, item: Variant) -> ItemTransferResultScript:
	var block := item as StandardBlockScript
	if block == null or not block.is_valid():
		return ItemTransferResultScript.rejected(ItemTransferResultScript.Status.TYPE_MISMATCH)
	if has_item(cell):
		return ItemTransferResultScript.rejected(ItemTransferResultScript.Status.OCCUPIED)
	if block.is_claimed() or not block.try_claim(self):
		return ItemTransferResultScript.rejected(ItemTransferResultScript.Status.ALREADY_CONTAINED)
	_items[cell] = block
	cell_changed.emit(cell, null, block)
	return ItemTransferResultScript.accepted(block)


func take_item(cell: Vector2i) -> ItemTransferResultScript:
	var block := get_item(cell)
	if block == null:
		return ItemTransferResultScript.rejected(ItemTransferResultScript.Status.EMPTY)
	if not block.is_claimed_by(self):
		return ItemTransferResultScript.rejected(ItemTransferResultScript.Status.INVALID_TARGET)
	_items.erase(cell)
	if not block.release_claim(self):
		_items[cell] = block
		return ItemTransferResultScript.rejected(ItemTransferResultScript.Status.INVALID_TARGET)
	cell_changed.emit(cell, block, null)
	return ItemTransferResultScript.accepted(block)


func reset() -> void:
	var occupied := get_occupied_cells()
	for cell in occupied:
		var block := get_item(cell)
		_items.erase(cell)
		if block != null and block.is_claimed_by(self):
			block.release_claim(self)
		cell_changed.emit(cell, block, null)

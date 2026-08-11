extends Resource
class_name GroundBlockField

const GroundBlockCellInterfaceScript := preload("res://scripts/objects/ground_block_cell_interface.gd")
const ItemTransferResultScript := preload("res://scripts/objects/item_transfer_result.gd")
const StandardBlockScript := preload("res://scripts/objects/standard_block.gd")

signal cell_changed(cell: Vector2i, previous_item: StandardBlockScript, current_item: StandardBlockScript)

var _items: Dictionary = {}
var _interfaces: Dictionary = {}
var _valid_cells: Dictionary = {}
var _has_cell_policy: bool = false
var _access_guard_ref: WeakRef
var _access_guard_method: StringName = &""
var _has_access_guard: bool = false


func configure_valid_cells(cells: Array[Vector2i]) -> void:
	var next_valid_cells: Dictionary = {}
	for cell in cells:
		next_valid_cells[cell] = true
	if _has_cell_policy and next_valid_cells == _valid_cells:
		return
	_valid_cells = next_valid_cells
	_has_cell_policy = true
	for cell_variant in get_occupied_cells():
		var cell: Vector2i = cell_variant
		if _valid_cells.has(cell):
			continue
		var block := _items.get(cell) as StandardBlockScript
		_items.erase(cell)
		if block != null and block.is_claimed_by(self):
			block.release_claim(self)
		cell_changed.emit(cell, block, null)
	for cell_variant in _interfaces.keys():
		var cell: Vector2i = cell_variant
		if not _valid_cells.has(cell):
			_interfaces.erase(cell)


func configure_access_guard(owner: Object, method_name: StringName) -> bool:
	if owner == null or method_name == &"" or not owner.has_method(method_name):
		return false
	_access_guard_ref = weakref(owner)
	_access_guard_method = method_name
	_has_access_guard = true
	return true


func is_configured() -> bool:
	return _has_cell_policy


func is_cell_allowed(cell: Vector2i) -> bool:
	return _has_cell_policy and _valid_cells.has(cell)


func can_access_cell(cell: Vector2i) -> bool:
	if not is_cell_allowed(cell):
		return false
	if not _has_access_guard:
		return true
	if _access_guard_ref == null:
		return false
	var guard_owner: Object = _access_guard_ref.get_ref() as Object
	if guard_owner == null or not guard_owner.has_method(_access_guard_method):
		return false
	return bool(guard_owner.call(_access_guard_method, cell))


func get_cell_interface(cell: Vector2i) -> GroundBlockCellInterfaceScript:
	if not can_access_cell(cell):
		return null
	var existing := _interfaces.get(cell) as GroundBlockCellInterfaceScript
	if existing != null:
		return existing
	var interaction := GroundBlockCellInterfaceScript.new()
	if not interaction.configure(self, cell):
		return null
	_interfaces[cell] = interaction
	return interaction


func has_item(cell: Vector2i) -> bool:
	return is_cell_allowed(cell) and _items.has(cell)


func get_item(cell: Vector2i) -> StandardBlockScript:
	if not is_cell_allowed(cell):
		return null
	return _items.get(cell) as StandardBlockScript


func get_occupied_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell_variant in _items.keys():
		var cell: Vector2i = cell_variant
		cells.append(cell)
	return cells


func put_item(cell: Vector2i, item: Variant) -> ItemTransferResultScript:
	if not can_access_cell(cell):
		return ItemTransferResultScript.rejected(ItemTransferResultScript.Status.INVALID_TARGET)
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
	if not can_access_cell(cell):
		return ItemTransferResultScript.rejected(ItemTransferResultScript.Status.INVALID_TARGET)
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
		var block := _items.get(cell) as StandardBlockScript
		_items.erase(cell)
		if block != null and block.is_claimed_by(self):
			block.release_claim(self)
		cell_changed.emit(cell, block, null)

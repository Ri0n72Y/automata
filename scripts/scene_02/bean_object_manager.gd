class_name BeanObjectManager
extends Scene01ObjectManager

## Bean Sorting scene object manager: exposes bean sources/targets through the
## same ItemSource/ItemReceiver interfaces the GrabDrop pipeline already uses.
## Ground placement is intentionally unsupported (beans must not be re-pickable).

var _sources: Array[BeanSourceNode] = []
var _targets: Array[BeanTargetNode] = []
var _interfaces: Array[Variant] = []
var _occupied_cells: Dictionary = {}
var _beans_initialized := false


func _ready() -> void:
	_initialize_bean_objects()


func _initialize_bean_objects() -> bool:
	_sources.clear()
	_targets.clear()
	_interfaces.clear()
	_occupied_cells.clear()
	for child in get_children():
		if child is BeanSourceNode:
			var source := child as BeanSourceNode
			_sources.append(source)
			_interfaces.append(source.get_source_interface())
			_occupied_cells[source.get_occupied_cell()] = true
		elif child is BeanTargetNode:
			var target := child as BeanTargetNode
			_targets.append(target)
			_interfaces.append(target.get_receiver_interface())
			_occupied_cells[target.get_occupied_cell()] = true
	_beans_initialized = not _sources.is_empty() and not _targets.is_empty()
	return _beans_initialized


func initialize_objects() -> bool:
	if _beans_initialized:
		return true
	return _initialize_bean_objects()


func is_initialized() -> bool:
	return _beans_initialized


func reset_objects() -> bool:
	if not _beans_initialized:
		return false
	for source in _sources:
		source.inventory.reset()
	for target in _targets:
		target.inventory.reset()
	return true


func refresh_ground_cell_policy() -> void:
	pass


func get_item_interaction_interfaces() -> Array[Variant]:
	return _interfaces.duplicate()


func is_static_item_cell_occupied(cell: Vector2i) -> bool:
	return _occupied_cells.has(cell)


func get_sources() -> Array[BeanSourceNode]:
	return _sources.duplicate()


func get_targets() -> Array[BeanTargetNode]:
	return _targets.duplicate()


func can_drop_item_to_ground_cell(_cell: Vector2i) -> bool:
	return false


func can_pick_up_item_from_ground_cell(_cell: Vector2i) -> bool:
	return false


func get_ground_cell_interface(_cell: Vector2i) -> ItemReceiverInterface:
	return null


func is_ground_cell_interactable(_cell: Vector2i) -> bool:
	return false


func has_ground_block(_cell: Vector2i) -> bool:
	return false


func get_standard_box() -> StandardBox:
	return null

extends Node3D
class_name Scene01ObjectManager

signal box_count_changed(previous_count: int, current_count: int)
signal pile_produced_count_changed(previous_count: int, current_count: int)

@onready var _block_pile_node: Scene01ItemSourceNode = %InfiniteBlockPile
@onready var _standard_box_node: Scene01ItemReceiverNode = %StandardBox


func _ready() -> void:
	if not initialize_objects():
		push_error("Scene 01 static object resources failed to initialize.")


func initialize_objects() -> bool:
	if _block_pile_node == null or _standard_box_node == null:
		return false
	if not _block_pile_node.is_configured() or not _standard_box_node.is_configured():
		return false
	var block_pile := _block_pile_node.get_source_interface() as InfiniteBlockPile
	var standard_box := _standard_box_node.get_receiver_interface() as StandardBox
	if block_pile == null or standard_box == null:
		return false
	if not block_pile.produced_count_changed.is_connected(_on_pile_produced_count_changed):
		block_pile.produced_count_changed.connect(_on_pile_produced_count_changed)
	if not standard_box.count_changed.is_connected(_on_box_count_changed):
		standard_box.count_changed.connect(_on_box_count_changed)
	return true


func reset_objects() -> void:
	if not initialize_objects():
		return
	get_block_pile().reset()
	get_standard_box().reset()


func get_item_interaction_interfaces() -> Array[Variant]:
	var interfaces: Array[Variant] = []
	for node in find_children("*", "", true, false):
		if node.has_method("get_source_interface"):
			var source = node.call("get_source_interface")
			if source != null and not interfaces.has(source):
				interfaces.append(source)
		if node.has_method("get_receiver_interface"):
			var receiver = node.call("get_receiver_interface")
			if receiver != null and not interfaces.has(receiver):
				interfaces.append(receiver)
	return interfaces


func get_block_pile() -> InfiniteBlockPile:
	if _block_pile_node == null:
		return null
	return _block_pile_node.get_source_interface() as InfiniteBlockPile


func get_standard_box() -> StandardBox:
	if _standard_box_node == null:
		return null
	return _standard_box_node.get_receiver_interface() as StandardBox


func get_block_pile_source() -> ItemSourceInterface:
	if _block_pile_node == null:
		return null
	return _block_pile_node.get_source_interface()


func get_standard_box_receiver() -> ItemReceiverInterface:
	if _standard_box_node == null:
		return null
	return _standard_box_node.get_receiver_interface()


func get_block_pile_node() -> Scene01ItemSourceNode:
	return _block_pile_node


func get_standard_box_node() -> Scene01ItemReceiverNode:
	return _standard_box_node


func _on_box_count_changed(previous_count: int, current_count: int) -> void:
	box_count_changed.emit(previous_count, current_count)


func _on_pile_produced_count_changed(previous_count: int, current_count: int) -> void:
	pile_produced_count_changed.emit(previous_count, current_count)

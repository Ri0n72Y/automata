extends Node3D
class_name Scene01ObjectManager

signal box_count_changed(previous_count: int, current_count: int)
signal pile_produced_count_changed(previous_count: int, current_count: int)

@onready var _block_pile_node: Scene01ItemSourceNode = %InfiniteBlockPile
@onready var _standard_box_node: Scene01ItemReceiverNode = %StandardBox

var _block_pile: InfiniteBlockPile
var _standard_box: StandardBox


func _ready() -> void:
	initialize_objects()


func initialize_objects() -> bool:
	if _block_pile == null:
		_block_pile = InfiniteBlockPile.new()
		_block_pile.produced_count_changed.connect(_on_pile_produced_count_changed)
	if _standard_box == null:
		_standard_box = StandardBox.new()
		_standard_box.count_changed.connect(_on_box_count_changed)
	if _block_pile_node == null or _standard_box_node == null:
		return false
	return (
		_block_pile_node.configure(_block_pile)
		and _standard_box_node.configure(_standard_box)
	)


func reset_objects() -> void:
	if not initialize_objects():
		return
	_block_pile.reset()
	_standard_box.reset()


func get_block_pile() -> InfiniteBlockPile:
	initialize_objects()
	return _block_pile


func get_standard_box() -> StandardBox:
	initialize_objects()
	return _standard_box


func get_block_pile_source() -> ItemSourceInterface:
	if not initialize_objects():
		return null
	return _block_pile_node.get_source_interface()


func get_standard_box_receiver() -> ItemReceiverInterface:
	if not initialize_objects():
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

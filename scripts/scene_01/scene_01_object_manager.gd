extends Node3D
class_name Scene01ObjectManager

signal box_count_changed(previous_count: int, current_count: int)
signal pile_produced_count_changed(previous_count: int, current_count: int)

@onready var block_pile_node: Scene01ItemSourceNode = %InfiniteBlockPile
@onready var standard_box_node: Scene01ItemReceiverNode = %StandardBox

var block_pile: InfiniteBlockPile
var standard_box: StandardBox


func _ready() -> void:
	initialize_objects()


func initialize_objects() -> bool:
	if block_pile == null:
		block_pile = InfiniteBlockPile.new()
		block_pile.produced_count_changed.connect(_on_pile_produced_count_changed)
	if standard_box == null:
		standard_box = StandardBox.new()
		standard_box.count_changed.connect(_on_box_count_changed)
	if block_pile_node == null or standard_box_node == null:
		return false
	return (
		block_pile_node.configure(block_pile)
		and standard_box_node.configure(standard_box)
	)


func reset_objects() -> void:
	if not initialize_objects():
		return
	block_pile.reset()
	standard_box.reset()


func get_block_pile() -> InfiniteBlockPile:
	initialize_objects()
	return block_pile


func get_standard_box() -> StandardBox:
	initialize_objects()
	return standard_box


func get_block_pile_source() -> ItemSourceInterface:
	if not initialize_objects():
		return null
	return block_pile_node.get_source_interface()


func get_standard_box_receiver() -> ItemReceiverInterface:
	if not initialize_objects():
		return null
	return standard_box_node.get_receiver_interface()


func get_block_pile_node() -> Scene01ItemSourceNode:
	return block_pile_node


func get_standard_box_node() -> Scene01ItemReceiverNode:
	return standard_box_node


func _on_box_count_changed(previous_count: int, current_count: int) -> void:
	box_count_changed.emit(previous_count, current_count)


func _on_pile_produced_count_changed(previous_count: int, current_count: int) -> void:
	pile_produced_count_changed.emit(previous_count, current_count)

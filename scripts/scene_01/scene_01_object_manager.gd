extends Node3D
class_name Scene01ObjectManager

signal box_count_changed(previous_count: int, current_count: int)
signal pile_produced_count_changed(previous_count: int, current_count: int)

var block_pile: InfiniteBlockPile
var standard_box: StandardBox


func _ready() -> void:
	initialize_objects()


func initialize_objects() -> void:
	if block_pile == null:
		block_pile = InfiniteBlockPile.new()
		block_pile.produced_count_changed.connect(_on_pile_produced_count_changed)
	if standard_box == null:
		standard_box = StandardBox.new()
		standard_box.count_changed.connect(_on_box_count_changed)


func reset_objects() -> void:
	initialize_objects()
	block_pile.reset()
	standard_box.reset()


func get_block_pile() -> InfiniteBlockPile:
	initialize_objects()
	return block_pile


func get_standard_box() -> StandardBox:
	initialize_objects()
	return standard_box


func _on_box_count_changed(previous_count: int, current_count: int) -> void:
	box_count_changed.emit(previous_count, current_count)


func _on_pile_produced_count_changed(previous_count: int, current_count: int) -> void:
	pile_produced_count_changed.emit(previous_count, current_count)

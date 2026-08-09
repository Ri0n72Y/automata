extends Node3D
class_name Scene01ObjectManager

const GroundBlockFieldScript := preload("res://scripts/objects/ground_block_field.gd")
const StandardBlockScene := preload("res://scenes/scene_01/objects/standard_block_placeholder.tscn")

signal box_count_changed(previous_count: int, current_count: int)
signal pile_produced_count_changed(previous_count: int, current_count: int)
signal ground_block_changed(cell: Vector2i, has_item: bool)

@onready var _block_pile_node: Scene01ItemSourceNode = %InfiniteBlockPile
@onready var _standard_box_node: Scene01ItemReceiverNode = %StandardBox
@onready var _ground_visual_root: Node3D = %GroundBlockVisuals

var _ground_block_field := GroundBlockFieldScript.new()
var _ground_visuals: Dictionary = {}


func _ready() -> void:
	if not initialize_objects():
		push_error("Scene 01 static object resources failed to initialize.")


func initialize_objects() -> bool:
	if _block_pile_node == null or _standard_box_node == null or _ground_visual_root == null:
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
	var ground_changed_callable := Callable(self, "_on_ground_cell_changed")
	if not _ground_block_field.cell_changed.is_connected(ground_changed_callable):
		_ground_block_field.cell_changed.connect(ground_changed_callable)
	return true


func reset_objects() -> void:
	if not initialize_objects():
		return
	_ground_block_field.reset()
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


func get_ground_block_field() -> GroundBlockFieldScript:
	return _ground_block_field


func get_ground_cell_interface(cell: Vector2i) -> ItemReceiverInterface:
	return _ground_block_field.get_cell_interface(cell)


func has_ground_block(cell: Vector2i) -> bool:
	return _ground_block_field.has_item(cell)


func get_ground_block_visual(cell: Vector2i) -> Node3D:
	var visual: Variant = _ground_visuals.get(cell)
	if visual is Node3D and is_instance_valid(visual):
		return visual as Node3D
	return null


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


func _on_ground_cell_changed(
	cell: Vector2i,
	_previous_item: Variant,
	current_item: Variant
) -> void:
	_remove_ground_visual(cell)
	if current_item != null:
		_create_ground_visual(cell)
	ground_block_changed.emit(cell, current_item != null)


func _create_ground_visual(cell: Vector2i) -> void:
	if _ground_visual_root == null:
		return
	var visual := StandardBlockScene.instantiate() as Node3D
	if visual == null:
		return
	visual.name = "GroundBlock_%d_%d" % [cell.x, cell.y]
	_ground_visual_root.add_child(visual)
	var scene := get_tree().current_scene
	var grid_root := scene.get_node_or_null("SceneRoot/GridRoot") as Node3D if scene != null else null
	if scene != null and grid_root != null and scene.has_method("grid_cell_to_world"):
		var world_position: Vector3 = scene.call("grid_cell_to_world", cell)
		visual.position = grid_root.to_local(world_position)
	else:
		visual.position = Vector3(float(cell.x) + 0.5, 0.0, float(cell.y) + 0.5)
	_ground_visuals[cell] = visual


func _remove_ground_visual(cell: Vector2i) -> void:
	var visual := get_ground_block_visual(cell)
	_ground_visuals.erase(cell)
	if visual == null:
		return
	if visual.get_parent() != null:
		visual.get_parent().remove_child(visual)
	visual.free()


func _on_box_count_changed(previous_count: int, current_count: int) -> void:
	box_count_changed.emit(previous_count, current_count)


func _on_pile_produced_count_changed(previous_count: int, current_count: int) -> void:
	pile_produced_count_changed.emit(previous_count, current_count)

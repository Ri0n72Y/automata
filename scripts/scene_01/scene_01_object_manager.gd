extends Node3D
class_name Scene01ObjectManager

const GroundBlockFieldScript := preload("res://scripts/objects/ground_block_field.gd")
const StandardBlockScene := preload("res://scenes/scene_01/objects/standard_block_placeholder.tscn")
const VehicleActorScript := preload("res://scripts/vehicles/vehicle_actor.gd")
const Scene01VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")

signal box_count_changed(previous_count: int, current_count: int)
signal pile_produced_count_changed(previous_count: int, current_count: int)
signal ground_block_changed(cell: Vector2i, has_item: bool)

@export var ground_block_field: GroundBlockFieldScript
@export var scene_controller_path: NodePath = NodePath("../../..")
@export var vehicle_manager_path: NodePath = NodePath("../../RobotRoot/Scene01VehicleManager")

@onready var _block_pile_node: Scene01ItemSourceNode = %InfiniteBlockPile
@onready var _standard_box_node: Scene01ItemReceiverNode = %StandardBox
@onready var _ground_visual_root: Node3D = %GroundBlockVisuals

var _ground_visuals: Dictionary = {}
var _static_item_interaction_interfaces: Array[Variant] = []


func _ready() -> void:
	if not initialize_objects():
		push_error("Scene 01 static object resources failed to initialize.")


func initialize_objects() -> bool:
	if (
		_block_pile_node == null
		or _standard_box_node == null
		or _ground_visual_root == null
		or ground_block_field == null
		or _get_scene_controller() == null
		or _get_vehicle_manager() == null
	):
		return false
	if not _block_pile_node.is_configured() or not _standard_box_node.is_configured():
		return false
	var block_pile := _block_pile_node.get_source_interface() as InfiniteBlockPile
	var standard_box := _standard_box_node.get_receiver_interface() as StandardBox
	if block_pile == null or standard_box == null:
		return false
	_cache_static_item_interaction_interfaces()
	refresh_ground_cell_policy()
	if not ground_block_field.is_configured():
		return false
	if not block_pile.produced_count_changed.is_connected(_on_pile_produced_count_changed):
		block_pile.produced_count_changed.connect(_on_pile_produced_count_changed)
	if not standard_box.count_changed.is_connected(_on_box_count_changed):
		standard_box.count_changed.connect(_on_box_count_changed)
	var ground_changed_callable := Callable(self, "_on_ground_cell_changed")
	if not ground_block_field.cell_changed.is_connected(ground_changed_callable):
		ground_block_field.cell_changed.connect(ground_changed_callable)
	return true


func refresh_ground_cell_policy() -> void:
	if ground_block_field == null:
		return
	var scene_controller := _get_scene_controller()
	if scene_controller == null:
		return
	if not scene_controller.has_method("get_grid_size") or not scene_controller.has_method(
		"is_grid_cell_walkable"
	):
		return
	if _static_item_interaction_interfaces.is_empty():
		_cache_static_item_interaction_interfaces()
	var static_blocked_cells: Dictionary = {}
	for interaction_interface in _static_item_interaction_interfaces:
		for interaction_cell in _get_interaction_cells(interaction_interface):
			static_blocked_cells[interaction_cell] = true
	var grid_size: Vector2i = scene_controller.call("get_grid_size")
	var valid_cells: Array[Vector2i] = []
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var cell := Vector2i(x, y)
			if (
				bool(scene_controller.call("is_grid_cell_walkable", cell))
				and not static_blocked_cells.has(cell)
			):
				valid_cells.append(cell)
	ground_block_field.configure_valid_cells(valid_cells)


func reset_objects() -> void:
	if not initialize_objects():
		return
	ground_block_field.reset()
	get_block_pile().reset()
	get_standard_box().reset()


func get_item_interaction_interfaces() -> Array[Variant]:
	return _static_item_interaction_interfaces.duplicate()


func get_ground_block_field() -> GroundBlockFieldScript:
	return ground_block_field


func is_ground_cell_interactable(cell: Vector2i) -> bool:
	if ground_block_field == null or not ground_block_field.is_cell_allowed(cell):
		return false
	for interaction_interface in _static_item_interaction_interfaces:
		if _get_interaction_cells(interaction_interface).has(cell):
			return false
	var vehicle_manager := _get_vehicle_manager()
	if vehicle_manager == null:
		return false
	for vehicle_node in vehicle_manager.get_vehicles():
		var actor := vehicle_node as VehicleActorScript
		if actor != null and actor.get_occupied_cells().has(cell):
			return false
	return true


func get_ground_cell_interface(cell: Vector2i) -> ItemReceiverInterface:
	if ground_block_field == null or not is_ground_cell_interactable(cell):
		return null
	return ground_block_field.get_cell_interface(cell)


func has_ground_block(cell: Vector2i) -> bool:
	return ground_block_field != null and ground_block_field.has_item(cell)


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


func _cache_static_item_interaction_interfaces() -> void:
	_static_item_interaction_interfaces.clear()
	for node in find_children("*", "", true, false):
		if node.has_method("get_source_interface"):
			var source = node.call("get_source_interface")
			if source != null and not _static_item_interaction_interfaces.has(source):
				_static_item_interaction_interfaces.append(source)
		if node.has_method("get_receiver_interface"):
			var receiver = node.call("get_receiver_interface")
			if receiver != null and not _static_item_interaction_interfaces.has(receiver):
				_static_item_interaction_interfaces.append(receiver)


func _get_interaction_cells(target: Variant) -> Array[Vector2i]:
	var source := target as ItemSourceInterface
	if source != null:
		return source.get_interaction_cells()
	var receiver := target as ItemReceiverInterface
	if receiver != null:
		return receiver.get_interaction_cells()
	var empty_cells: Array[Vector2i] = []
	return empty_cells


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
	var scene_controller := _get_scene_controller()
	if scene_controller == null or not scene_controller.has_method("grid_cell_to_world"):
		return
	var visual := StandardBlockScene.instantiate() as Node3D
	if visual == null:
		return
	visual.name = "GroundBlock_%d_%d" % [cell.x, cell.y]
	_ground_visual_root.add_child(visual)
	var world_position: Vector3 = scene_controller.call("grid_cell_to_world", cell)
	visual.position = _ground_visual_root.to_local(world_position)
	_ground_visuals[cell] = visual


func _remove_ground_visual(cell: Vector2i) -> void:
	var visual := get_ground_block_visual(cell)
	_ground_visuals.erase(cell)
	if visual == null:
		return
	if visual.get_parent() != null:
		visual.get_parent().remove_child(visual)
	visual.free()


func _get_scene_controller() -> Node:
	if scene_controller_path.is_empty():
		return null
	return get_node_or_null(scene_controller_path)


func _get_vehicle_manager() -> Scene01VehicleManagerScript:
	if vehicle_manager_path.is_empty():
		return null
	return get_node_or_null(vehicle_manager_path) as Scene01VehicleManagerScript


func _on_box_count_changed(previous_count: int, current_count: int) -> void:
	box_count_changed.emit(previous_count, current_count)


func _on_pile_produced_count_changed(previous_count: int, current_count: int) -> void:
	pile_produced_count_changed.emit(previous_count, current_count)
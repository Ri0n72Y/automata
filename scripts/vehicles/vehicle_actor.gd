class_name VehicleActor
extends Node3D

const VehicleDefinitionScript := preload("res://scripts/vehicles/vehicle_definition.gd")
const VehicleRuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")

@export var vehicle_selection_layer: int = 2

var definition: VehicleDefinitionScript
var runtime_state: VehicleRuntimeStateScript
var controller: Node
var cell_size: float = 1.0

var _visual_root: Node3D
var _selection_area: Area3D
var _debug_label: Label3D
var _visual_parts: Dictionary = {}
var _visual_generation: int = 0


func _ready() -> void:
	sync_from_state()


func configure(
	p_definition: VehicleDefinitionScript,
	p_runtime_state: VehicleRuntimeStateScript,
	p_controller: Node,
	p_cell_size: float
) -> bool:
	if p_definition == null or p_runtime_state == null or p_controller == null:
		push_error("Vehicle actor requires definition, runtime state, and controller.")
		return false
	if not p_definition.is_configured():
		push_error("Vehicle actor requires a configured definition.")
		return false
	if p_runtime_state.definition != p_definition:
		push_error("Vehicle actor definition must match its runtime state definition.")
		return false

	definition = p_definition
	runtime_state = p_runtime_state
	controller = p_controller
	cell_size = maxf(p_cell_size, 0.01)
	name = "Vehicle_%s" % String(definition.assembly_id)
	_rebuild_visual()
	sync_from_state()
	return true


func sync_from_state() -> void:
	if definition == null or runtime_state == null or controller == null:
		return
	if not is_inside_tree():
		return
	global_position = controller.call(
		"grid_footprint_center_to_world",
		runtime_state.anchor_cell,
		definition.footprint
	)
	var grid_basis: Basis = controller.call("get_grid_world_basis")
	global_basis = grid_basis * Basis(
		Vector3.UP,
		-float(runtime_state.facing) * PI * 0.5
	)
	_update_debug_label()


func reset_actor() -> void:
	if runtime_state == null:
		return
	runtime_state.reset()
	sync_from_state()


func get_vehicle_id() -> StringName:
	if definition == null:
		return &""
	return definition.assembly_id


func get_occupied_cells() -> Array[Vector2i]:
	var occupied_cells: Array[Vector2i] = []
	if definition == null or runtime_state == null:
		return occupied_cells
	for offset_y in range(definition.footprint.y):
		for offset_x in range(definition.footprint.x):
			occupied_cells.append(
				runtime_state.anchor_cell + Vector2i(offset_x, offset_y)
			)
	return occupied_cells


func get_selection_area() -> Area3D:
	return _selection_area


func get_visual_part(part_name: StringName) -> Node3D:
	var part: Variant = _visual_parts.get(part_name)
	if part is Node3D and is_instance_valid(part):
		return part
	return null


func get_debug_label_text() -> String:
	if _debug_label == null or not is_instance_valid(_debug_label):
		return ""
	return _debug_label.text


func _rebuild_visual() -> void:
	_visual_generation += 1
	_visual_parts.clear()
	if _visual_root != null and is_instance_valid(_visual_root):
		_visual_root.queue_free()

	_visual_root = Node3D.new()
	_visual_root.name = "VisualRoot_%d" % _visual_generation
	add_child(_visual_root)

	var footprint_size := Vector3(
		float(definition.footprint.x) * cell_size * 0.82,
		cell_size * 0.45,
		float(definition.footprint.y) * cell_size * 0.82
	)
	var body := _create_box_part(&"Body", footprint_size)
	body.position.y = footprint_size.y * 0.5

	if definition.vehicle_kind == VehicleDefinitionScript.VehicleKind.ARM:
		_build_arm_visual(footprint_size)
	elif definition.vehicle_kind == VehicleDefinitionScript.VehicleKind.TRANSPORT:
		_build_transport_visual(footprint_size)

	_selection_area = Area3D.new()
	_selection_area.name = "VehicleSelectionArea"
	_selection_area.collision_layer = 1 << max(vehicle_selection_layer - 1, 0)
	_selection_area.collision_mask = 0
	_selection_area.set_meta("vehicle_id", definition.assembly_id)
	var collision_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = footprint_size
	collision_shape.shape = box_shape
	collision_shape.position.y = footprint_size.y * 0.5
	_selection_area.add_child(collision_shape)
	_visual_root.add_child(_selection_area)

	_debug_label = Label3D.new()
	_debug_label.name = "DebugLabel"
	_debug_label.position = Vector3(0.0, footprint_size.y + cell_size * 0.9, 0.0)
	_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_debug_label.no_depth_test = true
	_debug_label.font_size = 28
	_visual_root.add_child(_debug_label)
	_update_debug_label()


func _build_arm_visual(footprint_size: Vector3) -> void:
	var column_size := Vector3(cell_size * 0.28, cell_size * 0.85, cell_size * 0.28)
	var column := _create_box_part(&"ArmColumn", column_size)
	column.position = Vector3(0.0, footprint_size.y + column_size.y * 0.5, 0.0)

	var beam_size := Vector3(cell_size * 0.95, cell_size * 0.18, cell_size * 0.22)
	var beam := _create_box_part(&"ArmBeam", beam_size)
	beam.position = Vector3(
		cell_size * 0.28,
		footprint_size.y + column_size.y + beam_size.y * 0.5,
		0.0
	)


func _build_transport_visual(footprint_size: Vector3) -> void:
	var tray_size := Vector3(
		footprint_size.x * 0.86,
		cell_size * 0.14,
		footprint_size.z * 0.86
	)
	var tray := _create_box_part(&"Tray", tray_size)
	tray.position = Vector3(0.0, footprint_size.y + tray_size.y * 0.5, 0.0)


func _create_box_part(part_name: StringName, size: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = String(part_name)
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	_visual_root.add_child(part)
	_visual_parts[part_name] = part
	return part


func _update_debug_label() -> void:
	if _debug_label == null or not is_instance_valid(_debug_label):
		return
	if definition == null or runtime_state == null:
		_debug_label.text = ""
		return
	_debug_label.text = "%s\n%.1f kg" % [definition.display_name, definition.total_weight]

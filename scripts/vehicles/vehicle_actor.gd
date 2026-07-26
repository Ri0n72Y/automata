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
var _visual_generation: int = 0


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
	if _visual_root == null:
		return null
	return _visual_root.get_node_or_null(NodePath(String(part_name))) as Node3D


func get_debug_label_text() -> String:
	if _debug_label == null:
		return ""
	return _debug_label.text


func _rebuild_visual() -> void:
	if _visual_root != null:
		remove_child(_visual_root)
		_visual_root.queue_free()
		_visual_root = null

	_visual_generation += 1
	_visual_root = Node3D.new()
	_visual_root.name = "Visual_%d" % _visual_generation
	add_child(_visual_root)

	var body_width := float(definition.footprint.x) * cell_size * 0.82
	var body_depth := float(definition.footprint.y) * cell_size * 0.82
	var body_size := Vector3(body_width, cell_size * 0.32, body_depth)
	var body_color := Color(0.12, 0.48, 0.82, 1.0)
	if definition.vehicle_kind == VehicleDefinitionScript.VehicleKind.TRANSPORT:
		body_color = Color(0.88, 0.45, 0.12, 1.0)

	_create_box(
		"Base",
		body_size,
		Vector3.UP * body_size.y * 0.5,
		body_color
	)

	if definition.vehicle_kind == VehicleDefinitionScript.VehicleKind.ARM:
		_create_arm_visual(body_size)
	else:
		_create_transport_visual(body_size)

	_create_selection_area(body_size)
	_create_debug_label(body_size)


func _create_arm_visual(body_size: Vector3) -> void:
	var column_size := Vector3(cell_size * 0.28, cell_size * 0.72, cell_size * 0.28)
	_create_box(
		"ArmColumn",
		column_size,
		Vector3(0.0, body_size.y + column_size.y * 0.5, 0.0),
		Color(0.72, 0.82, 0.92, 1.0)
	)
	var beam_size := Vector3(cell_size * 0.95, cell_size * 0.18, cell_size * 0.22)
	_create_box(
		"ArmBeam",
		beam_size,
		Vector3(
			beam_size.x * 0.32,
			body_size.y + column_size.y,
			0.0
		),
		Color(0.92, 0.94, 0.98, 1.0)
	)


func _create_transport_visual(body_size: Vector3) -> void:
	var tray_size := Vector3(
		body_size.x * 0.88,
		cell_size * 0.12,
		body_size.z * 0.88
	)
	_create_box(
		"Tray",
		tray_size,
		Vector3(0.0, body_size.y + tray_size.y * 0.5, 0.0),
		Color(0.98, 0.72, 0.28, 1.0)
	)


func _create_box(
	part_name: String,
	size: Vector3,
	local_position: Vector3,
	color: Color
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = part_name
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh_instance.mesh = box_mesh
	mesh_instance.position = local_position
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	mesh_instance.material_override = material
	_visual_root.add_child(mesh_instance)
	return mesh_instance


func _create_selection_area(body_size: Vector3) -> void:
	_selection_area = Area3D.new()
	_selection_area.name = "VehicleSelectionArea"
	_selection_area.collision_layer = vehicle_selection_layer
	_selection_area.collision_mask = 0
	_selection_area.set_meta("vehicle_id", definition.assembly_id)
	_visual_root.add_child(_selection_area)

	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "VehicleSelectionShape"
	var box_shape := BoxShape3D.new()
	box_shape.size = body_size
	collision_shape.shape = box_shape
	collision_shape.position = Vector3.UP * body_size.y * 0.5
	_selection_area.add_child(collision_shape)


func _create_debug_label(body_size: Vector3) -> void:
	_debug_label = Label3D.new()
	_debug_label.name = "VehicleLabel"
	_debug_label.position = Vector3.UP * (body_size.y + cell_size * 1.05)
	_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_debug_label.no_depth_test = true
	_debug_label.pixel_size = 0.008
	_visual_root.add_child(_debug_label)
	_update_debug_label()


func _update_debug_label() -> void:
	if _debug_label == null or definition == null:
		return
	_debug_label.text = "%s\n%.1f kg" % [definition.display_name, definition.total_weight]

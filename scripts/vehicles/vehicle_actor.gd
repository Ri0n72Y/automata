class_name VehicleActor
extends Node3D

signal move_started(target_anchor: Vector2i)
signal move_completed(target_anchor: Vector2i)
signal move_blocked()

const VehicleDefinitionScript := preload("res://scripts/vehicles/vehicle_definition.gd")
const VehicleRuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const MoveCommandScript := preload("res://scripts/vehicles/move_command.gd")

@export var vehicle_selection_layer: int = 2
@export var use_static_scene_visual: bool = false
@export var vehicle_preset_id: StringName = &""

var definition: VehicleDefinitionScript
var runtime_state: VehicleRuntimeStateScript
var controller: Node
var cell_size: float = 1.0

var _visual_root: Node3D
var _selection_area: Area3D
var _debug_label: Label3D
var _visual_parts: Dictionary = {}
var _visual_generation: int = 0
var _segment_progress: float = 0.0


func _ready() -> void:
	if use_static_scene_visual and _visual_root == null:
		_bind_static_visual()
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
	vehicle_preset_id = definition.assembly_id
	if not use_static_scene_visual:
		name = "Vehicle_%s" % String(definition.assembly_id)

	if use_static_scene_visual:
		if not _bind_static_visual():
			push_error("Static vehicle scene is missing VisualRoot, selection area, or debug label.")
			return false
	else:
		_rebuild_visual()

	_segment_progress = 0.0
	set_physics_process(false)
	sync_from_state()
	return true


func sync_from_state() -> void:
	if definition == null or runtime_state == null or controller == null:
		return
	if not is_inside_tree():
		return
	if (
		runtime_state.active_move_command != null
		and runtime_state.motion_state == VehicleRuntimeStateScript.MotionState.MOVING
	):
		_sync_movement_transform()
	else:
		global_position = _anchor_to_world(runtime_state.anchor_cell)
		_sync_actor_basis()
	_update_debug_label()


func start_move(command: MoveCommandScript) -> bool:
	if definition == null or runtime_state == null or controller == null:
		return false
	if not definition.can_move():
		return false
	if command == null or command.state != MoveCommandScript.State.MOVING:
		return false
	if command.path.is_empty() or command.path.front() != runtime_state.anchor_cell:
		return false
	if not runtime_state.assign_move_command(command):
		return false

	_segment_progress = 0.0
	set_physics_process(true)
	_sync_movement_transform()
	move_started.emit(command.target_anchor)
	return true


func _physics_process(delta: float) -> void:
	advance_move(delta)


func advance_move(delta: float) -> void:
	if runtime_state == null:
		set_physics_process(false)
		return
	var command: MoveCommandScript = runtime_state.active_move_command
	if command == null or runtime_state.motion_state != VehicleRuntimeStateScript.MotionState.MOVING:
		set_physics_process(false)
		return
	if command.path_index >= command.path.size() - 1:
		_finish_move(command.target_anchor)
		return

	var speed_in_cells := runtime_state.get_effective_speed()
	if speed_in_cells <= 0.0:
		_block_move()
		return

	var remaining_distance := maxf(delta, 0.0) * speed_in_cells
	if remaining_distance <= 0.0:
		_sync_movement_transform()
		return

	while remaining_distance > 0.000001:
		command = runtime_state.active_move_command
		if command == null or command.state != MoveCommandScript.State.MOVING:
			return
		var remaining_segment := 1.0 - _segment_progress
		var step := minf(remaining_distance, remaining_segment)
		_segment_progress += step
		remaining_distance -= step
		_sync_movement_transform()
		if _segment_progress < 0.999999:
			return

		var reached_anchor := command.get_next_anchor()
		runtime_state.anchor_cell = reached_anchor
		var finished := command.advance()
		_segment_progress = 0.0
		if finished:
			_finish_move(command.target_anchor)
			return
		_sync_movement_transform()


func cancel_move() -> void:
	if runtime_state == null or runtime_state.active_move_command == null:
		return
	runtime_state.block_move_command()
	_segment_progress = 0.0
	set_physics_process(false)
	sync_from_state()
	move_blocked.emit()


func reset_actor() -> void:
	if runtime_state == null:
		return
	set_physics_process(false)
	_segment_progress = 0.0
	runtime_state.reset()
	sync_from_state()


func get_vehicle_id() -> StringName:
	if definition != null:
		return definition.assembly_id
	return vehicle_preset_id


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


func get_segment_progress() -> float:
	return _segment_progress


func _anchor_to_world(anchor: Vector2i) -> Vector3:
	return controller.call(
		"grid_footprint_center_to_world",
		anchor,
		definition.footprint
	)


func _sync_movement_transform() -> void:
	if runtime_state == null or runtime_state.active_move_command == null:
		return
	var command: MoveCommandScript = runtime_state.active_move_command
	var current_anchor := command.get_current_anchor()
	var next_anchor := command.get_next_anchor()
	var current_world := _anchor_to_world(current_anchor)
	var next_world := _anchor_to_world(next_anchor)
	global_position = current_world.lerp(next_world, clampf(_segment_progress, 0.0, 1.0))
	_sync_actor_basis()


func _sync_actor_basis() -> void:
	var grid_basis: Basis = controller.call("get_grid_world_basis")
	global_basis = grid_basis * Basis(
		Vector3.UP,
		-float(runtime_state.facing) * PI * 0.5
	)


func _finish_move(target_anchor: Vector2i) -> void:
	runtime_state.anchor_cell = target_anchor
	_segment_progress = 0.0
	global_position = _anchor_to_world(target_anchor)
	_sync_actor_basis()
	runtime_state.complete_move_command()
	set_physics_process(false)
	move_completed.emit(target_anchor)


func _block_move() -> void:
	runtime_state.block_move_command()
	_segment_progress = 0.0
	set_physics_process(false)
	sync_from_state()
	move_blocked.emit()


func _bind_static_visual() -> bool:
	_visual_parts.clear()
	_visual_root = get_node_or_null("VisualRoot") as Node3D
	if _visual_root == null:
		return false

	_visual_root.scale = Vector3.ONE * cell_size
	for child in _visual_root.find_children("*", "Node3D", true, false):
		if child is MeshInstance3D:
			_visual_parts[StringName(child.name)] = child

	_selection_area = _visual_root.get_node_or_null("VehicleSelectionArea") as Area3D
	_debug_label = _visual_root.get_node_or_null("DebugLabel") as Label3D
	if _selection_area == null or _debug_label == null:
		return false

	_selection_area.collision_layer = 1 << max(vehicle_selection_layer - 1, 0)
	_selection_area.collision_mask = 0
	_selection_area.set_meta("vehicle_id", get_vehicle_id())
	_update_debug_label()
	return true


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
	_debug_label.outline_size = 7
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
	part.material_override = _create_fallback_material(part_name)
	_visual_root.add_child(part)
	_visual_parts[part_name] = part
	return part


func _create_fallback_material(part_name: StringName) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.roughness = 0.55
	match part_name:
		&"Body":
			material.albedo_color = Color(0.08, 0.32, 0.55, 1.0)
		&"ArmColumn":
			material.albedo_color = Color(0.9, 0.36, 0.06, 1.0)
		&"ArmBeam":
			material.albedo_color = Color(0.98, 0.72, 0.08, 1.0)
		&"Tray":
			material.albedo_color = Color(0.16, 0.68, 0.74, 1.0)
		_:
			material.albedo_color = Color(0.3, 0.36, 0.44, 1.0)
	return material


func _update_debug_label() -> void:
	if _debug_label == null or not is_instance_valid(_debug_label):
		return
	if definition == null or runtime_state == null:
		return
	_debug_label.text = "%s\n%.1f kg" % [definition.display_name, definition.total_weight]

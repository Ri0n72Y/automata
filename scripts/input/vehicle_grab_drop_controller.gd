class_name VehicleGrabDropController
extends Node3D

signal grab_drop_completed(vehicle_id: StringName, action: int, status: int)
signal facing_changed(vehicle_id: StringName, facing: int)

const VehicleActorScript := preload("res://scripts/vehicles/vehicle_actor.gd")
const VehicleDefinitionScript := preload("res://scripts/vehicles/vehicle_definition.gd")
const VehicleRuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const GrabDropCommandScript := preload("res://scripts/vehicles/grab_drop_command.gd")
const GrabDropResultScript := preload("res://scripts/vehicles/grab_drop_result.gd")
const ItemSourceInterfaceScript := preload("res://scripts/objects/item_source_interface.gd")
const ItemReceiverInterfaceScript := preload("res://scripts/objects/item_receiver_interface.gd")
const VehicleSelectionControllerScript := preload("res://scripts/input/vehicle_selection_controller.gd")
const Scene01VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const Scene01ObjectManagerScript := preload("res://scripts/scene_01/scene_01_object_manager.gd")

const GRAB_DROP_ACTION := &"vehicle_grab_drop"
const ROTATE_COUNTERCLOCKWISE_ACTION := &"vehicle_rotate_counterclockwise"
const ROTATE_CLOCKWISE_ACTION := &"vehicle_rotate_clockwise"

@export var valid_interaction_color: Color = Color(0.2, 0.92, 0.38, 0.28)
@export var invalid_interaction_color: Color = Color(1.0, 0.24, 0.18, 0.28)
@export_range(0.01, 0.2, 0.01) var preview_height: float = 0.06
@export_range(0.5, 1.0, 0.01) var preview_scale: float = 0.86

var vehicle_selection_controller: VehicleSelectionControllerScript
var vehicle_manager: Scene01VehicleManagerScript
var object_manager: Scene01ObjectManagerScript
var _command := GrabDropCommandScript.new()
var _preview_meshes: Array[MeshInstance3D] = []
var _preview_cells: Array[Vector2i] = []
var _preview_is_valid: bool = false


func _ready() -> void:
	configure(
		get_node_or_null("../VehicleSelectionController") as VehicleSelectionControllerScript,
		get_node_or_null("../../RobotRoot/Scene01VehicleManager") as Scene01VehicleManagerScript,
		get_node_or_null("../../ObjectRoot/Scene01ObjectManager") as Scene01ObjectManagerScript
	)
	set_process(true)
	refresh_interaction_preview()


func _process(_delta: float) -> void:
	refresh_interaction_preview()


func configure(
	p_vehicle_selection_controller: VehicleSelectionControllerScript,
	p_vehicle_manager: Scene01VehicleManagerScript,
	p_object_manager: Scene01ObjectManagerScript
) -> void:
	vehicle_selection_controller = p_vehicle_selection_controller
	vehicle_manager = p_vehicle_manager
	object_manager = p_object_manager


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.echo or _has_command_modifier(key_event) or _is_text_input_focused():
			return
	if _is_move_target_mode_active():
		return
	if event.is_action_pressed(GRAB_DROP_ACTION):
		request_selected_grab_drop()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(ROTATE_COUNTERCLOCKWISE_ACTION):
		if rotate_selected_arm(-1):
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(ROTATE_CLOCKWISE_ACTION):
		if rotate_selected_arm(1):
			get_viewport().set_input_as_handled()


func request_selected_grab_drop() -> GrabDropResultScript:
	var vehicle := _get_selected_vehicle()
	if vehicle == null or vehicle.runtime_state == null:
		var missing_vehicle_result := GrabDropResultScript.rejected(
			GrabDropResultScript.Action.NONE,
			GrabDropResultScript.Status.NO_TARGET
		)
		grab_drop_completed.emit(
			&"",
			missing_vehicle_result.action,
			missing_vehicle_result.status
		)
		return missing_vehicle_result
	var target := resolve_target_for_vehicle(vehicle)
	var result := _command.execute(vehicle.runtime_state, target)
	vehicle.sync_from_state()
	refresh_interaction_preview()
	grab_drop_completed.emit(vehicle.get_vehicle_id(), result.action, result.status)
	return result


func rotate_selected_arm(direction: int) -> bool:
	var vehicle := _get_selected_vehicle()
	if not _can_rotate(vehicle):
		return false
	var step := clampi(direction, -1, 1)
	if step == 0:
		return false
	vehicle.runtime_state.facing = posmod(vehicle.runtime_state.facing + step, 4)
	vehicle.sync_from_state()
	refresh_interaction_preview()
	facing_changed.emit(vehicle.get_vehicle_id(), vehicle.runtime_state.facing)
	return true


func resolve_target_for_vehicle(vehicle: VehicleActorScript) -> Variant:
	if vehicle == null or vehicle.runtime_state == null or vehicle.definition == null:
		return null
	var front_cells := get_forward_interaction_cells(vehicle)
	if front_cells.is_empty():
		return null
	var all_interfaces := _collect_item_interaction_interfaces()
	var candidates: Array[Variant] = []
	for interaction_interface in all_interfaces:
		if not _is_action_compatible(vehicle.runtime_state, interaction_interface):
			continue
		var interaction_cells := _get_interaction_cells(interaction_interface)
		if interaction_cells.is_empty() or not _cells_overlap(front_cells, interaction_cells):
			continue
		if not candidates.has(interaction_interface):
			candidates.append(interaction_interface)

	if candidates.size() > 1:
		return null
	if candidates.size() == 1:
		return candidates[0]
	return _resolve_ground_target(vehicle, all_interfaces)


func get_forward_interaction_cells(vehicle: VehicleActorScript) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if vehicle == null or vehicle.runtime_state == null or vehicle.definition == null:
		return result
	var anchor: Vector2i = vehicle.runtime_state.anchor_cell
	var footprint: Vector2i = vehicle.definition.footprint
	match vehicle.runtime_state.facing:
		VehicleRuntimeStateScript.Facing.NORTH:
			for offset_x in range(footprint.x):
				result.append(anchor + Vector2i(offset_x, -1))
		VehicleRuntimeStateScript.Facing.EAST:
			for offset_y in range(footprint.y):
				result.append(anchor + Vector2i(footprint.x, offset_y))
		VehicleRuntimeStateScript.Facing.SOUTH:
			for offset_x in range(footprint.x):
				result.append(anchor + Vector2i(offset_x, footprint.y))
		VehicleRuntimeStateScript.Facing.WEST:
			for offset_y in range(footprint.y):
				result.append(anchor + Vector2i(-1, offset_y))
	return result


func get_primary_ground_interaction_cell(vehicle: VehicleActorScript) -> Vector2i:
	if vehicle == null or vehicle.runtime_state == null or vehicle.definition == null:
		return Vector2i(-1, -1)
	var anchor: Vector2i = vehicle.runtime_state.anchor_cell
	var footprint: Vector2i = vehicle.definition.footprint
	match vehicle.runtime_state.facing:
		VehicleRuntimeStateScript.Facing.NORTH:
			return anchor + Vector2i(0, -1)
		VehicleRuntimeStateScript.Facing.EAST:
			return anchor + Vector2i(footprint.x, 0)
		VehicleRuntimeStateScript.Facing.SOUTH:
			return anchor + Vector2i(footprint.x - 1, footprint.y)
		VehicleRuntimeStateScript.Facing.WEST:
			return anchor + Vector2i(-1, footprint.y - 1)
	return Vector2i(-1, -1)


func refresh_interaction_preview() -> void:
	var vehicle := _get_selected_vehicle()
	if not _can_preview(vehicle):
		_hide_interaction_preview()
		return
	var target := resolve_target_for_vehicle(vehicle)
	var cells := get_forward_interaction_cells(vehicle)
	if target != null:
		var target_cells := _get_interaction_cells(target)
		var overlap: Array[Vector2i] = []
		for cell in cells:
			if target_cells.has(cell):
				overlap.append(cell)
		if not overlap.is_empty():
			cells = overlap
	else:
		var all_interfaces := _collect_item_interaction_interfaces()
		var ground_cell := get_primary_ground_interaction_cell(vehicle)
		if (
			ground_cell != Vector2i(-1, -1)
			and _is_legal_ground_cell(vehicle, ground_cell, all_interfaces)
		):
			cells = [ground_cell]
	_preview_is_valid = target != null and _is_target_ready(vehicle.runtime_state, target)
	_show_interaction_preview(vehicle, cells, _preview_is_valid)


func is_interaction_preview_visible() -> bool:
	return not _preview_cells.is_empty()


func is_interaction_preview_valid() -> bool:
	return is_interaction_preview_visible() and _preview_is_valid


func get_interaction_preview_cells() -> Array[Vector2i]:
	return _preview_cells.duplicate()


func _resolve_ground_target(
	vehicle: VehicleActorScript,
	all_interfaces: Array[Variant]
) -> ItemReceiverInterfaceScript:
	if object_manager == null:
		return null
	var cell := get_primary_ground_interaction_cell(vehicle)
	if cell == Vector2i(-1, -1) or not _is_legal_ground_cell(vehicle, cell, all_interfaces):
		return null
	var ground_interface := object_manager.get_ground_cell_interface(cell) as ItemReceiverInterfaceScript
	if ground_interface == null:
		return null
	if not vehicle.runtime_state.arm_has_item and not ground_interface.can_take_item():
		return null
	return ground_interface


func _is_legal_ground_cell(
	vehicle: VehicleActorScript,
	cell: Vector2i,
	all_interfaces: Array[Variant]
) -> bool:
	if vehicle == null or vehicle.controller == null:
		return false
	if not vehicle.controller.has_method("is_grid_cell_walkable"):
		return false
	if not bool(vehicle.controller.call("is_grid_cell_walkable", cell)):
		return false
	for interaction_interface in all_interfaces:
		if _get_interaction_cells(interaction_interface).has(cell):
			return false
	if vehicle_manager != null:
		for vehicle_node in vehicle_manager.get_vehicles():
			var actor := vehicle_node as VehicleActorScript
			if actor != null and actor.get_occupied_cells().has(cell):
				return false
	return true


func _collect_item_interaction_interfaces() -> Array[Variant]:
	var interfaces: Array[Variant] = []
	if object_manager != null:
		for interaction_interface in object_manager.get_item_interaction_interfaces():
			if interaction_interface != null and not interfaces.has(interaction_interface):
				interfaces.append(interaction_interface)
	if vehicle_manager != null:
		for vehicle_node in vehicle_manager.get_vehicles():
			var actor := vehicle_node as VehicleActorScript
			if actor == null or actor.runtime_state == null:
				continue
			for interaction_interface in actor.runtime_state.get_item_interaction_interfaces(
				actor.get_occupied_cells()
			):
				if interaction_interface != null and not interfaces.has(interaction_interface):
					interfaces.append(interaction_interface)
	return interfaces


func _is_action_compatible(runtime: VehicleRuntimeStateScript, target: Variant) -> bool:
	if runtime == null:
		return false
	if runtime.arm_has_item:
		var receiver := target as ItemReceiverInterfaceScript
		return (
			receiver != null
			and runtime.carried_item != null
			and receiver.accepts_item_type(runtime.carried_item.get_item_type())
		)
	var source := target as ItemSourceInterfaceScript
	if source != null:
		return true
	var receiver := target as ItemReceiverInterfaceScript
	return receiver != null and receiver.can_take_item()


func _is_target_ready(runtime: VehicleRuntimeStateScript, target: Variant) -> bool:
	if runtime == null or target == null:
		return false
	if runtime.arm_has_item:
		var receiver := target as ItemReceiverInterfaceScript
		if receiver == null or runtime.carried_item == null:
			return false
		if not receiver.accepts_item_type(runtime.carried_item.get_item_type()):
			return false
		var capacity := receiver.get_capacity()
		return capacity <= 0 or receiver.get_current_count() < capacity
	var source := target as ItemSourceInterfaceScript
	if source != null:
		return source.is_available()
	var receiver := target as ItemReceiverInterfaceScript
	return receiver != null and receiver.can_take_item() and receiver.get_current_count() > 0


func _get_interaction_cells(target: Variant) -> Array[Vector2i]:
	var source := target as ItemSourceInterfaceScript
	if source != null:
		return source.get_interaction_cells()
	var receiver := target as ItemReceiverInterfaceScript
	if receiver != null:
		return receiver.get_interaction_cells()
	var empty_cells: Array[Vector2i] = []
	return empty_cells


func _show_interaction_preview(
	vehicle: VehicleActorScript,
	cells: Array[Vector2i],
	is_valid: bool
) -> void:
	_ensure_preview_mesh_count(cells.size())
	_preview_cells = cells.duplicate()
	for index in range(_preview_meshes.size()):
		var preview := _preview_meshes[index]
		if index >= cells.size():
			preview.visible = false
			continue
		var mesh := preview.mesh as BoxMesh
		mesh.size = Vector3(
			vehicle.cell_size * preview_scale,
			0.015,
			vehicle.cell_size * preview_scale
		)
		var material := preview.material_override as StandardMaterial3D
		material.albedo_color = valid_interaction_color if is_valid else invalid_interaction_color
		var world_position: Vector3 = vehicle.controller.call("grid_cell_to_world", cells[index])
		preview.global_position = world_position + Vector3.UP * preview_height
		preview.visible = true


func _hide_interaction_preview() -> void:
	_preview_cells.clear()
	_preview_is_valid = false
	for preview in _preview_meshes:
		preview.visible = false


func _ensure_preview_mesh_count(count: int) -> void:
	while _preview_meshes.size() < count:
		var preview := MeshInstance3D.new()
		preview.name = "GrabDropInteractionPreview_%d" % _preview_meshes.size()
		preview.top_level = true
		preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mesh := BoxMesh.new()
		preview.mesh = mesh
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = false
		preview.material_override = material
		add_child(preview)
		_preview_meshes.append(preview)


func _get_selected_vehicle() -> VehicleActorScript:
	if vehicle_selection_controller == null:
		return null
	return vehicle_selection_controller.get_selected_vehicle()


func _can_rotate(vehicle: VehicleActorScript) -> bool:
	if vehicle == null or vehicle.definition == null or vehicle.runtime_state == null:
		return false
	if not vehicle.definition.has_capability(VehicleDefinitionScript.CAPABILITY_CAN_GRAB):
		return false
	return (
		vehicle.runtime_state.motion_state != VehicleRuntimeStateScript.MotionState.PLANNING
		and vehicle.runtime_state.motion_state != VehicleRuntimeStateScript.MotionState.MOVING
	)


func _can_preview(vehicle: VehicleActorScript) -> bool:
	if vehicle == null or vehicle.definition == null or vehicle.runtime_state == null:
		return false
	if not vehicle.definition.has_capability(VehicleDefinitionScript.CAPABILITY_CAN_GRAB):
		return false
	if _is_move_target_mode_active():
		return false
	return (
		vehicle.runtime_state.motion_state != VehicleRuntimeStateScript.MotionState.PLANNING
		and vehicle.runtime_state.motion_state != VehicleRuntimeStateScript.MotionState.MOVING
	)


func _is_move_target_mode_active() -> bool:
	var grid_selection := get_node_or_null("../GridSelectionController")
	return (
		grid_selection != null
		and grid_selection.has_method("is_live_target_mode")
		and bool(grid_selection.call("is_live_target_mode"))
	)


func _cells_overlap(a: Array[Vector2i], b: Array[Vector2i]) -> bool:
	for cell in a:
		if b.has(cell):
			return true
	return false


func _has_command_modifier(event: InputEventKey) -> bool:
	return event.shift_pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed


func _is_text_input_focused() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit

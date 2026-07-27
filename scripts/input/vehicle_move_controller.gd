class_name VehicleMoveController
extends Node3D

signal move_requested(vehicle_id: StringName, target_anchor: Vector2i)
signal move_accepted(vehicle_id: StringName, target_anchor: Vector2i)
signal move_rejected(vehicle_id: StringName, target_anchor: Vector2i, reason: StringName)

const GridPathfinderScript := preload("res://scripts/vehicles/grid_pathfinder.gd")
const MoveCommandScript := preload("res://scripts/vehicles/move_command.gd")
const VehicleActorScript := preload("res://scripts/vehicles/vehicle_actor.gd")
const VehicleRuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")

const REJECTION_NO_VEHICLE := &"no_vehicle_selected"
const REJECTION_BUSY := &"vehicle_busy"
const REJECTION_NO_PATH := &"no_path"
const REJECTION_START_FAILED := &"start_failed"

@export var valid_target_color: Color = Color(0.2, 0.9, 0.35, 0.32)
@export var invalid_target_color: Color = Color(1.0, 0.2, 0.18, 0.36)
@export_range(0.01, 0.2, 0.01) var preview_height: float = 0.05
@export_range(0.8, 1.0, 0.01) var preview_scale: float = 0.94

var controller: Node
var vehicle_selection_controller: Node
var grid_selection_controller: Node
var vehicle_manager: Node
var _pathfinder := GridPathfinderScript.new()
var _target_preview: MeshInstance3D
var _preview_is_valid: bool = false
var _last_rejection_reason: StringName = &""


func _ready() -> void:
	_target_preview = _create_target_preview()
	add_child(_target_preview)


func configure(
	p_controller: Node,
	p_vehicle_selection_controller: Node,
	p_grid_selection_controller: Node,
	p_vehicle_manager: Node
) -> void:
	controller = p_controller
	vehicle_selection_controller = p_vehicle_selection_controller
	grid_selection_controller = p_grid_selection_controller
	vehicle_manager = p_vehicle_manager
	_connect_input_signals()
	refresh_target_preview()


func request_selected_vehicle_move(target_anchor: Vector2i) -> bool:
	var vehicle := _get_selected_vehicle()
	var vehicle_id: StringName = &""
	if vehicle != null:
		vehicle_id = vehicle.get_vehicle_id()
	move_requested.emit(vehicle_id, target_anchor)
	if vehicle == null:
		_reject(vehicle_id, target_anchor, REJECTION_NO_VEHICLE)
		return false
	if vehicle.runtime_state == null or not vehicle.runtime_state.begin_move_planning():
		_reject(vehicle_id, target_anchor, REJECTION_BUSY)
		return false

	var path := _find_path(vehicle, target_anchor)
	if path.is_empty():
		vehicle.runtime_state.fail_move_planning()
		_reject(vehicle_id, target_anchor, REJECTION_NO_PATH)
		refresh_target_preview()
		return false

	var command := MoveCommandScript.new()
	if not command.configure(target_anchor, path):
		vehicle.runtime_state.fail_move_planning()
		_reject(vehicle_id, target_anchor, REJECTION_NO_PATH)
		refresh_target_preview()
		return false

	if command.state == MoveCommandScript.State.WAITING:
		vehicle.runtime_state.clear_move_command()
		_clear_grid_target()
		_last_rejection_reason = &""
		move_accepted.emit(vehicle_id, target_anchor)
		return true

	if not vehicle.start_move(command):
		vehicle.runtime_state.fail_move_planning()
		_reject(vehicle_id, target_anchor, REJECTION_START_FAILED)
		refresh_target_preview()
		return false

	_clear_grid_target()
	_last_rejection_reason = &""
	move_accepted.emit(vehicle_id, target_anchor)
	return true


func reset_controller_state() -> void:
	_last_rejection_reason = &""
	_hide_target_preview()


func refresh_target_preview() -> void:
	if _target_preview == null or grid_selection_controller == null:
		return
	if not bool(grid_selection_controller.call("has_selected_cell")):
		_hide_target_preview()
		return
	var vehicle := _get_selected_vehicle()
	if vehicle == null or vehicle.definition == null:
		_hide_target_preview()
		return

	var target_anchor: Vector2i = grid_selection_controller.get("selected_cell")
	var footprint: Vector2i = vehicle.definition.footprint
	var cell_size := vehicle.cell_size
	var mesh := _target_preview.mesh as BoxMesh
	mesh.size = Vector3(
		float(footprint.x) * cell_size * preview_scale,
		0.025,
		float(footprint.y) * cell_size * preview_scale
	)
	var world_center: Vector3 = controller.call(
		"grid_footprint_center_to_world",
		target_anchor,
		footprint
	)
	_target_preview.position = to_local(world_center) + Vector3.UP * preview_height
	_preview_is_valid = not _find_path(vehicle, target_anchor).is_empty()
	var material := _target_preview.material_override as StandardMaterial3D
	material.albedo_color = valid_target_color if _preview_is_valid else invalid_target_color
	_target_preview.visible = true


func sync_visuals() -> void:
	refresh_target_preview()


func is_target_preview_visible() -> bool:
	return _target_preview != null and _target_preview.visible


func is_target_preview_valid() -> bool:
	return is_target_preview_visible() and _preview_is_valid


func get_last_rejection_reason() -> StringName:
	return _last_rejection_reason


func _connect_input_signals() -> void:
	if grid_selection_controller != null:
		var confirmed_callable := Callable(self, "_on_grid_selection_confirmed")
		if not grid_selection_controller.selection_confirmed.is_connected(confirmed_callable):
			grid_selection_controller.selection_confirmed.connect(confirmed_callable)
		var grid_changed_callable := Callable(self, "_on_grid_selection_changed")
		if not grid_selection_controller.selection_changed.is_connected(grid_changed_callable):
			grid_selection_controller.selection_changed.connect(grid_changed_callable)
	if vehicle_selection_controller != null:
		var vehicle_changed_callable := Callable(self, "_on_vehicle_selection_changed")
		if not vehicle_selection_controller.selection_changed.is_connected(vehicle_changed_callable):
			vehicle_selection_controller.selection_changed.connect(vehicle_changed_callable)


func _on_grid_selection_confirmed(target_anchor: Vector2i) -> void:
	request_selected_vehicle_move(target_anchor)


func _on_grid_selection_changed(_cell: Vector2i, _has_selection: bool) -> void:
	refresh_target_preview()


func _on_vehicle_selection_changed(_vehicle_id: StringName, _has_selection: bool) -> void:
	refresh_target_preview()


func _get_selected_vehicle() -> VehicleActorScript:
	if vehicle_selection_controller == null:
		return null
	return vehicle_selection_controller.call("get_selected_vehicle") as VehicleActorScript


func _find_path(vehicle: VehicleActorScript, target_anchor: Vector2i) -> Array[Vector2i]:
	var empty_path: Array[Vector2i] = []
	if controller == null or vehicle_manager == null:
		return empty_path
	if vehicle == null or vehicle.definition == null or vehicle.runtime_state == null:
		return empty_path
	var grid_size: Vector2i = controller.call("get_grid_size")
	var walkable := Callable(self, "_is_footprint_walkable_for_vehicle").bind(vehicle)
	return _pathfinder.find_path(
		vehicle.runtime_state.anchor_cell,
		target_anchor,
		vehicle.definition.footprint,
		grid_size,
		walkable
	)


func _is_footprint_walkable_for_vehicle(
	anchor: Vector2i,
	footprint: Vector2i,
	moving_vehicle: VehicleActorScript
) -> bool:
	if not bool(controller.call("is_grid_footprint_walkable", anchor, footprint)):
		return false
	var candidate_cells: Dictionary = {}
	for offset_y in range(footprint.y):
		for offset_x in range(footprint.x):
			candidate_cells[anchor + Vector2i(offset_x, offset_y)] = true
	for vehicle_node in vehicle_manager.call("get_vehicles"):
		var other := vehicle_node as VehicleActorScript
		if other == null or other == moving_vehicle or other.runtime_state == null:
			continue
		for occupied_cell in other.get_occupied_cells():
			if candidate_cells.has(occupied_cell):
				return false
	return true


func _clear_grid_target() -> void:
	if grid_selection_controller != null:
		grid_selection_controller.call("cancel_selection")
	_hide_target_preview()


func _reject(vehicle_id: StringName, target_anchor: Vector2i, reason: StringName) -> void:
	_last_rejection_reason = reason
	move_rejected.emit(vehicle_id, target_anchor, reason)


func _hide_target_preview() -> void:
	_preview_is_valid = false
	if _target_preview != null:
		_target_preview.visible = false


func _create_target_preview() -> MeshInstance3D:
	var preview := MeshInstance3D.new()
	preview.name = "VehicleTargetFootprintPreview"
	preview.visible = false
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	preview.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = valid_target_color
	preview.material_override = material
	return preview

class_name VehicleMoveController
extends Node3D

signal move_requested(vehicle_id: StringName, target_anchor: Vector2i)
signal move_accepted(vehicle_id: StringName, target_anchor: Vector2i)
signal move_rejected(vehicle_id: StringName, target_anchor: Vector2i, reason: StringName)

const GridPathfinderScript := preload("res://scripts/vehicles/grid_pathfinder.gd")
const MoveCommandScript := preload("res://scripts/vehicles/move_command.gd")
const VehicleActorScript := preload("res://scripts/vehicles/vehicle_actor.gd")
const VehicleRuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const GridSelectionControllerScript := preload("res://scripts/input/grid_selection_controller.gd")
const VehicleSelectionControllerScript := preload("res://scripts/input/vehicle_selection_controller.gd")
const Scene01VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")

const REJECTION_NO_VEHICLE := &"no_vehicle_selected"
const REJECTION_BUSY := &"vehicle_busy"
const REJECTION_NO_PATH := &"no_path"
const REJECTION_START_FAILED := &"start_failed"

@export var valid_target_color: Color = Color(0.2, 0.9, 0.35, 0.20)
@export var invalid_target_color: Color = Color(1.0, 0.2, 0.18, 0.23)
@export var valid_path_color: Color = Color(0.2, 0.95, 0.42, 0.88)
@export var invalid_path_color: Color = Color(1.0, 0.28, 0.22, 0.82)
@export_range(0.01, 0.2, 0.01) var preview_height: float = 0.05
@export_range(0.8, 1.0, 0.01) var preview_scale: float = 0.94
@export_range(0.02, 0.2, 0.01) var path_line_width: float = 0.07
@export_range(0.01, 0.2, 0.01) var path_line_height: float = 0.075

var controller: Node
var vehicle_selection_controller: VehicleSelectionControllerScript
var grid_selection_controller: GridSelectionControllerScript
var vehicle_manager: Scene01VehicleManagerScript
var _pathfinder := GridPathfinderScript.new()
var _target_preview: MeshInstance3D
var _path_preview_root: Node3D
var _path_segments: Array[MeshInstance3D] = []
var _preview_path: Array[Vector2i] = []
var _preview_is_valid: bool = false
var _last_rejection_reason: StringName = &""
var _vehicle_ui_open: bool = false
var _observed_vehicle: VehicleActorScript
var _valid_path_material: StandardMaterial3D
var _invalid_path_material: StandardMaterial3D


func _ready() -> void:
	_target_preview = _create_target_preview()
	add_child(_target_preview)
	_path_preview_root = Node3D.new()
	_path_preview_root.name = "VehiclePathPreview"
	add_child(_path_preview_root)
	_valid_path_material = _create_path_material(valid_path_color)
	_invalid_path_material = _create_path_material(invalid_path_color)


func _exit_tree() -> void:
	_replace_observed_vehicle(null)


func configure(
	p_controller: Node,
	p_vehicle_selection_controller: VehicleSelectionControllerScript,
	p_grid_selection_controller: GridSelectionControllerScript,
	p_vehicle_manager: Scene01VehicleManagerScript
) -> void:
	controller = p_controller
	vehicle_selection_controller = p_vehicle_selection_controller
	grid_selection_controller = p_grid_selection_controller
	vehicle_manager = p_vehicle_manager
	_connect_input_signals()
	_sync_live_target_mode()


func set_vehicle_ui_open(is_open: bool) -> void:
	if _vehicle_ui_open == is_open:
		return
	_vehicle_ui_open = is_open
	_sync_live_target_mode()


func is_vehicle_ui_open() -> bool:
	return _vehicle_ui_open


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
		refresh_target_preview()
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
		_sync_live_target_mode()
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
	_vehicle_ui_open = false
	_hide_prediction()


func refresh_target_preview() -> void:
	if _target_preview == null or grid_selection_controller == null:
		_hide_prediction()
		return
	var vehicle := _get_selected_vehicle()
	if not _can_show_prediction(vehicle):
		_hide_prediction()
		return
	if not grid_selection_controller.has_selected_cell():
		_hide_prediction()
		return

	var target_anchor := grid_selection_controller.selected_cell
	var footprint: Vector2i = vehicle.definition.footprint
	var cell_size := vehicle.cell_size
	var path := _find_path(vehicle, target_anchor)
	_preview_path = path.duplicate()
	_preview_is_valid = not path.is_empty()

	var mesh := _target_preview.mesh as BoxMesh
	mesh.size = Vector3(
		float(footprint.x) * cell_size * preview_scale,
		0.02,
		float(footprint.y) * cell_size * preview_scale
	)
	var world_center: Vector3 = controller.call(
		"grid_footprint_center_to_world",
		target_anchor,
		footprint
	)
	_target_preview.position = to_local(world_center) + Vector3.UP * preview_height
	var target_material := _target_preview.material_override as StandardMaterial3D
	target_material.albedo_color = valid_target_color if _preview_is_valid else invalid_target_color
	_target_preview.visible = true
	_update_path_preview(path, footprint, _preview_is_valid)


func sync_visuals() -> void:
	refresh_target_preview()


func is_target_preview_visible() -> bool:
	return _target_preview != null and _target_preview.visible


func is_target_preview_valid() -> bool:
	return is_target_preview_visible() and _preview_is_valid


func is_path_preview_visible() -> bool:
	for segment in _path_segments:
		if segment != null and segment.visible:
			return true
	return false


func get_preview_path() -> Array[Vector2i]:
	return _preview_path.duplicate()


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
	_sync_live_target_mode()


func _on_observed_vehicle_move_started(_target_anchor: Vector2i) -> void:
	_hide_prediction()


func _on_observed_vehicle_move_completed(_target_anchor: Vector2i) -> void:
	_sync_live_target_mode()


func _on_observed_vehicle_move_blocked() -> void:
	_sync_live_target_mode()


func _sync_live_target_mode() -> void:
	if grid_selection_controller == null:
		return
	var vehicle := _get_selected_vehicle()
	_replace_observed_vehicle(vehicle)
	var interaction_enabled := vehicle != null and not _vehicle_ui_open
	var footprint := Vector2i.ONE
	if vehicle != null and vehicle.definition != null:
		footprint = vehicle.definition.footprint
	grid_selection_controller.set_live_target_mode(interaction_enabled, footprint)
	if _can_show_prediction(vehicle):
		refresh_target_preview()
	else:
		_hide_prediction()


func _can_show_prediction(vehicle: VehicleActorScript) -> bool:
	if vehicle == null or _vehicle_ui_open:
		return false
	if vehicle.definition == null or vehicle.runtime_state == null:
		return false
	return (
		vehicle.runtime_state.motion_state != VehicleRuntimeStateScript.MotionState.PLANNING
		and vehicle.runtime_state.motion_state != VehicleRuntimeStateScript.MotionState.MOVING
	)


func _replace_observed_vehicle(vehicle: VehicleActorScript) -> void:
	if _observed_vehicle == vehicle:
		return
	_disconnect_observed_vehicle()
	_observed_vehicle = vehicle
	if _observed_vehicle == null or not is_instance_valid(_observed_vehicle):
		return
	var started_callable := Callable(self, "_on_observed_vehicle_move_started")
	if not _observed_vehicle.move_started.is_connected(started_callable):
		_observed_vehicle.move_started.connect(started_callable)
	var completed_callable := Callable(self, "_on_observed_vehicle_move_completed")
	if not _observed_vehicle.move_completed.is_connected(completed_callable):
		_observed_vehicle.move_completed.connect(completed_callable)
	var blocked_callable := Callable(self, "_on_observed_vehicle_move_blocked")
	if not _observed_vehicle.move_blocked.is_connected(blocked_callable):
		_observed_vehicle.move_blocked.connect(blocked_callable)


func _disconnect_observed_vehicle() -> void:
	if _observed_vehicle == null or not is_instance_valid(_observed_vehicle):
		_observed_vehicle = null
		return
	var started_callable := Callable(self, "_on_observed_vehicle_move_started")
	if _observed_vehicle.move_started.is_connected(started_callable):
		_observed_vehicle.move_started.disconnect(started_callable)
	var completed_callable := Callable(self, "_on_observed_vehicle_move_completed")
	if _observed_vehicle.move_completed.is_connected(completed_callable):
		_observed_vehicle.move_completed.disconnect(completed_callable)
	var blocked_callable := Callable(self, "_on_observed_vehicle_move_blocked")
	if _observed_vehicle.move_blocked.is_connected(blocked_callable):
		_observed_vehicle.move_blocked.disconnect(blocked_callable)
	_observed_vehicle = null


func _get_selected_vehicle() -> VehicleActorScript:
	if vehicle_selection_controller == null:
		return null
	return vehicle_selection_controller.get_selected_vehicle()


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
	for vehicle_node in vehicle_manager.get_vehicles():
		var other := vehicle_node as VehicleActorScript
		if other == null or other == moving_vehicle or other.runtime_state == null:
			continue
		for occupied_cell in other.get_occupied_cells():
			if candidate_cells.has(occupied_cell):
				return false
	return true


func _update_path_preview(
	path: Array[Vector2i],
	footprint: Vector2i,
	is_valid: bool
) -> void:
	_hide_path_segments()
	if controller == null or path.size() < 2:
		return
	for index in range(path.size() - 1):
		var segment := _ensure_path_segment(index)
		var start_world: Vector3 = controller.call(
			"grid_footprint_center_to_world",
			path[index],
			footprint
		)
		var end_world: Vector3 = controller.call(
			"grid_footprint_center_to_world",
			path[index + 1],
			footprint
		)
		var start_local := to_local(start_world)
		var end_local := to_local(end_world)
		var delta := end_local - start_local
		var length := Vector2(delta.x, delta.z).length()
		if length <= 0.001:
			continue
		var box_mesh := segment.mesh as BoxMesh
		box_mesh.size = Vector3(length, 0.025, path_line_width)
		segment.position = (start_local + end_local) * 0.5 + Vector3.UP * path_line_height
		segment.rotation = Vector3(0.0, -atan2(delta.z, delta.x), 0.0)
		segment.material_override = _valid_path_material if is_valid else _invalid_path_material
		segment.visible = true


func _ensure_path_segment(index: int) -> MeshInstance3D:
	while _path_segments.size() <= index:
		var segment := MeshInstance3D.new()
		segment.name = "PathSegment_%d" % _path_segments.size()
		segment.visible = false
		segment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		segment.mesh = BoxMesh.new()
		_path_preview_root.add_child(segment)
		_path_segments.append(segment)
	return _path_segments[index]


func _clear_grid_target() -> void:
	if grid_selection_controller != null:
		grid_selection_controller.cancel_selection()
	_hide_prediction()


func _reject(vehicle_id: StringName, target_anchor: Vector2i, reason: StringName) -> void:
	_last_rejection_reason = reason
	move_rejected.emit(vehicle_id, target_anchor, reason)


func _hide_prediction() -> void:
	_preview_is_valid = false
	_preview_path.clear()
	if _target_preview != null:
		_target_preview.visible = false
	_hide_path_segments()


func _hide_path_segments() -> void:
	for segment in _path_segments:
		if segment != null:
			segment.visible = false


func _create_target_preview() -> MeshInstance3D:
	var preview := MeshInstance3D.new()
	preview.name = "VehicleTargetFootprintPreview"
	preview.visible = false
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	preview.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = false
	material.albedo_color = valid_target_color
	preview.material_override = material
	return preview


func _create_path_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = false
	material.albedo_color = color
	return material

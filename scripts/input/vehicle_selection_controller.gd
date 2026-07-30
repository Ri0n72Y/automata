class_name VehicleSelectionController
extends Node3D

signal selection_changed(vehicle_id: StringName, has_selection: bool)

const VehicleActorScript := preload("res://scripts/vehicles/vehicle_actor.gd")
const VehicleRuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")

@export var vehicle_collision_mask: int = 2
@export_range(1.0, 1000.0, 1.0) var ray_length: float = 200.0
@export var selection_color: Color = Color(1.0, 0.85, 0.15, 0.28)
@export_range(1.0, 1.3, 0.01) var highlight_scale: float = 1.08

var camera: Camera3D
var vehicle_manager: Node
var _selected_vehicle: VehicleActorScript
var _selection_highlight: MeshInstance3D


func _ready() -> void:
	_selection_highlight = _create_selection_highlight()
	add_child(_selection_highlight)
	_selection_highlight.top_level = true
	set_process(false)


func configure(p_camera: Camera3D, p_vehicle_manager: Node) -> void:
	camera = p_camera
	vehicle_manager = p_vehicle_manager
	if _selected_vehicle != null and not _is_current_vehicle(_selected_vehicle):
		_clear_selection(true)


func _process(_delta: float) -> void:
	var vehicle := get_selected_vehicle()
	if vehicle == null:
		return
	_update_highlight(vehicle)


func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if _is_move_command_active():
		return
	if get_viewport().gui_get_hovered_control() != null:
		return
	if select_from_screen_position(event.position):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			if _is_move_command_active():
				return
			cancel_selection()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if _is_move_command_active():
				return
			cancel_selection()


func select_from_screen_position(screen_position: Vector2) -> bool:
	var hit := _raycast_vehicle(screen_position)
	if hit.is_empty():
		return false
	var collider := hit.get("collider") as Area3D
	if collider == null:
		return false
	var vehicle_id: StringName = collider.get_meta("vehicle_id", &"")
	if vehicle_id == &"" or vehicle_manager == null:
		return false
	var vehicle := vehicle_manager.call("get_vehicle_by_id", vehicle_id) as VehicleActorScript
	return select_vehicle(vehicle)


func select_vehicle(vehicle: VehicleActorScript) -> bool:
	if vehicle == null or not is_instance_valid(vehicle) or not _is_current_vehicle(vehicle):
		return false
	if _has_other_active_vehicle(vehicle):
		return false
	if _selected_vehicle == vehicle:
		_update_highlight(vehicle)
		return true
	_selected_vehicle = vehicle
	_update_highlight(vehicle)
	set_process(true)
	selection_changed.emit(_selected_vehicle.get_vehicle_id(), true)
	return true


func cancel_selection() -> void:
	_clear_selection(true)


func has_selected_vehicle() -> bool:
	return get_selected_vehicle() != null


func get_selected_vehicle() -> VehicleActorScript:
	if _selected_vehicle == null:
		return null
	if not is_instance_valid(_selected_vehicle) or not _is_current_vehicle(_selected_vehicle):
		_clear_selection(true)
		return null
	return _selected_vehicle


func get_selected_vehicle_id() -> StringName:
	var vehicle := get_selected_vehicle()
	if vehicle == null:
		return &""
	return vehicle.get_vehicle_id()


func is_selection_highlight_visible() -> bool:
	return _selection_highlight != null and _selection_highlight.visible


func refresh_highlight() -> void:
	var vehicle := get_selected_vehicle()
	if vehicle != null:
		_update_highlight(vehicle)


func _clear_selection(emit_change: bool) -> void:
	if _selected_vehicle == null:
		_hide_highlight()
		set_process(false)
		return
	_selected_vehicle = null
	_hide_highlight()
	set_process(false)
	if emit_change:
		selection_changed.emit(&"", false)


func _is_move_command_active() -> bool:
	var grid_selection := get_parent().get_node_or_null("GridSelectionController")
	return (
		grid_selection != null
		and grid_selection.has_method("is_live_target_mode")
		and bool(grid_selection.call("is_live_target_mode"))
	)


func _has_other_active_vehicle(candidate: VehicleActorScript) -> bool:
	if vehicle_manager == null or not vehicle_manager.has_method("get_vehicles"):
		return false
	var vehicle_nodes: Array = vehicle_manager.call("get_vehicles")
	for vehicle_node in vehicle_nodes:
		var other: VehicleActorScript = vehicle_node as VehicleActorScript
		if other == null or other == candidate or other.runtime_state == null:
			continue
		if (
			other.runtime_state.motion_state == VehicleRuntimeStateScript.MotionState.PLANNING
			or other.runtime_state.motion_state == VehicleRuntimeStateScript.MotionState.MOVING
		):
			return true
	return false


func _is_current_vehicle(vehicle: VehicleActorScript) -> bool:
	if vehicle_manager == null or vehicle == null:
		return false
	return vehicle_manager.call("get_vehicle_by_id", vehicle.get_vehicle_id()) == vehicle


func _update_highlight(vehicle: VehicleActorScript) -> void:
	if _selection_highlight == null or vehicle.definition == null:
		return
	var footprint: Vector2i = vehicle.definition.footprint
	var body_height := vehicle.cell_size * 0.36
	var mesh := _selection_highlight.mesh as BoxMesh
	mesh.size = Vector3(
		float(footprint.x) * vehicle.cell_size * highlight_scale,
		body_height,
		float(footprint.y) * vehicle.cell_size * highlight_scale
	)
	_selection_highlight.global_transform = Transform3D(
		vehicle.global_basis,
		vehicle.global_position + vehicle.global_basis.y.normalized() * body_height * 0.5
	)
	_selection_highlight.visible = true


func _hide_highlight() -> void:
	if _selection_highlight != null:
		_selection_highlight.visible = false


func _create_selection_highlight() -> MeshInstance3D:
	var highlight := MeshInstance3D.new()
	highlight.name = "VehicleSelectionHighlight"
	highlight.visible = false
	highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := BoxMesh.new()
	highlight.mesh = mesh
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = selection_color
	material.no_depth_test = true
	highlight.material_override = material
	return highlight


func _raycast_vehicle(screen_position: Vector2) -> Dictionary:
	var active_camera := camera
	if active_camera == null:
		active_camera = get_viewport().get_camera_3d()
	if active_camera == null or get_world_3d() == null:
		return {}
	var ray_origin := active_camera.project_ray_origin(screen_position)
	var ray_direction := active_camera.project_ray_normal(screen_position)
	var query := PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_direction * ray_length,
		vehicle_collision_mask
	)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	return get_world_3d().direct_space_state.intersect_ray(query)

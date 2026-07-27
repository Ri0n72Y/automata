class_name GridSelectionController
extends Node3D

signal hover_changed(cell: Vector2i, has_hover: bool)
signal selection_changed(cell: Vector2i, has_selection: bool)
signal selection_confirmed(cell: Vector2i)

const INVALID_CELL := Vector2i(-1, -1)

@export var ground_collision_mask: int = 1
@export_range(1.0, 1000.0, 1.0) var ray_length: float = 200.0
@export_range(0.01, 0.2, 0.01) var highlight_height: float = 0.03
@export_range(0.5, 1.0, 0.01) var highlight_scale: float = 0.88
@export var hover_color: Color = Color(0.25, 0.75, 1.0, 0.18)
@export var selected_color: Color = Color(1.0, 0.68, 0.1, 0.26)

var controller: Node
var camera: Camera3D
var hovered_cell: Vector2i = INVALID_CELL
var selected_cell: Vector2i = INVALID_CELL
var _cell_size: float = 1.0
var _target_footprint: Vector2i = Vector2i.ONE
var _live_target_mode: bool = false
var _last_hover_world_position: Vector3 = Vector3.ZERO
var _has_hover_world_position: bool = false
var _hover_highlight: MeshInstance3D
var _selected_highlight: MeshInstance3D


func _ready() -> void:
	_hover_highlight = _create_highlight("HoverHighlight", hover_color)
	_selected_highlight = _create_highlight("SelectedHighlight", selected_color)
	add_child(_hover_highlight)
	add_child(_selected_highlight)
	_update_highlight_sizes()


func configure(
	p_controller: Node,
	p_camera: Camera3D,
	p_cell_size: float
) -> void:
	controller = p_controller
	camera = p_camera
	_cell_size = maxf(p_cell_size, 0.01)
	_update_highlight_sizes()
	_recalculate_hover_for_current_footprint()
	refresh_visuals()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		update_hover_from_screen_position(event.position)
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			select_from_screen_position(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_selection()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER:
			confirm_selection()
		elif event.keycode == KEY_ESCAPE:
			cancel_selection()


func set_live_target_mode(
	enabled: bool,
	footprint: Vector2i = Vector2i.ONE
) -> void:
	_target_footprint = Vector2i(
		maxi(footprint.x, 1),
		maxi(footprint.y, 1)
	)
	_live_target_mode = enabled
	_recalculate_hover_for_current_footprint()
	if _live_target_mode:
		_hide_default_highlights()
		if has_hovered_cell():
			_set_selected_cell(hovered_cell)
		return
	cancel_selection()
	refresh_visuals()


func is_live_target_mode() -> bool:
	return _live_target_mode


func get_target_footprint() -> Vector2i:
	return _target_footprint


func update_hover_from_screen_position(screen_position: Vector2) -> bool:
	var hit := _raycast_ground(screen_position)
	if hit.is_empty():
		clear_hover()
		return false
	var world_position: Vector3 = hit["position"]
	return update_hover_from_world_position(world_position)


func select_from_screen_position(screen_position: Vector2) -> bool:
	var hit := _raycast_ground(screen_position)
	if hit.is_empty():
		clear_hover()
		cancel_selection()
		return false
	var world_position: Vector3 = hit["position"]
	return select_from_world_position(world_position)


func update_hover_from_world_position(world_position: Vector3) -> bool:
	var cell := _world_position_to_valid_cell(world_position)
	if cell == INVALID_CELL:
		clear_hover()
		return false
	_last_hover_world_position = world_position
	_has_hover_world_position = true
	_set_hovered_cell(cell)
	if _live_target_mode:
		_set_selected_cell(cell)
	return true


func select_from_world_position(world_position: Vector3) -> bool:
	var cell := _world_position_to_valid_cell(world_position)
	if cell == INVALID_CELL:
		cancel_selection()
		return false
	_last_hover_world_position = world_position
	_has_hover_world_position = true
	_set_hovered_cell(cell)
	_set_selected_cell(cell)
	return true


func clear_hover() -> void:
	_has_hover_world_position = false
	if hovered_cell == INVALID_CELL:
		return
	hovered_cell = INVALID_CELL
	if _hover_highlight != null:
		_hover_highlight.visible = false
	hover_changed.emit(INVALID_CELL, false)
	if _live_target_mode:
		cancel_selection()


func cancel_selection() -> void:
	if selected_cell == INVALID_CELL:
		return
	selected_cell = INVALID_CELL
	if _selected_highlight != null:
		_selected_highlight.visible = false
	selection_changed.emit(INVALID_CELL, false)


func confirm_selection() -> bool:
	if not has_selected_cell() or not is_selected_cell_walkable():
		return false
	selection_confirmed.emit(selected_cell)
	return true


func has_hovered_cell() -> bool:
	return hovered_cell != INVALID_CELL


func has_selected_cell() -> bool:
	return selected_cell != INVALID_CELL


func is_selected_cell_walkable() -> bool:
	if controller == null or not has_selected_cell():
		return false
	return bool(controller.call("is_grid_cell_walkable", selected_cell))


func refresh_visuals() -> void:
	_hide_default_highlights()
	if _live_target_mode:
		return
	if has_hovered_cell():
		_position_highlight(_hover_highlight, hovered_cell)
	if has_selected_cell():
		_position_highlight(_selected_highlight, selected_cell)


func _recalculate_hover_for_current_footprint() -> void:
	if not _has_hover_world_position or controller == null:
		return
	var recalculated_cell := _world_position_to_valid_cell(_last_hover_world_position)
	if recalculated_cell == INVALID_CELL:
		clear_hover()
		return
	_set_hovered_cell(recalculated_cell)


func _world_position_to_valid_cell(world_position: Vector3) -> Vector2i:
	if controller == null:
		return INVALID_CELL
	var containing_cell: Vector2i = controller.call("world_to_grid_cell", world_position)
	if not bool(controller.call("is_grid_cell_valid", containing_cell)):
		return INVALID_CELL
	var cell: Vector2i = controller.call(
		"world_to_nearest_grid_anchor",
		world_position,
		_target_footprint
	)
	if not bool(controller.call("is_grid_cell_valid", cell)):
		return INVALID_CELL
	return cell


func _set_hovered_cell(cell: Vector2i) -> void:
	if hovered_cell == cell:
		return
	hovered_cell = cell
	if not _live_target_mode:
		_position_highlight(_hover_highlight, cell)
	hover_changed.emit(cell, true)


func _set_selected_cell(cell: Vector2i) -> void:
	if selected_cell == cell:
		return
	selected_cell = cell
	if not _live_target_mode:
		_position_highlight(_selected_highlight, cell)
	selection_changed.emit(cell, true)


func _position_highlight(highlight: MeshInstance3D, cell: Vector2i) -> void:
	if highlight == null or controller == null or _live_target_mode:
		return
	var world_position: Vector3 = controller.call("grid_cell_to_world", cell)
	highlight.position = to_local(world_position) + Vector3.UP * highlight_height
	highlight.visible = true


func _hide_default_highlights() -> void:
	if _hover_highlight != null:
		_hover_highlight.visible = false
	if _selected_highlight != null:
		_selected_highlight.visible = false


func _raycast_ground(screen_position: Vector2) -> Dictionary:
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
		ground_collision_mask
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func _create_highlight(node_name: String, color: Color) -> MeshInstance3D:
	var highlight := MeshInstance3D.new()
	highlight.name = node_name
	highlight.visible = false
	highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mesh := BoxMesh.new()
	highlight.mesh = mesh

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = false
	highlight.material_override = material
	return highlight


func _update_highlight_sizes() -> void:
	var size := Vector3(_cell_size * highlight_scale, 0.015, _cell_size * highlight_scale)
	for highlight in [_hover_highlight, _selected_highlight]:
		if highlight == null:
			continue
		var mesh := highlight.mesh as BoxMesh
		if mesh != null:
			mesh.size = size
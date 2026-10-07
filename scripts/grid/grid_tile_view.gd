class_name GridTileView
extends Node3D

const GridModelScript := preload("res://scripts/grid/grid_model.gd")

@export_range(0.01, 0.5, 0.01) var tile_height: float = 0.08
@export var ground_collision_layer: int = 1

var _tiles_root: Node3D
var _surface_visuals: Node3D
var _playable_floor: MeshInstance3D
var _north_boundary: MeshInstance3D
var _south_boundary: MeshInstance3D
var _west_boundary: MeshInstance3D
var _east_boundary: MeshInstance3D
var _ground_body: StaticBody3D
var _surface_active: bool = false


func _ready() -> void:
	_bind_surface_nodes()
	_set_surface_visible(false)
	_set_ground_enabled(false)


func draw(model: GridModelScript) -> bool:
	return rebuild(model)


func rebuild(model: GridModelScript) -> bool:
	if model == null or not _bind_surface_nodes():
		_deactivate_field()
		return false
	if not _sync_surface_geometry(model) or not _sync_ground_geometry(model):
		_deactivate_field()
		return false

	_tiles_root.position = model.local_origin
	_tiles_root.scale = Vector3.ONE
	_set_surface_visible(true)
	_set_ground_enabled(true)
	_surface_active = true
	return true


func is_surface_active() -> bool:
	return _surface_active


func get_ground_body() -> StaticBody3D:
	if _ground_body == null:
		_bind_surface_nodes()
	return _ground_body


func _bind_surface_nodes() -> bool:
	if (
		_tiles_root != null
		and _surface_visuals != null
		and _playable_floor != null
		and _north_boundary != null
		and _south_boundary != null
		and _west_boundary != null
		and _east_boundary != null
		and _ground_body != null
	):
		return true

	_tiles_root = get_node_or_null("Tiles") as Node3D
	_surface_visuals = get_node_or_null("Tiles/SurfaceVisuals") as Node3D
	_playable_floor = get_node_or_null("Tiles/SurfaceVisuals/PlayableFloor") as MeshInstance3D
	_north_boundary = get_node_or_null(
		"Tiles/SurfaceVisuals/WarningBoundary/NorthBoundaryCells"
	) as MeshInstance3D
	_south_boundary = get_node_or_null(
		"Tiles/SurfaceVisuals/WarningBoundary/SouthBoundaryCells"
	) as MeshInstance3D
	_west_boundary = get_node_or_null(
		"Tiles/SurfaceVisuals/WarningBoundary/WestBoundaryCells"
	) as MeshInstance3D
	_east_boundary = get_node_or_null(
		"Tiles/SurfaceVisuals/WarningBoundary/EastBoundaryCells"
	) as MeshInstance3D
	_ground_body = get_node_or_null("Tiles/GroundBody") as StaticBody3D
	return (
		_tiles_root != null
		and _surface_visuals != null
		and _playable_floor != null
		and _north_boundary != null
		and _south_boundary != null
		and _west_boundary != null
		and _east_boundary != null
		and _ground_body != null
	)


func _sync_surface_geometry(model: GridModelScript) -> bool:
	var width := float(model.width) * model.cell_size
	var height := float(model.height) * model.cell_size
	var boundary_width := model.cell_size
	var side_height := maxf(height - boundary_width * 2.0, 0.0)

	if not _set_plane_size(_playable_floor, Vector2(width, height)):
		return false
	if not _set_plane_size(_north_boundary, Vector2(width, boundary_width)):
		return false
	if not _set_plane_size(_south_boundary, Vector2(width, boundary_width)):
		return false
	if side_height > 0.0:
		if not _set_plane_size(_west_boundary, Vector2(boundary_width, side_height)):
			return false
		if not _set_plane_size(_east_boundary, Vector2(boundary_width, side_height)):
			return false

	_set_xz(_playable_floor, width * 0.5, height * 0.5)
	_set_xz(_north_boundary, width * 0.5, boundary_width * 0.5)
	_set_xz(_south_boundary, width * 0.5, height - boundary_width * 0.5)
	_set_xz(_west_boundary, boundary_width * 0.5, height * 0.5)
	_set_xz(_east_boundary, width - boundary_width * 0.5, height * 0.5)

	_west_boundary.visible = side_height > 0.0
	_east_boundary.visible = side_height > 0.0

	_playable_floor.set_instance_shader_parameter(
		&"tile_repeat",
		Vector2(float(model.width), float(model.height))
	)
	_north_boundary.set_instance_shader_parameter(
		&"tile_repeat",
		Vector2(float(model.width), 1.0)
	)
	_south_boundary.set_instance_shader_parameter(
		&"tile_repeat",
		Vector2(float(model.width), 1.0)
	)
	var side_repeat := maxf(float(model.height - 2), 1.0)
	_west_boundary.set_instance_shader_parameter(&"tile_repeat", Vector2(1.0, side_repeat))
	_east_boundary.set_instance_shader_parameter(&"tile_repeat", Vector2(1.0, side_repeat))

	_north_boundary.set_instance_shader_parameter(&"tile_origin", Vector2.ZERO)
	_south_boundary.set_instance_shader_parameter(
		&"tile_origin",
		Vector2(0.0, float(model.height - 1))
	)
	_west_boundary.set_instance_shader_parameter(&"tile_origin", Vector2(0.0, 1.0))
	_east_boundary.set_instance_shader_parameter(
		&"tile_origin",
		Vector2(float(model.width - 1), 1.0)
	)
	return true


func _sync_ground_geometry(model: GridModelScript) -> bool:
	if _ground_body == null:
		return false
	var ground_shape := _ground_body.get_node_or_null("GroundShape") as CollisionShape3D
	if ground_shape == null:
		return false
	var box_shape := ground_shape.shape as BoxShape3D
	if box_shape == null:
		return false

	var ground_depth := maxf(tile_height, 0.05)
	box_shape.size = Vector3(
		float(model.width) * model.cell_size,
		ground_depth,
		float(model.height) * model.cell_size
	)
	ground_shape.position = Vector3(
		float(model.width) * model.cell_size * 0.5,
		-ground_depth * 0.5,
		float(model.height) * model.cell_size * 0.5
	)
	return true


func _set_plane_size(mesh_instance: MeshInstance3D, size: Vector2) -> bool:
	if mesh_instance == null:
		return false
	var plane := mesh_instance.mesh as PlaneMesh
	if plane == null:
		return false
	plane.size = size
	return true


func _set_xz(node: Node3D, x: float, z: float) -> void:
	var position := node.position
	position.x = x
	position.z = z
	node.position = position


func _deactivate_field() -> void:
	_surface_active = false
	_set_surface_visible(false)
	_set_ground_enabled(false)


func _set_surface_visible(visible: bool) -> void:
	if _surface_visuals != null:
		_surface_visuals.visible = visible


func _set_ground_enabled(enabled: bool) -> void:
	if _ground_body == null:
		return
	_ground_body.collision_layer = ground_collision_layer if enabled else 0
	_ground_body.collision_mask = 0
	var ground_shape := _ground_body.get_node_or_null("GroundShape") as CollisionShape3D
	if ground_shape != null:
		ground_shape.disabled = not enabled

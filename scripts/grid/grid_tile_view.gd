class_name GridTileView
extends Node3D

const GridModelScript := preload("res://scripts/grid/grid_model.gd")

@export_range(0.01, 0.5, 0.01) var tile_height: float = 0.08
@export var ground_collision_layer: int = 1

@export_group("Flat Surface")
@export var use_flat_static_surface: bool = false
@export_range(1, 256, 1) var flat_surface_grid_width: int = 12
@export_range(1, 256, 1) var flat_surface_grid_height: int = 8
@export_range(0.01, 16.0, 0.01) var flat_surface_cell_size: float = 1.0

var _tiles_root: Node3D
var _surface_visuals: Node3D
var _ground_body: StaticBody3D
var _surface_active: bool = false


func _ready() -> void:
	_bind_surface_nodes()
	_set_surface_visible(false)
	_set_ground_enabled(false)


func draw(model: GridModelScript) -> void:
	rebuild(model)


func rebuild(model: GridModelScript) -> void:
	if not use_flat_static_surface or model == null or not _bind_surface_nodes():
		_surface_active = false
		_set_surface_visible(false)
		_set_ground_enabled(false)
		return

	_tiles_root.position = model.local_origin
	_tiles_root.scale = Vector3.ONE
	_sync_ground_geometry(model)
	_set_ground_enabled(true)

	_surface_active = _surface_geometry_matches_model(model)
	_set_surface_visible(_surface_active)


func is_surface_active() -> bool:
	return _surface_active


func get_ground_body() -> StaticBody3D:
	if _ground_body == null:
		_bind_surface_nodes()
	return _ground_body


func _bind_surface_nodes() -> bool:
	if _tiles_root != null and _surface_visuals != null and _ground_body != null:
		return true

	_tiles_root = get_node_or_null("Tiles") as Node3D
	_surface_visuals = get_node_or_null("Tiles/SurfaceVisuals") as Node3D
	_ground_body = get_node_or_null("Tiles/GroundBody") as StaticBody3D
	return _tiles_root != null and _surface_visuals != null and _ground_body != null


func _surface_geometry_matches_model(model: GridModelScript) -> bool:
	return (
		model.width == flat_surface_grid_width
		and model.height == flat_surface_grid_height
		and is_equal_approx(model.cell_size, flat_surface_cell_size)
	)


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


func _sync_ground_geometry(model: GridModelScript) -> void:
	if _ground_body == null:
		return
	var ground_shape := _ground_body.get_node_or_null("GroundShape") as CollisionShape3D
	if ground_shape == null:
		return
	var box_shape := ground_shape.shape as BoxShape3D
	if box_shape == null:
		return

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

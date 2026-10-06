class_name GridTileView
extends Node3D

const GridModelScript := preload("res://scripts/grid/grid_model.gd")

enum RenderMode {
	NONE,
	FLAT_STATIC,
}

@export_range(0.01, 0.5, 0.01) var tile_height: float = 0.08
@export var ground_collision_layer: int = 1

@export_group("Flat Surface")
@export var use_flat_static_surface: bool = false
@export_range(1, 256, 1) var flat_surface_grid_width: int = 12
@export_range(1, 256, 1) var flat_surface_grid_height: int = 8
@export_range(0.01, 16.0, 0.01) var flat_surface_cell_size: float = 1.0

var _flat_surface_container: Node3D
var _render_mode: int = RenderMode.NONE
var _tile_count: int = 0


func _ready() -> void:
	if use_flat_static_surface and _bind_flat_surface():
		_activate_flat_static_surface()


func draw(model: GridModelScript) -> void:
	rebuild(model)


func rebuild(model: GridModelScript) -> void:
	if use_flat_static_surface and _apply_model_to_flat_static_surface(model):
		return
	_deactivate_flat_static_surface()
	_tile_count = 0
	_render_mode = RenderMode.NONE


func get_tile_count() -> int:
	return _tile_count


## Kept as a compatibility query for consumers that only distinguish
## scene-owned rendering from generated runtime geometry.
func is_using_static_scene() -> bool:
	return is_using_flat_static_surface()


func is_using_flat_static_surface() -> bool:
	return _render_mode == RenderMode.FLAT_STATIC


## Per-cell runtime mesh generation is intentionally no longer supported.
func is_using_dynamic_scene() -> bool:
	return false


## Flat surfaces do not own a MeshInstance3D per logical grid cell.
func get_tile_node(_cell: Vector2i) -> MeshInstance3D:
	return null


func get_ground_body() -> StaticBody3D:
	if _render_mode != RenderMode.FLAT_STATIC:
		return null
	return get_node_or_null("Tiles/GroundBody") as StaticBody3D


func _bind_flat_surface() -> bool:
	var tiles := get_node_or_null("Tiles") as Node3D
	var ground_body := get_node_or_null("Tiles/GroundBody") as StaticBody3D
	if tiles == null or ground_body == null:
		return false
	_flat_surface_container = tiles
	return true


func _activate_flat_static_surface() -> bool:
	if _flat_surface_container == null and not _bind_flat_surface():
		return false
	_flat_surface_container.visible = true
	var ground_body := _flat_surface_container.get_node_or_null("GroundBody") as StaticBody3D
	if ground_body == null:
		return false
	ground_body.collision_layer = ground_collision_layer
	ground_body.collision_mask = 0
	var ground_shape := ground_body.get_node_or_null("GroundShape") as CollisionShape3D
	if ground_shape != null:
		ground_shape.disabled = false
	_render_mode = RenderMode.FLAT_STATIC
	return true


func _deactivate_flat_static_surface() -> void:
	if _flat_surface_container == null and not _bind_flat_surface():
		return
	_flat_surface_container.visible = false
	var ground_body := _flat_surface_container.get_node_or_null("GroundBody") as StaticBody3D
	if ground_body == null:
		return
	ground_body.collision_layer = 0
	var ground_shape := ground_body.get_node_or_null("GroundShape") as CollisionShape3D
	if ground_shape != null:
		ground_shape.disabled = true


func _apply_model_to_flat_static_surface(model: GridModelScript) -> bool:
	if model == null:
		return false
	if model.width != flat_surface_grid_width or model.height != flat_surface_grid_height:
		return false
	if not is_equal_approx(model.cell_size, flat_surface_cell_size):
		return false
	if not _flat_static_surface_matches_model(model):
		return false
	if not _activate_flat_static_surface():
		return false

	_flat_surface_container.position = model.local_origin
	_flat_surface_container.scale = Vector3.ONE
	_tile_count = model.width * model.height
	_update_static_ground(model)
	return true


func _flat_static_surface_matches_model(model: GridModelScript) -> bool:
	for cell_y in range(model.height):
		for cell_x in range(model.width):
			var cell := Vector2i(cell_x, cell_y)
			var expected_type := GridModelScript.CellType.WHITE_POWER_TILE
			if (
				cell_x == 0
				or cell_y == 0
				or cell_x == model.width - 1
				or cell_y == model.height - 1
			):
				expected_type = GridModelScript.CellType.BOUNDARY
			if model.get_cell_type(cell) != expected_type:
				return false
	return true


func _update_static_ground(model: GridModelScript) -> void:
	var ground_body := get_ground_body()
	if ground_body == null:
		return
	ground_body.collision_layer = ground_collision_layer
	var ground_shape := ground_body.get_node_or_null("GroundShape") as CollisionShape3D
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

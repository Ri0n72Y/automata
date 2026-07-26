class_name GridTileView
extends Node3D

const GridModelScript := preload("res://scripts/grid/grid_model.gd")

@export_range(0.0, 0.25, 0.01) var tile_gap: float = 0.04
@export_range(0.01, 0.5, 0.01) var tile_height: float = 0.08
@export var normal_tile_color: Color = Color(0.45, 0.48, 0.52, 1.0)
@export var power_tile_color: Color = Color(0.92, 0.96, 1.0, 1.0)
@export var boundary_color: Color = Color(0.12, 0.15, 0.2, 1.0)
@export var ground_collision_layer: int = 1

var _active_tile_container: Node3D
var _draw_generation: int = 0
var _tile_count: int = 0


func draw(model: GridModelScript) -> void:
	rebuild(model)


func rebuild(model: GridModelScript) -> void:
	if _active_tile_container != null:
		_active_tile_container.queue_free()
		_active_tile_container = null
	_tile_count = 0

	if model == null:
		return

	_draw_generation += 1
	var container := Node3D.new()
	container.name = "TileBatch_%d" % _draw_generation
	add_child(container)
	_active_tile_container = container

	var tiles := Node3D.new()
	tiles.name = "Tiles"
	container.add_child(tiles)

	var tile_mesh := BoxMesh.new()
	var tile_size := maxf(model.cell_size - tile_gap, 0.01)
	tile_mesh.size = Vector3(tile_size, tile_height, tile_size)

	var normal_material := _create_tile_material(normal_tile_color)
	var power_material := _create_tile_material(power_tile_color, true)
	var boundary_material := _create_tile_material(boundary_color)

	for cell_y in range(model.height):
		for cell_x in range(model.width):
			var cell := Vector2i(cell_x, cell_y)
			var tile := MeshInstance3D.new()
			tile.name = "Tile_%d_%d" % [cell_x, cell_y]
			tile.mesh = tile_mesh
			tile.material_override = _material_for_cell_type(
				model.get_cell_type(cell),
				normal_material,
				power_material,
				boundary_material
			)
			tile.position = model.cell_to_position(cell) - Vector3.UP * tile_height * 0.5
			tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			tiles.add_child(tile)
			_tile_count += 1

	var ground_body := StaticBody3D.new()
	ground_body.name = "GroundBody"
	ground_body.collision_layer = ground_collision_layer
	ground_body.collision_mask = 0
	container.add_child(ground_body)

	var ground_shape := CollisionShape3D.new()
	ground_shape.name = "GroundShape"
	var box_shape := BoxShape3D.new()
	var ground_depth := maxf(tile_height, 0.05)
	box_shape.size = Vector3(
		float(model.width) * model.cell_size,
		ground_depth,
		float(model.height) * model.cell_size
	)
	ground_shape.shape = box_shape
	ground_shape.position = model.local_origin + Vector3(
		float(model.width) * model.cell_size * 0.5,
		-ground_depth * 0.5,
		float(model.height) * model.cell_size * 0.5
	)
	ground_body.add_child(ground_shape)


func get_tile_count() -> int:
	return _tile_count


func get_tile_node(cell: Vector2i) -> MeshInstance3D:
	if _active_tile_container == null:
		return null
	return _active_tile_container.get_node_or_null(
		"Tiles/Tile_%d_%d" % [cell.x, cell.y]
	) as MeshInstance3D


func get_ground_body() -> StaticBody3D:
	if _active_tile_container == null:
		return null
	return _active_tile_container.get_node_or_null("GroundBody") as StaticBody3D


func _create_tile_material(color: Color, use_emission: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	if use_emission:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.35
	return material


func _material_for_cell_type(
	cell_type: int,
	normal_material: StandardMaterial3D,
	power_material: StandardMaterial3D,
	boundary_material: StandardMaterial3D
) -> StandardMaterial3D:
	match cell_type:
		GridModelScript.CellType.NORMAL_TILE:
			return normal_material
		GridModelScript.CellType.WHITE_POWER_TILE:
			return power_material
		_:
			return boundary_material

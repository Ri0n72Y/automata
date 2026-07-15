class_name GridModel
extends RefCounted

var width: int
var height: int
var cell_size: float
var world_origin: Vector3


func _init(
	p_width: int = 1,
	p_height: int = 1,
	p_cell_size: float = 1.0,
	p_world_origin: Vector3 = Vector3.ZERO
) -> void:
	configure(p_width, p_height, p_cell_size, p_world_origin)


func configure(
	p_width: int,
	p_height: int,
	p_cell_size: float,
	p_world_origin: Vector3 = Vector3.ZERO
) -> void:
	assert(p_width > 0, "Grid width must be greater than zero.")
	assert(p_height > 0, "Grid height must be greater than zero.")
	assert(p_cell_size > 0.0, "Grid cell size must be greater than zero.")

	width = p_width
	height = p_height
	cell_size = p_cell_size
	world_origin = p_world_origin


## Converts a logical grid cell to its center point on the world XZ plane.
func cell_to_world(cell: Vector2i) -> Vector3:
	return world_origin + Vector3(
		(float(cell.x) + 0.5) * cell_size,
		0.0,
		(float(cell.y) + 0.5) * cell_size
	)


## Converts a world position on the XZ plane to its containing logical cell.
## The returned cell may be outside the configured grid; call is_cell_valid()
## when a bounded result is required.
func world_to_cell(world_position: Vector3) -> Vector2i:
	var local_position := world_position - world_origin
	return Vector2i(
		int(floor(local_position.x / cell_size)),
		int(floor(local_position.z / cell_size))
	)


func is_cell_valid(cell: Vector2i) -> bool:
	return (
		cell.x >= 0
		and cell.y >= 0
		and cell.x < width
		and cell.y < height
	)

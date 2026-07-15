class_name GridModel
extends RefCounted

var width: int = 1
var height: int = 1
var cell_size: float = 1.0
var local_origin: Vector3 = Vector3.ZERO


func _init(
	p_width: int = 1,
	p_height: int = 1,
	p_cell_size: float = 1.0,
	p_local_origin: Vector3 = Vector3.ZERO
) -> void:
	configure(p_width, p_height, p_cell_size, p_local_origin)


func configure(
	p_width: int,
	p_height: int,
	p_cell_size: float,
	p_local_origin: Vector3 = Vector3.ZERO
) -> bool:
	if p_width <= 0:
		push_error("Grid width must be greater than zero.")
		return false
	if p_height <= 0:
		push_error("Grid height must be greater than zero.")
		return false
	if p_cell_size <= 0.0:
		push_error("Grid cell size must be greater than zero.")
		return false

	width = p_width
	height = p_height
	cell_size = p_cell_size
	local_origin = p_local_origin
	return true


## Converts a logical grid cell to its center point in GridRoot-local XZ space.
func cell_to_local(cell: Vector2i) -> Vector3:
	return local_origin + Vector3(
		(float(cell.x) + 0.5) * cell_size,
		0.0,
		(float(cell.y) + 0.5) * cell_size
	)


## Converts a GridRoot-local position on the XZ plane to its containing cell.
## The returned cell may be outside the configured grid; call is_cell_valid()
## when a bounded result is required.
func local_to_cell(local_position: Vector3) -> Vector2i:
	var grid_position := local_position - local_origin
	return Vector2i(
		int(floor(grid_position.x / cell_size)),
		int(floor(grid_position.z / cell_size))
	)


func is_cell_valid(cell: Vector2i) -> bool:
	return (
		cell.x >= 0
		and cell.y >= 0
		and cell.x < width
		and cell.y < height
	)

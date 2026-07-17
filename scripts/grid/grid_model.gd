class_name GridModel
extends RefCounted

enum CellType {
	NORMAL_TILE,
	WHITE_POWER_TILE,
	BOUNDARY,
}

var _width: int = 1
var _height: int = 1
var _cell_size: float = 1.0
var _local_origin: Vector3 = Vector3.ZERO
var _cell_types: PackedInt32Array = PackedInt32Array()

var width: int:
	get:
		return _width

var height: int:
	get:
		return _height

var cell_size: float:
	get:
		return _cell_size

var local_origin: Vector3:
	get:
		return _local_origin


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

	var cell_types := _build_default_cell_types(p_width, p_height)
	_width = p_width
	_height = p_height
	_cell_size = p_cell_size
	_local_origin = p_local_origin
	_cell_types = cell_types
	return true


## Converts a logical grid cell to its center position in GridRoot-local XZ space.
func cell_to_position(cell: Vector2i) -> Vector3:
	return _local_origin + Vector3(
		(float(cell.x) + 0.5) * _cell_size,
		0.0,
		(float(cell.y) + 0.5) * _cell_size
	)


## Converts a position in GridRoot-local XZ space to its containing cell.
## The returned cell may be outside the configured grid; call is_cell_valid()
## when a bounded result is required.
func position_to_cell(position: Vector3) -> Vector2i:
	var grid_position := position - _local_origin
	return Vector2i(
		int(floor(grid_position.x / _cell_size)),
		int(floor(grid_position.z / _cell_size))
	)


func is_cell_valid(cell: Vector2i) -> bool:
	return (
		cell.x >= 0
		and cell.y >= 0
		and cell.x < _width
		and cell.y < _height
	)


func get_cell_type(cell: Vector2i) -> int:
	if not is_cell_valid(cell):
		return CellType.BOUNDARY
	if _cell_types.size() != _width * _height:
		return CellType.BOUNDARY
	return _cell_types[_cell_index(cell)]


func is_cell_walkable(cell: Vector2i) -> bool:
	return is_cell_valid(cell) and get_cell_type(cell) != CellType.BOUNDARY


## Internal mutation used by the scene controller so model and views stay synchronized.
func _set_cell_type(cell: Vector2i, cell_type: int) -> bool:
	if not is_cell_valid(cell):
		return false
	if cell_type < CellType.NORMAL_TILE or cell_type > CellType.BOUNDARY:
		return false
	if _cell_types.size() != _width * _height:
		return false
	_cell_types[_cell_index(cell)] = cell_type
	return true


func _cell_index(cell: Vector2i) -> int:
	return cell.y * _width + cell.x


func _build_default_cell_types(p_width: int, p_height: int) -> PackedInt32Array:
	var cell_types := PackedInt32Array()
	cell_types.resize(p_width * p_height)
	cell_types.fill(CellType.WHITE_POWER_TILE)

	for cell_y in range(p_height):
		for cell_x in range(p_width):
			if (
				cell_x == 0
				or cell_y == 0
				or cell_x == p_width - 1
				or cell_y == p_height - 1
			):
				cell_types[cell_y * p_width + cell_x] = CellType.BOUNDARY

	return cell_types

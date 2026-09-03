class_name AssemblySimulationEnvelope
extends RefCounted

var _occupied_cells: Array[Vector2i] = []


func _init(cells: Array[Vector2i] = []) -> void:
	_occupied_cells = cells.duplicate()


func get_occupied_cells() -> Array[Vector2i]:
	return _occupied_cells.duplicate()


func contains_cell(cell: Vector2i) -> bool:
	return _occupied_cells.has(cell)


func size() -> int:
	return _occupied_cells.size()

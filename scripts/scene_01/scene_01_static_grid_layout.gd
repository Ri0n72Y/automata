class_name Scene01StaticGridLayout
extends Node

const GridModelScript := preload("res://scripts/grid/grid_model.gd")

@export var scene_controller_path: NodePath = NodePath("../../..")
@export var boundary_cells: Array[Vector2i] = []


func _enter_tree() -> void:
	var controller := get_node_or_null(scene_controller_path)
	if controller == null or not controller.has_method("set_grid_cell_type"):
		push_error("Scene 01 static grid layout requires the scene controller.")
		return
	for cell in boundary_cells:
		if not bool(controller.call("set_grid_cell_type", cell, GridModelScript.CellType.BOUNDARY)):
			push_error("Scene 01 static boundary cell is invalid: %s" % str(cell))

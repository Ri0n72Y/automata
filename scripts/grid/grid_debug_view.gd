class_name GridDebugView
extends Node3D

@export var show_coordinates: bool = true
@export var label_height: float = 0.02
@export var label_pixel_size: float = 0.01

var grid_model: GridModel


func configure(model: GridModel) -> void:
	grid_model = model
	rebuild()


func rebuild() -> void:
	for child in get_children():
		child.queue_free()

	if not show_coordinates or grid_model == null:
		return

	for cell_y in range(grid_model.height):
		for cell_x in range(grid_model.width):
			var cell := Vector2i(cell_x, cell_y)
			var label := Label3D.new()
			label.name = "Cell_%d_%d" % [cell_x, cell_y]
			label.text = "(%d, %d)" % [cell_x, cell_y]
			label.position = grid_model.cell_to_world(cell) + Vector3.UP * label_height
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.pixel_size = label_pixel_size
			add_child(label)

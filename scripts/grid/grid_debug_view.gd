class_name GridDebugView
extends Node3D

const GridModelScript := preload("res://scripts/grid/grid_model.gd")

@export var show_coordinates: bool = false
@export var label_height: float = 0.02
@export var label_pixel_size: float = 0.01
@export_range(1, 4096, 1) var max_debug_labels: int = 512

var _active_label_container: Node3D
var _draw_generation: int = 0


func draw(model: GridModelScript) -> void:
	rebuild(model)


func rebuild(model: GridModelScript) -> void:
	if _active_label_container != null:
		_active_label_container.queue_free()
		_active_label_container = null

	if not show_coordinates or model == null:
		return

	_draw_generation += 1
	var label_container := Node3D.new()
	label_container.name = "Labels_%d" % _draw_generation
	add_child(label_container)
	_active_label_container = label_container

	var label_limit := maxi(max_debug_labels, 1)
	var sample_step := _calculate_sample_step(model, label_limit)
	if sample_step > 1:
		push_warning(
			"Grid debug coordinates sampled every %d cells to stay below %d labels."
			% [sample_step, label_limit]
		)

	for cell_y in range(0, model.height, sample_step):
		for cell_x in range(0, model.width, sample_step):
			var cell := Vector2i(cell_x, cell_y)
			var label := Label3D.new()
			label.name = "Cell_%d_%d" % [cell_x, cell_y]
			label.text = "(%d, %d)" % [cell_x, cell_y]
			label.position = model.cell_to_position(cell) + Vector3.UP * label_height
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.pixel_size = label_pixel_size
			label_container.add_child(label)


func get_debug_label_count() -> int:
	if _active_label_container == null:
		return 0
	return _active_label_container.get_child_count()


func _calculate_sample_step(model: GridModelScript, label_limit: int) -> int:
	var sample_step := 1
	while (
		_ceil_div(model.width, sample_step)
		* _ceil_div(model.height, sample_step)
		> label_limit
	):
		sample_step += 1
	return sample_step


func _ceil_div(value: int, divisor: int) -> int:
	return int((value + divisor - 1) / divisor)

extends Node

var controller: Node
var grid_model_was_ready: bool = false
var conversion_succeeded: bool = false


func _ready() -> void:
	grid_model_was_ready = controller != null and controller.get("grid_model") != null
	if not grid_model_was_ready:
		return

	var world_position: Vector3 = controller.call(
		"grid_cell_to_world",
		Vector2i.ZERO
	)
	conversion_succeeded = world_position.is_equal_approx(Vector3(0.5, 0.0, 0.5))

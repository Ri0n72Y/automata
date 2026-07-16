class_name Scene01CameraRig
extends Node3D

@export_range(1.0, 2.0, 0.05) var framing_margin: float = 1.25
@export_range(0.5, 4.0, 0.1) var distance_multiplier: float = 1.5
@export_range(1.0, 90.0, 1.0) var minimum_distance: float = 10.0

@onready var camera: Camera3D = %SceneCamera


func configure_for_grid(
	world_center: Vector3,
	world_width: float,
	world_height: float
) -> void:
	if camera == null:
		push_error("Scene 01 camera rig is missing SceneCamera.")
		return

	global_position = world_center
	var diagonal := maxf(sqrt(world_width * world_width + world_height * world_height), 1.0)
	var distance := maxf(diagonal * distance_multiplier, minimum_distance)
	var horizontal_component := distance / sqrt(2.0)

	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = diagonal * framing_margin
	camera.near = 0.1
	camera.far = maxf(distance * 4.0, 100.0)
	camera.position = Vector3(horizontal_component, distance, horizontal_component)
	camera.look_at(world_center, Vector3.UP)
	camera.current = true


func get_camera() -> Camera3D:
	return camera


func get_orthographic_size() -> float:
	if camera == null:
		return 0.0
	return camera.size

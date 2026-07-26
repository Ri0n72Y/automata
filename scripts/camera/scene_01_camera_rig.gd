class_name Scene01CameraRig
extends Node3D

@export var auto_frame_grid: bool = true
@export_range(1.0, 2.0, 0.05) var framing_margin: float = 1.25
@export_range(0.5, 4.0, 0.1) var distance_multiplier: float = 1.5
@export_range(1.0, 90.0, 1.0) var minimum_distance: float = 10.0

@onready var camera: Camera3D = %SceneCamera


func _ready() -> void:
	if camera != null:
		camera.current = true


func configure_for_grid(
	world_center: Vector3,
	world_width: float,
	world_height: float
) -> void:
	if camera == null:
		push_error("Scene 01 camera rig is missing SceneCamera.")
		return
	if not auto_frame_grid:
		camera.current = true
		return

	global_position = world_center
	var diagonal := maxf(sqrt(world_width * world_width + world_height * world_height), 1.0)
	var distance := maxf(diagonal * distance_multiplier, minimum_distance)
	var horizontal_component := distance / sqrt(2.0)

	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.1
	camera.far = maxf(distance * 4.0, 100.0)
	camera.position = Vector3(horizontal_component, distance, horizontal_component)
	camera.look_at(world_center, Vector3.UP)
	camera.size = _calculate_required_size(world_center, world_width, world_height)
	camera.current = true


func get_camera() -> Camera3D:
	return camera


func get_orthographic_size() -> float:
	if camera == null:
		return 0.0
	return camera.size


func _calculate_required_size(
	world_center: Vector3,
	world_width: float,
	world_height: float
) -> float:
	var half_width := maxf(world_width, 0.01) * 0.5
	var half_height := maxf(world_height, 0.01) * 0.5
	var corners := [
		world_center + Vector3(-half_width, 0.0, -half_height),
		world_center + Vector3(half_width, 0.0, -half_height),
		world_center + Vector3(-half_width, 0.0, half_height),
		world_center + Vector3(half_width, 0.0, half_height),
	]

	var half_projected_width: float = 0.0
	var half_projected_height: float = 0.0
	for corner in corners:
		var camera_local_corner := camera.to_local(corner)
		half_projected_width = maxf(half_projected_width, absf(camera_local_corner.x))
		half_projected_height = maxf(half_projected_height, absf(camera_local_corner.y))

	var viewport_size := camera.get_viewport().get_visible_rect().size
	var viewport_aspect := 1.0
	if viewport_size.y > 0.0:
		viewport_aspect = maxf(viewport_size.x / viewport_size.y, 0.01)

	var required_height := maxf(
		half_projected_height * 2.0,
		half_projected_width * 2.0 / viewport_aspect
	)
	return maxf(required_height * framing_margin, 1.0)

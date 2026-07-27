class_name Scene01CameraRig
extends Node3D

signal view_direction_changed(direction: int)

enum ViewDirection {
	SOUTHEAST,
	SOUTHWEST,
	NORTHWEST,
	NORTHEAST,
}

const ROTATE_COUNTERCLOCKWISE_ACTION := &"camera_rotate_counterclockwise"
const ROTATE_CLOCKWISE_ACTION := &"camera_rotate_clockwise"

@export var auto_frame_grid: bool = true
@export_range(1.0, 2.0, 0.05) var framing_margin: float = 1.25
@export_range(0.5, 4.0, 0.1) var distance_multiplier: float = 1.5
@export_range(1.0, 90.0, 1.0) var minimum_distance: float = 10.0
@export var initial_view_direction: ViewDirection = ViewDirection.SOUTHEAST

@onready var camera: Camera3D = %SceneCamera

var _view_direction: int = ViewDirection.SOUTHEAST
var _world_center: Vector3 = Vector3.ZERO
var _world_width: float = 1.0
var _world_height: float = 1.0
var _is_configured: bool = false


func _ready() -> void:
	_view_direction = initial_view_direction
	if camera != null:
		camera.current = true


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo() or _is_text_input_focused():
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if (
			key_event.shift_pressed
			or key_event.ctrl_pressed
			or key_event.alt_pressed
			or key_event.meta_pressed
		):
			return
	if event.is_action_pressed(ROTATE_COUNTERCLOCKWISE_ACTION):
		rotate_counterclockwise()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(ROTATE_CLOCKWISE_ACTION):
		rotate_clockwise()
		get_viewport().set_input_as_handled()


func configure_for_grid(
	world_center: Vector3,
	world_width: float,
	world_height: float
) -> void:
	if camera == null:
		push_error("Scene 01 camera rig is missing SceneCamera.")
		return

	_world_center = world_center
	_world_width = maxf(world_width, 0.01)
	_world_height = maxf(world_height, 0.01)
	if not auto_frame_grid:
		_is_configured = false
		camera.current = true
		return

	_is_configured = true
	global_position = world_center
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.1
	camera.current = true
	_apply_view_direction()


func set_view_direction(direction: int) -> bool:
	if direction < ViewDirection.SOUTHEAST or direction > ViewDirection.NORTHEAST:
		push_error("Scene 01 camera view direction is invalid: %s." % str(direction))
		return false
	if _view_direction == direction:
		return true
	_view_direction = direction
	if _is_configured:
		_apply_view_direction()
	view_direction_changed.emit(_view_direction)
	return true


func rotate_clockwise() -> void:
	set_view_direction((_view_direction + 1) % ViewDirection.size())


func rotate_counterclockwise() -> void:
	set_view_direction((_view_direction - 1 + ViewDirection.size()) % ViewDirection.size())


func get_view_direction() -> int:
	return _view_direction


func get_camera() -> Camera3D:
	return camera


func get_orthographic_size() -> float:
	if camera == null:
		return 0.0
	return camera.size


func _is_text_input_focused() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit


func _apply_view_direction() -> void:
	if camera == null or not _is_configured:
		return
	var diagonal := maxf(
		sqrt(_world_width * _world_width + _world_height * _world_height),
		1.0
	)
	var distance := maxf(diagonal * distance_multiplier, minimum_distance)
	var horizontal_component := distance / sqrt(2.0)
	var horizontal_signs := _get_horizontal_signs(_view_direction)
	camera.position = Vector3(
		horizontal_signs.x * horizontal_component,
		distance,
		horizontal_signs.y * horizontal_component
	)
	camera.look_at(_world_center, Vector3.UP)
	camera.far = maxf(distance * 4.0, 100.0)
	camera.size = _calculate_required_size(_world_center, _world_width, _world_height)


func _get_horizontal_signs(direction: int) -> Vector2:
	match direction:
		ViewDirection.SOUTHEAST:
			return Vector2(1.0, 1.0)
		ViewDirection.SOUTHWEST:
			return Vector2(-1.0, 1.0)
		ViewDirection.NORTHWEST:
			return Vector2(-1.0, -1.0)
		ViewDirection.NORTHEAST:
			return Vector2(1.0, -1.0)
	return Vector2.ONE


func _calculate_required_size(
	world_center: Vector3,
	world_width: float,
	world_height: float
) -> float:
	var half_width := maxf(world_width, 0.01) * 0.5
	var half_height := maxf(world_height, 0.01) * 0.5
	var corners: Array[Vector3] = [
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

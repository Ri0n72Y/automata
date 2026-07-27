class_name Scene01CameraRig
extends Node3D

signal view_direction_changed(direction: int)
signal view_transition_started(from_direction: int, to_direction: int)
signal view_transition_finished(direction: int)

enum ViewDirection {
	SOUTHEAST,
	SOUTHWEST,
	NORTHWEST,
	NORTHEAST,
}

const ROTATE_COUNTERCLOCKWISE_ACTION := &"camera_rotate_counterclockwise"
const ROTATE_CLOCKWISE_ACTION := &"camera_rotate_clockwise"
const QUARTER_TURN_DEGREES := 90.0

@export var auto_frame_grid: bool = true
@export_range(1.0, 2.0, 0.05) var framing_margin: float = 1.25
@export_range(0.5, 4.0, 0.1) var distance_multiplier: float = 1.5
@export_range(1.0, 90.0, 1.0) var minimum_distance: float = 10.0
@export_range(10.0, 80.0, 1.0) var elevation_degrees: float = 30.0
@export_range(0.0, 1.0, 0.01) var rotation_duration: float = 0.28
@export var initial_view_direction: ViewDirection = ViewDirection.SOUTHEAST

@onready var camera: Camera3D = %SceneCamera

var _view_direction: int = ViewDirection.SOUTHEAST
var _world_center: Vector3 = Vector3.ZERO
var _world_width: float = 1.0
var _world_height: float = 1.0
var _orbit_camera_size: float = 1.0
var _is_configured: bool = false
var _rendered_azimuth_degrees: float = 45.0
var _transition_tween: Tween
var _transition_generation: int = 0
var _input_origin_direction: int = ViewDirection.SOUTHEAST
var _input_target_direction: int = ViewDirection.SOUTHEAST
var _input_rotation_sign: int = 0


func _ready() -> void:
	_ensure_input_actions()
	_view_direction = initial_view_direction
	_rendered_azimuth_degrees = _get_direction_azimuth(_view_direction)
	_clear_input_transition()
	if camera != null:
		camera.current = true


func _exit_tree() -> void:
	_kill_transition()


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
	_ensure_input_actions()
	if event.is_action_pressed(ROTATE_CLOCKWISE_ACTION):
		rotate_clockwise()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(ROTATE_COUNTERCLOCKWISE_ACTION):
		rotate_counterclockwise()
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
	_kill_transition()
	_clear_input_transition()
	if not auto_frame_grid:
		_is_configured = false
		camera.current = true
		return

	_is_configured = true
	global_position = world_center
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.1
	camera.far = maxf(_calculate_orbit_distance() * 4.0, 100.0)
	camera.current = true
	_orbit_camera_size = _calculate_orbit_safe_size()
	camera.size = _orbit_camera_size
	_rendered_azimuth_degrees = _get_direction_azimuth(_view_direction)
	_set_camera_azimuth(_rendered_azimuth_degrees)


func set_view_direction(direction: int, animate: bool = true) -> bool:
	_clear_input_transition()
	return _set_view_direction(direction, animate, 0)


func rotate_clockwise(animate: bool = true) -> void:
	_request_rotation(1, animate)


func rotate_counterclockwise(animate: bool = true) -> void:
	_request_rotation(-1, animate)


func get_view_direction() -> int:
	return _view_direction


func get_camera() -> Camera3D:
	return camera


func get_orthographic_size() -> float:
	if camera == null:
		return 0.0
	return camera.size


func is_transitioning() -> bool:
	return _transition_tween != null and _transition_tween.is_valid()


func _request_rotation(rotation_sign: int, animate: bool) -> void:
	var normalized_sign := clampi(rotation_sign, -1, 1)
	if normalized_sign == 0:
		return
	if not animate:
		_clear_input_transition()
		_set_view_direction(
			_wrap_direction(_view_direction + normalized_sign),
			false,
			normalized_sign
		)
		return

	if _input_rotation_sign == 0 or not is_transitioning():
		_input_origin_direction = _view_direction
		_input_rotation_sign = normalized_sign
		_input_target_direction = _wrap_direction(
			_input_origin_direction + _input_rotation_sign
		)
		_set_view_direction(
			_input_target_direction,
			true,
			_input_rotation_sign
		)
		return

	var desired_direction := (
		_input_target_direction
		if normalized_sign == _input_rotation_sign
		else _input_origin_direction
	)
	if desired_direction == _view_direction:
		return
	_set_view_direction(desired_direction, true, normalized_sign)


func _set_view_direction(
	direction: int,
	animate: bool,
	preferred_rotation_sign: int
) -> bool:
	if direction < ViewDirection.SOUTHEAST or direction > ViewDirection.NORTHEAST:
		push_error("Scene 01 camera view direction is invalid: %s." % str(direction))
		return false
	if _view_direction == direction:
		if _is_configured and not animate:
			_kill_transition()
			_rendered_azimuth_degrees = _get_direction_azimuth(direction)
			_set_camera_azimuth(_rendered_azimuth_degrees)
			_clear_input_transition()
		return true

	var previous_direction := _view_direction
	_view_direction = direction
	var transition_started := false
	if _is_configured:
		transition_started = _apply_view_direction(animate, preferred_rotation_sign)
	view_direction_changed.emit(_view_direction)
	if transition_started:
		view_transition_started.emit(previous_direction, _view_direction)
	else:
		_clear_input_transition()
	return true


func _is_text_input_focused() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit


func _ensure_input_actions() -> void:
	_ensure_key_action(ROTATE_CLOCKWISE_ACTION, KEY_Q)
	_ensure_key_action(ROTATE_COUNTERCLOCKWISE_ACTION, KEY_E)


func _ensure_key_action(action: StringName, keycode: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var key_event := InputEventKey.new()
	key_event.keycode = keycode
	InputMap.action_add_event(action, key_event)


func _apply_view_direction(animate: bool, preferred_rotation_sign: int) -> bool:
	if camera == null or not _is_configured:
		return false

	var canonical_target := _get_direction_azimuth(_view_direction)
	if not animate or rotation_duration <= 0.0 or not is_inside_tree():
		_kill_transition()
		_rendered_azimuth_degrees = canonical_target
		_set_camera_azimuth(_rendered_azimuth_degrees)
		return false

	var direct_delta := _shortest_angular_delta(
		_rendered_azimuth_degrees,
		canonical_target
	)
	if absf(direct_delta) <= 0.001:
		_kill_transition()
		_rendered_azimuth_degrees = canonical_target
		_set_camera_azimuth(_rendered_azimuth_degrees)
		return false

	_kill_transition()
	var target_azimuth := _resolve_target_azimuth(
		canonical_target,
		preferred_rotation_sign
	)
	var angular_distance := absf(target_azimuth - _rendered_azimuth_degrees)
	if angular_distance <= 0.001:
		_rendered_azimuth_degrees = canonical_target
		_set_camera_azimuth(_rendered_azimuth_degrees)
		return false

	var effective_duration := rotation_duration * angular_distance / QUARTER_TURN_DEGREES
	_transition_generation += 1
	var generation := _transition_generation
	_transition_tween = create_tween()
	_transition_tween.set_trans(Tween.TRANS_SINE)
	_transition_tween.set_ease(Tween.EASE_IN_OUT)
	_transition_tween.tween_method(
		Callable(self, "_set_camera_azimuth"),
		_rendered_azimuth_degrees,
		target_azimuth,
		effective_duration
	)
	_transition_tween.finished.connect(
		_on_transition_finished.bind(_view_direction, canonical_target, generation)
	)
	return true


func _resolve_target_azimuth(
	canonical_target: float,
	preferred_rotation_sign: int
) -> float:
	var target := canonical_target
	if preferred_rotation_sign > 0:
		while target <= _rendered_azimuth_degrees + 0.001:
			target += 360.0
		return target
	if preferred_rotation_sign < 0:
		while target >= _rendered_azimuth_degrees - 0.001:
			target -= 360.0
		return target
	return _rendered_azimuth_degrees + _shortest_angular_delta(
		_rendered_azimuth_degrees,
		canonical_target
	)


func _shortest_angular_delta(from_degrees: float, to_degrees: float) -> float:
	return wrapf(to_degrees - from_degrees + 180.0, 0.0, 360.0) - 180.0


func _calculate_orbit_distance() -> float:
	var diagonal := maxf(
		sqrt(_world_width * _world_width + _world_height * _world_height),
		1.0
	)
	return maxf(diagonal * distance_multiplier, minimum_distance)


func _calculate_orbit_safe_size() -> float:
	var half_diagonal := sqrt(
		_world_width * _world_width + _world_height * _world_height
	) * 0.5
	var elevation_radians := deg_to_rad(clampf(elevation_degrees, 10.0, 80.0))
	var half_projected_height := half_diagonal * sin(elevation_radians)
	var half_projected_width := half_diagonal
	var viewport_size := camera.get_viewport().get_visible_rect().size
	var viewport_aspect := 1.0
	if viewport_size.y > 0.0:
		viewport_aspect = maxf(viewport_size.x / viewport_size.y, 0.01)
	var required_height := maxf(
		half_projected_height * 2.0,
		half_projected_width * 2.0 / viewport_aspect
	)
	return maxf(required_height * framing_margin, 1.0)


func _set_camera_azimuth(azimuth_degrees: float) -> void:
	if camera == null:
		return
	_rendered_azimuth_degrees = azimuth_degrees
	camera.position = _calculate_camera_position(azimuth_degrees)
	camera.look_at(_world_center, Vector3.UP)
	camera.size = _orbit_camera_size


func _calculate_camera_position(azimuth_degrees: float) -> Vector3:
	var orbit_distance := _calculate_orbit_distance()
	var elevation_radians := deg_to_rad(clampf(elevation_degrees, 10.0, 80.0))
	var azimuth_radians := deg_to_rad(azimuth_degrees)
	var horizontal_radius := orbit_distance * cos(elevation_radians)
	var vertical_height := orbit_distance * sin(elevation_radians)
	return Vector3(
		cos(azimuth_radians) * horizontal_radius,
		vertical_height,
		sin(azimuth_radians) * horizontal_radius
	)


func _on_transition_finished(
	target_direction: int,
	canonical_target: float,
	generation: int
) -> void:
	if generation != _transition_generation:
		return
	_transition_tween = null
	_rendered_azimuth_degrees = canonical_target
	_set_camera_azimuth(_rendered_azimuth_degrees)
	_clear_input_transition()
	view_transition_finished.emit(target_direction)


func _kill_transition() -> void:
	_transition_generation += 1
	if _transition_tween == null:
		return
	if _transition_tween.is_valid():
		_transition_tween.kill()
	_transition_tween = null


func _clear_input_transition() -> void:
	_input_origin_direction = _view_direction
	_input_target_direction = _view_direction
	_input_rotation_sign = 0


func _wrap_direction(direction: int) -> int:
	return posmod(direction, ViewDirection.size())


func _get_direction_azimuth(direction: int) -> float:
	match direction:
		ViewDirection.SOUTHEAST:
			return 45.0
		ViewDirection.SOUTHWEST:
			return 135.0
		ViewDirection.NORTHWEST:
			return 225.0
		ViewDirection.NORTHEAST:
			return 315.0
	return 45.0

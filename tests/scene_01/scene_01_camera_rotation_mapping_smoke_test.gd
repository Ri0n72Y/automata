extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const CAMERA_RIG_SCRIPT := preload("res://scripts/camera/scene_01_camera_rig.gd")
const GRID_SELECTION_SCRIPT := preload("res://scripts/input/grid_selection_controller.gd")
const MANUAL_CONTROLS_SCRIPT := preload("res://scripts/scene_01/scene_01_manual_controls.gd")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	_expect_true(packed_scene != null, "Scene 01 should load for camera rotation tests.")
	if packed_scene == null:
		_finish()
		return

	var scene := packed_scene.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await physics_frame

	var camera_rig := scene.get_node_or_null(
		"SceneRoot/CameraRoot/Scene01CameraRig"
	) as CAMERA_RIG_SCRIPT
	var selection := scene.get_node_or_null(
		"SceneRoot/GridRoot/GridSelectionController"
	) as GRID_SELECTION_SCRIPT
	var manual_controls := scene.get_node_or_null("UIRoot") as MANUAL_CONTROLS_SCRIPT
	var grid_root := scene.get_node_or_null("SceneRoot/GridRoot") as Node3D
	_expect_true(camera_rig != null, "Scene 01 should contain its camera rig.")
	_expect_true(selection != null, "Scene 01 should contain its grid selection controller.")
	_expect_true(manual_controls != null, "Scene 01 should contain its manual controls.")
	_expect_true(grid_root != null, "Scene 01 should contain GridRoot.")

	if camera_rig != null and selection != null:
		_test_camera_elevation(camera_rig)
		await _test_four_directions_preserve_click_mapping(scene, camera_rig, selection)
		_test_rotation_wraps(camera_rig)
		await _test_animated_rotation_has_fixed_framing(camera_rig)
		await _test_last_command_rotation_semantics(camera_rig)
		if manual_controls != null and grid_root != null:
			_test_shortcut_partition(scene, camera_rig, manual_controls, grid_root)
		await _test_rotation_input_actions(scene, camera_rig)

	current_scene = null
	scene.queue_free()
	await process_frame
	_finish()


func _test_camera_elevation(camera_rig: CAMERA_RIG_SCRIPT) -> void:
	_expect_close(
		camera_rig.elevation_degrees,
		30.0,
		0.01,
		"Camera rig should use the requested 30 degree elevation."
	)
	camera_rig.set_view_direction(CAMERA_RIG_SCRIPT.ViewDirection.SOUTHEAST, false)
	var camera: Camera3D = camera_rig.get_camera()
	_expect_true(camera != null, "Camera rig should expose SceneCamera for elevation tests.")
	if camera == null:
		return
	var horizontal_distance := Vector2(camera.position.x, camera.position.z).length()
	var actual_elevation := rad_to_deg(atan2(camera.position.y, horizontal_distance))
	_expect_close(
		actual_elevation,
		30.0,
		0.1,
		"Configured camera position should preserve a 30 degree elevation."
	)


func _test_four_directions_preserve_click_mapping(
	scene: Node,
	camera_rig: CAMERA_RIG_SCRIPT,
	selection: GRID_SELECTION_SCRIPT
) -> void:
	var test_cells: Array[Vector2i] = [
		Vector2i(1, 1),
		Vector2i(5, 3),
		Vector2i(10, 6),
	]
	var directions: Array[int] = [
		CAMERA_RIG_SCRIPT.ViewDirection.SOUTHEAST,
		CAMERA_RIG_SCRIPT.ViewDirection.SOUTHWEST,
		CAMERA_RIG_SCRIPT.ViewDirection.NORTHWEST,
		CAMERA_RIG_SCRIPT.ViewDirection.NORTHEAST,
	]
	var expected_signs: Array[Vector2] = [
		Vector2(1.0, 1.0),
		Vector2(-1.0, 1.0),
		Vector2(-1.0, -1.0),
		Vector2(1.0, -1.0),
	]

	for index in range(directions.size()):
		var direction: int = directions[index]
		_expect_true(
			camera_rig.set_view_direction(direction, false),
			"Camera should accept fixed direction %d." % direction
		)
		await process_frame
		await physics_frame
		_expect_equal(
			camera_rig.get_view_direction(),
			direction,
			"Camera should report the selected fixed direction."
		)
		var camera: Camera3D = camera_rig.get_camera()
		var signs: Vector2 = expected_signs[index]
		_expect_true(
			camera != null,
			"Camera rig should expose SceneCamera in direction %d." % direction
		)
		if camera == null:
			continue
		_expect_true(
			signf(camera.position.x) == signs.x and signf(camera.position.z) == signs.y,
			"Camera horizontal position should match fixed direction %d." % direction
		)

		for cell in test_cells:
			var world_position: Vector3 = scene.call("grid_cell_to_world", cell)
			var screen_position: Vector2 = camera.unproject_position(world_position)
			selection.cancel_selection()
			_expect_true(
				selection.select_from_screen_position(screen_position),
				"Screen ray should hit cell %s in direction %d." % [str(cell), direction]
			)
			_expect_equal(
				selection.selected_cell,
				cell,
				"Click mapping should preserve cell %s in direction %d." % [str(cell), direction]
			)


func _test_rotation_wraps(camera_rig: CAMERA_RIG_SCRIPT) -> void:
	camera_rig.set_view_direction(CAMERA_RIG_SCRIPT.ViewDirection.SOUTHEAST, false)
	camera_rig.rotate_counterclockwise(false)
	_expect_equal(
		camera_rig.get_view_direction(),
		CAMERA_RIG_SCRIPT.ViewDirection.NORTHEAST,
		"Counterclockwise rotation should wrap from southeast to northeast."
	)
	camera_rig.rotate_clockwise(false)
	_expect_equal(
		camera_rig.get_view_direction(),
		CAMERA_RIG_SCRIPT.ViewDirection.SOUTHEAST,
		"Clockwise rotation should wrap back to southeast."
	)
	for _step in range(4):
		camera_rig.rotate_clockwise(false)
	_expect_equal(
		camera_rig.get_view_direction(),
		CAMERA_RIG_SCRIPT.ViewDirection.SOUTHEAST,
		"Four clockwise rotations should return to the starting direction."
	)


func _test_animated_rotation_has_fixed_framing(
	camera_rig: CAMERA_RIG_SCRIPT
) -> void:
	camera_rig.set_view_direction(CAMERA_RIG_SCRIPT.ViewDirection.SOUTHEAST, false)
	var camera: Camera3D = camera_rig.get_camera()
	_expect_true(camera != null, "Camera rig should expose SceneCamera for animation tests.")
	if camera == null:
		return

	var started_transitions: Array[Vector2i] = []
	var finished_directions: Array[int] = []
	camera_rig.view_transition_started.connect(
		func(from_direction: int, to_direction: int) -> void:
			started_transitions.append(Vector2i(from_direction, to_direction))
	)
	camera_rig.view_transition_finished.connect(
		func(direction: int) -> void:
			finished_directions.append(direction)
	)

	var start_position: Vector3 = camera.position
	var start_horizontal_radius := Vector2(start_position.x, start_position.z).length()
	var start_size: float = camera.size
	camera_rig.rotate_clockwise(true)
	_expect_true(camera_rig.is_transitioning(), "Camera rotation should start a Tween transition.")
	_expect_true(
		camera.position.is_equal_approx(start_position),
		"Animated rotation should begin from the current rendered position without snapping."
	)
	_expect_close(
		camera.size,
		start_size,
		0.001,
		"Animated rotation should preserve its orthographic size at startup."
	)
	_expect_equal(started_transitions.size(), 1, "Animated rotation should emit one start signal.")
	if started_transitions.size() == 1:
		_expect_equal(
			started_transitions[0],
			Vector2i(
				CAMERA_RIG_SCRIPT.ViewDirection.SOUTHEAST,
				CAMERA_RIG_SCRIPT.ViewDirection.SOUTHWEST
			),
			"Transition start signal should describe the requested clockwise quarter turn."
		)

	await create_timer(maxf(camera_rig.rotation_duration * 0.5, 0.05)).timeout
	var middle_position: Vector3 = camera.position
	var middle_horizontal_radius := Vector2(
		middle_position.x,
		middle_position.z
	).length()
	var middle_elevation := rad_to_deg(atan2(
		middle_position.y,
		middle_horizontal_radius
	))
	_expect_true(
		not middle_position.is_equal_approx(start_position),
		"Camera position should change continuously during the rotation animation."
	)
	_expect_true(
		camera_rig.is_transitioning(),
		"Camera should still be transitioning near the middle of the configured duration."
	)
	_expect_close(
		middle_horizontal_radius,
		start_horizontal_radius,
		0.01,
		"Animated camera motion should follow a circular orbit instead of a straight chord."
	)
	_expect_close(
		middle_elevation,
		30.0,
		0.1,
		"Animated camera motion should preserve the 30 degree elevation."
	)
	_expect_close(
		camera.size,
		start_size,
		0.001,
		"Camera rotation should not zoom in or out at the middle of the orbit."
	)

	await create_timer(maxf(camera_rig.rotation_duration * 0.65, 0.1)).timeout
	_expect_true(not camera_rig.is_transitioning(), "Camera transition should finish on time.")
	_expect_equal(finished_directions.size(), 1, "Animated rotation should emit one finish signal.")
	if finished_directions.size() == 1:
		_expect_equal(
			finished_directions[0],
			CAMERA_RIG_SCRIPT.ViewDirection.SOUTHWEST,
			"Transition finish signal should report the final direction."
		)
	_expect_true(
		camera.position.x < 0.0 and camera.position.z > 0.0,
		"Animated clockwise rotation should finish in the southwest camera quadrant."
	)
	_expect_close(
		camera.size,
		start_size,
		0.001,
		"Camera rotation should finish with the same orthographic size."
	)


func _test_last_command_rotation_semantics(
	camera_rig: CAMERA_RIG_SCRIPT
) -> void:
	camera_rig.set_view_direction(CAMERA_RIG_SCRIPT.ViewDirection.SOUTHEAST, false)
	var camera: Camera3D = camera_rig.get_camera()
	_expect_true(camera != null, "Camera rig should expose SceneCamera for input coalescing tests.")
	if camera == null:
		return

	var immediate_start_position: Vector3 = camera.position
	camera_rig.rotate_clockwise(true)
	camera_rig.rotate_counterclockwise(true)
	_expect_equal(
		camera_rig.get_view_direction(),
		CAMERA_RIG_SCRIPT.ViewDirection.SOUTHEAST,
		"Immediate QE should keep the starting logical direction."
	)
	_expect_true(
		not camera_rig.is_transitioning(),
		"Immediate QE at the same rendered endpoint should cancel instead of orbiting 360 degrees."
	)
	_expect_true(
		camera.position.is_equal_approx(immediate_start_position),
		"Immediate QE should keep the camera at the starting endpoint."
	)

	camera_rig.rotate_clockwise(true)
	await create_timer(maxf(camera_rig.rotation_duration * 0.2, 0.04)).timeout
	camera_rig.rotate_clockwise(true)
	camera_rig.rotate_clockwise(true)
	_expect_equal(
		camera_rig.get_view_direction(),
		CAMERA_RIG_SCRIPT.ViewDirection.SOUTHWEST,
		"Repeated clockwise input during one transition should keep one adjacent target."
	)
	await create_timer(maxf(camera_rig.rotation_duration, 0.3)).timeout
	_expect_true(
		not camera_rig.is_transitioning(),
		"Repeated same-direction input should still finish after one quarter turn."
	)
	_expect_equal(
		camera_rig.get_view_direction(),
		CAMERA_RIG_SCRIPT.ViewDirection.SOUTHWEST,
		"Three quick clockwise commands should produce only one quarter turn."
	)

	camera_rig.set_view_direction(CAMERA_RIG_SCRIPT.ViewDirection.SOUTHEAST, false)
	var start_position: Vector3 = camera.position
	camera_rig.rotate_clockwise(true)
	await create_timer(maxf(camera_rig.rotation_duration * 0.45, 0.08)).timeout
	_expect_true(
		not camera.position.is_equal_approx(start_position),
		"Clockwise motion should be underway before reversal."
	)
	camera_rig.rotate_clockwise(true)
	camera_rig.rotate_counterclockwise(true)
	_expect_equal(
		camera_rig.get_view_direction(),
		CAMERA_RIG_SCRIPT.ViewDirection.SOUTHEAST,
		"The last opposite command should retarget the active transition to its origin."
	)
	await create_timer(maxf(camera_rig.rotation_duration, 0.3)).timeout
	_expect_true(
		not camera_rig.is_transitioning(),
		"Reversed transition should settle without queued extra turns."
	)
	_expect_equal(
		camera_rig.get_view_direction(),
		CAMERA_RIG_SCRIPT.ViewDirection.SOUTHEAST,
		"QQE should return to the starting direction instead of rotating farther."
	)
	_expect_true(
		camera.position.is_equal_approx(start_position),
		"QQE should return the rendered camera to its starting endpoint."
	)


func _test_shortcut_partition(
	scene: Node,
	camera_rig: CAMERA_RIG_SCRIPT,
	manual_controls: MANUAL_CONTROLS_SCRIPT,
	grid_root: Node3D
) -> void:
	scene.call("preview_restore_grid_transform")
	camera_rig.set_view_direction(CAMERA_RIG_SCRIPT.ViewDirection.SOUTHEAST, false)
	var restored_basis: Basis = grid_root.basis

	manual_controls._unhandled_key_input(_make_key_event(KEY_Q, true, false))
	_expect_true(
		grid_root.basis.is_equal_approx(restored_basis),
		"Plain Q should not rotate the GridRoot preview."
	)

	scene.call("preview_rotate_grid", 1)
	var expected_positive_basis: Basis = grid_root.basis
	scene.call("preview_restore_grid_transform")
	manual_controls._unhandled_key_input(_make_key_event(KEY_Q, true, false, true))
	_expect_true(
		grid_root.basis.is_equal_approx(expected_positive_basis),
		"Shift+Q should rotate GridRoot by positive 90 degrees."
	)
	_expect_equal(
		camera_rig.get_view_direction(),
		CAMERA_RIG_SCRIPT.ViewDirection.SOUTHEAST,
		"Shift+Q GridRoot rotation should preserve camera direction."
	)

	scene.call("preview_restore_grid_transform")
	scene.call("preview_rotate_grid", -1)
	var expected_negative_basis: Basis = grid_root.basis
	scene.call("preview_restore_grid_transform")
	manual_controls._unhandled_key_input(_make_key_event(KEY_E, true, false, true))
	_expect_true(
		grid_root.basis.is_equal_approx(expected_negative_basis),
		"Shift+E should rotate GridRoot by negative 90 degrees."
	)

	scene.call("preview_restore_grid_transform")
	_expect_true(
		grid_root.basis.is_equal_approx(restored_basis),
		"GridRoot should restore after shortcut partition testing."
	)


func _test_rotation_input_actions(scene: Node, camera_rig: CAMERA_RIG_SCRIPT) -> void:
	var has_counterclockwise_action := InputMap.has_action(
		CAMERA_RIG_SCRIPT.ROTATE_COUNTERCLOCKWISE_ACTION
	)
	var has_clockwise_action := InputMap.has_action(
		CAMERA_RIG_SCRIPT.ROTATE_CLOCKWISE_ACTION
	)
	_expect_true(
		has_counterclockwise_action,
		"Counterclockwise camera action should exist in InputMap."
	)
	_expect_true(
		has_clockwise_action,
		"Clockwise camera action should exist in InputMap."
	)
	if not has_counterclockwise_action or not has_clockwise_action:
		return

	camera_rig.set_view_direction(CAMERA_RIG_SCRIPT.ViewDirection.SOUTHEAST, false)
	var emitted_directions: Array[int] = []
	camera_rig.view_direction_changed.connect(
		func(direction: int) -> void:
			emitted_directions.append(direction)
	)

	camera_rig._unhandled_input(_make_key_event(KEY_Q, true, false))
	_expect_equal(
		camera_rig.get_view_direction(),
		CAMERA_RIG_SCRIPT.ViewDirection.SOUTHWEST,
		"Q should trigger one clockwise camera rotation."
	)
	_expect_equal(emitted_directions.size(), 1, "Q should emit one direction change.")
	if emitted_directions.size() == 1:
		_expect_equal(
			emitted_directions[0],
			CAMERA_RIG_SCRIPT.ViewDirection.SOUTHWEST,
			"Q direction signal should contain the clockwise target."
		)

	camera_rig._unhandled_input(_make_key_event(KEY_Q, false, false))
	camera_rig._unhandled_input(_make_key_event(KEY_Q, true, true))
	camera_rig._unhandled_input(_make_key_event(KEY_Q, true, false, true))
	_expect_equal(
		camera_rig.get_view_direction(),
		CAMERA_RIG_SCRIPT.ViewDirection.SOUTHWEST,
		"Release, echo, and Shift+Q events should not add camera turns."
	)
	await create_timer(maxf(camera_rig.rotation_duration * 1.1, 0.32)).timeout

	var text_controls: Array[Control] = [
		LineEdit.new(),
		TextEdit.new(),
		CodeEdit.new(),
	]
	for text_control in text_controls:
		await _assert_text_focus_blocks_rotation(
			scene,
			camera_rig,
			text_control,
			emitted_directions
		)

	camera_rig._unhandled_input(_make_key_event(KEY_E, true, false))
	_expect_equal(
		camera_rig.get_view_direction(),
		CAMERA_RIG_SCRIPT.ViewDirection.SOUTHEAST,
		"E should rotate counterclockwise after text focus is released."
	)
	_expect_equal(emitted_directions.size(), 2, "E should emit one additional signal.")


func _assert_text_focus_blocks_rotation(
	scene: Node,
	camera_rig: CAMERA_RIG_SCRIPT,
	text_control: Control,
	emitted_directions: Array[int]
) -> void:
	text_control.focus_mode = Control.FOCUS_ALL
	scene.add_child(text_control)
	text_control.grab_focus()
	await process_frame
	_expect_true(
		text_control.has_focus(),
		"%s should receive GUI focus during the input test." % text_control.get_class()
	)
	var direction_before: int = camera_rig.get_view_direction()
	var signal_count_before: int = emitted_directions.size()
	camera_rig._unhandled_input(_make_key_event(KEY_Q, true, false))
	camera_rig._unhandled_input(_make_key_event(KEY_E, true, false))
	_expect_equal(
		camera_rig.get_view_direction(),
		direction_before,
		"Focused %s should block camera rotation." % text_control.get_class()
	)
	_expect_equal(
		emitted_directions.size(),
		signal_count_before,
		"Focused %s should not emit camera direction changes." % text_control.get_class()
	)
	text_control.release_focus()
	text_control.queue_free()
	await process_frame


func _make_key_event(
	keycode: Key,
	pressed: bool,
	echo: bool,
	shift_pressed: bool = false
) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	event.echo = echo
	event.shift_pressed = shift_pressed
	return event


func _finish() -> void:
	if failures == 0:
		print("Scene 01 camera rotation and mapping smoke tests passed.")
		quit(0)
		return
	push_error("Scene 01 camera rotation tests failed: %d failure(s)." % failures)
	quit(1)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	failures += 1
	push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])


func _expect_close(
	actual: float,
	expected: float,
	tolerance: float,
	message: String
) -> void:
	if absf(actual - expected) <= tolerance:
		return
	failures += 1
	push_error(
		"%s Expected %.3f ± %.3f, got %.3f." % [message, expected, tolerance, actual]
	)


func _expect_true(value: bool, message: String) -> void:
	if value:
		return
	failures += 1
	push_error(message)

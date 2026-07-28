extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const CAMERA_RIG := preload("res://scripts/camera/scene_01_camera_rig.gd")
const GRID_MODEL := preload("res://scripts/grid/grid_model.gd")
const CONTRACT := preload("res://tests/support/contract_test.gd")

var test := CONTRACT.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var resource := load(SCENE_PATH) as PackedScene
	test.expect_true(resource != null, "Scene 01 should load for camera framing tests.")
	if resource == null:
		test.finish(self, "Scene 01 camera framing contract tests")
		return
	var scene := resource.instantiate()
	root.add_child(scene)
	await process_frame
	var rig := scene.get_node_or_null("SceneRoot/CameraRoot/Scene01CameraRig") as CAMERA_RIG
	var grid_root := scene.get_node_or_null("SceneRoot/GridRoot") as Node3D
	var model := scene.get("grid_model") as GRID_MODEL
	test.expect_true(rig != null and grid_root != null and model != null, "Camera framing dependencies should exist.")
	if rig != null and grid_root != null and model != null:
		_test_projection_and_elevation(rig)
		await _test_viewport_framing(grid_root, model, rig)
		await _test_animated_orbit_geometry(rig)
	scene.queue_free()
	await process_frame
	test.finish(self, "Scene 01 camera framing contract tests")


func _test_projection_and_elevation(rig) -> void:
	test.expect_float_approx(rig.elevation_degrees, 30.0, "Configured elevation should be 30 degrees.")
	rig.set_view_direction(CAMERA_RIG.ViewDirection.SOUTHEAST, false)
	var camera: Camera3D = rig.get_camera()
	test.expect_true(camera != null, "Rig should expose SceneCamera.")
	if camera == null:
		return
	test.expect_equal(camera.projection, Camera3D.PROJECTION_ORTHOGONAL, "Scene camera should be orthographic.")
	test.expect_true(camera.current, "Scene camera should be current.")
	var horizontal := Vector2(camera.position.x, camera.position.z).length()
	test.expect_true(absf(rad_to_deg(atan2(camera.position.y, horizontal)) - 30.0) <= 0.1, "Rendered camera elevation should remain 30 degrees.")


func _test_viewport_framing(grid_root: Node3D, model, rig) -> void:
	var original_size := root.size
	var viewport_cases := [Vector2i(1152, 648), Vector2i(480, 900)]
	for viewport_size in viewport_cases:
		root.size = viewport_size
		await process_frame
		_configure_for_grid(grid_root, model, rig)
		await process_frame
		_expect_corners_visible(grid_root, model, rig.get_camera(), "viewport %s" % str(viewport_size))
	root.size = original_size
	await process_frame
	_configure_for_grid(grid_root, model, rig)
	await process_frame


func _test_animated_orbit_geometry(rig) -> void:
	rig.set_view_direction(CAMERA_RIG.ViewDirection.SOUTHEAST, false)
	var camera: Camera3D = rig.get_camera()
	if camera == null:
		return
	var start_position := camera.position
	var start_radius := Vector2(start_position.x, start_position.z).length()
	var start_size := camera.size
	var starts: Array[Vector2i] = []
	var finishes: Array[int] = []
	rig.view_transition_started.connect(func(from: int, to: int) -> void: starts.append(Vector2i(from, to)))
	rig.view_transition_finished.connect(func(direction: int) -> void: finishes.append(direction))
	rig.rotate_clockwise(true)
	test.expect_true(rig.is_transitioning(), "Animated rotation should start a transition.")
	test.expect_vector3_approx(camera.position, start_position, "Transition should begin at the rendered endpoint.")
	test.expect_float_approx(camera.size, start_size, "Transition start should preserve orthographic size.")
	await create_timer(maxf(rig.rotation_duration * 0.5, 0.05)).timeout
	var middle := camera.position
	var middle_radius := Vector2(middle.x, middle.z).length()
	var middle_elevation := rad_to_deg(atan2(middle.y, middle_radius))
	test.expect_false(middle.is_equal_approx(start_position), "Camera should move during the orbit.")
	test.expect_true(absf(middle_radius - start_radius) <= 0.01, "Orbit should preserve horizontal radius.")
	test.expect_true(absf(middle_elevation - 30.0) <= 0.1, "Orbit should preserve elevation.")
	test.expect_float_approx(camera.size, start_size, "Orbit should preserve orthographic size.")
	await create_timer(maxf(rig.rotation_duration * 0.65, 0.1)).timeout
	test.expect_false(rig.is_transitioning(), "Orbit should finish within its duration.")
	test.expect_equal(starts, [Vector2i(CAMERA_RIG.ViewDirection.SOUTHEAST, CAMERA_RIG.ViewDirection.SOUTHWEST)], "Transition start payload.")
	test.expect_equal(finishes, [CAMERA_RIG.ViewDirection.SOUTHWEST], "Transition finish payload.")
	test.expect_true(camera.position.x < 0.0 and camera.position.z > 0.0, "Clockwise orbit should finish in the southwest quadrant.")
	test.expect_float_approx(camera.size, start_size, "Finished orbit should preserve orthographic size.")


func _configure_for_grid(grid_root: Node3D, model, rig) -> void:
	var center_local := model.local_origin + Vector3(
		float(model.width) * model.cell_size * 0.5,
		0.0,
		float(model.height) * model.cell_size * 0.5
	)
	var scale := grid_root.global_basis.get_scale().abs()
	rig.configure_for_grid(
		grid_root.to_global(center_local),
		float(model.width) * model.cell_size * scale.x,
		float(model.height) * model.cell_size * scale.z
	)


func _expect_corners_visible(grid_root: Node3D, model, camera: Camera3D, context: String) -> void:
	test.expect_true(camera != null, "%s should expose a camera." % context)
	if camera == null:
		return
	var viewport_size := camera.get_viewport().get_visible_rect().size
	var minimum := model.local_origin
	var maximum := minimum + Vector3(float(model.width) * model.cell_size, 0.0, float(model.height) * model.cell_size)
	var corners := [
		grid_root.to_global(Vector3(minimum.x, minimum.y, minimum.z)),
		grid_root.to_global(Vector3(maximum.x, minimum.y, minimum.z)),
		grid_root.to_global(Vector3(minimum.x, minimum.y, maximum.z)),
		grid_root.to_global(Vector3(maximum.x, minimum.y, maximum.z)),
	]
	for corner in corners:
		var screen := camera.unproject_position(corner)
		test.expect_true(
			screen.x >= 0.0 and screen.y >= 0.0 and screen.x <= viewport_size.x and screen.y <= viewport_size.y,
			"%s should keep corner %s visible." % [context, str(corner)]
		)

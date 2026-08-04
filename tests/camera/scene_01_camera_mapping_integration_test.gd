extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const CAMERA_RIG := preload("res://scripts/camera/scene_01_camera_rig.gd")
const GRID_SELECTION := preload("res://scripts/input/grid_selection_controller.gd")
const CONTRACT := preload("res://tests/support/contract_test.gd")

var test := CONTRACT.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var resource := load(SCENE_PATH) as PackedScene
	test.expect_true(resource != null, "Scene 01 should load for camera mapping tests.")
	if resource == null:
		test.finish(self, "Scene 01 camera mapping integration tests")
		return
	var scene := resource.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	var rig := scene.get_node_or_null("SceneRoot/CameraRoot/Scene01CameraRig") as CAMERA_RIG
	var selection := scene.get_node_or_null("SceneRoot/GridRoot/GridSelectionController") as GRID_SELECTION
	test.expect_true(rig != null and selection != null, "Camera mapping dependencies should exist.")
	if rig != null and selection != null:
		await _test_fixed_direction_matrix(scene, rig, selection)
		await _test_mapping_during_animation(scene, rig, selection)
	scene.queue_free()
	await process_frame
	test.finish(self, "Scene 01 camera mapping integration tests")


func _test_fixed_direction_matrix(scene: Node, rig, selection) -> void:
	var cells := [Vector2i(1, 1), Vector2i(5, 3), Vector2i(10, 6)]
	var cases: Array[Dictionary] = [
		{"direction": CAMERA_RIG.ViewDirection.SOUTHEAST, "signs": Vector2(1.0, 1.0)},
		{"direction": CAMERA_RIG.ViewDirection.SOUTHWEST, "signs": Vector2(-1.0, 1.0)},
		{"direction": CAMERA_RIG.ViewDirection.NORTHWEST, "signs": Vector2(-1.0, -1.0)},
		{"direction": CAMERA_RIG.ViewDirection.NORTHEAST, "signs": Vector2(1.0, -1.0)},
	]
	for case in cases:
		test.expect_true(rig.set_view_direction(case["direction"], false), "Fixed direction should be accepted.")
		await process_frame
		await physics_frame
		var camera: Camera3D = rig.get_camera()
		test.expect_true(camera != null, "Fixed direction should expose a camera.")
		if camera == null:
			continue
		var signs: Vector2 = case["signs"]
		test.expect_true(signf(camera.position.x) == signs.x and signf(camera.position.z) == signs.y, "Camera quadrant should match direction.")
		for cell in cells:
			_expect_screen_cell(scene, camera, selection, cell, "direction %d" % case["direction"])


func _test_mapping_during_animation(scene: Node, rig, selection) -> void:
	rig.set_view_direction(CAMERA_RIG.ViewDirection.SOUTHEAST, false)
	rig.rotate_clockwise(true)
	await create_timer(maxf(rig.rotation_duration * 0.5, 0.05)).timeout
	test.expect_true(rig.is_transitioning(), "Mapping animation case should sample an active transition.")
	var camera: Camera3D = rig.get_camera()
	for cell in [Vector2i(2, 2), Vector2i(8, 5)]:
		_expect_screen_cell(scene, camera, selection, cell, "mid-transition")
	await create_timer(maxf(rig.rotation_duration * 0.65, 0.1)).timeout


func _expect_screen_cell(scene: Node, camera: Camera3D, selection, cell: Vector2i, context: String) -> void:
	var world_position: Vector3 = scene.call("grid_cell_to_world", cell)
	var screen_position := camera.unproject_position(world_position)
	selection.cancel_selection()
	test.expect_true(selection.select_from_screen_position(screen_position), "%s should raycast cell %s." % [context, str(cell)])
	test.expect_equal(selection.selected_cell, cell, "%s should preserve logical cell %s." % [context, str(cell)])

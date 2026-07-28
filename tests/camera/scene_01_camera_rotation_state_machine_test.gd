extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const CAMERA_RIG := preload("res://scripts/camera/scene_01_camera_rig.gd")
const CONTRACT := preload("res://tests/support/contract_test.gd")

var test := CONTRACT.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := (load(SCENE_PATH) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var rig := scene.get_node_or_null("SceneRoot/CameraRoot/Scene01CameraRig") as CAMERA_RIG
	test.expect_true(rig != null, "Camera rig should exist.")
	if rig != null:
		_test_fixed_rotation_cycle(rig)
		await _test_immediate_opposite_cancels(rig)
		await _test_repeated_same_direction_coalesces(rig)
		await _test_last_opposite_command_retargets(rig)
	scene.queue_free()
	await process_frame
	test.finish(self, "Scene 01 camera rotation state machine tests")


func _test_fixed_rotation_cycle(rig) -> void:
	rig.set_view_direction(CAMERA_RIG.ViewDirection.SOUTHEAST, false)
	rig.rotate_counterclockwise(false)
	test.expect_equal(rig.get_view_direction(), CAMERA_RIG.ViewDirection.NORTHEAST, "Counterclockwise rotation should wrap northeast.")
	rig.rotate_clockwise(false)
	test.expect_equal(rig.get_view_direction(), CAMERA_RIG.ViewDirection.SOUTHEAST, "Clockwise rotation should return southeast.")
	for _step in range(4):
		rig.rotate_clockwise(false)
	test.expect_equal(rig.get_view_direction(), CAMERA_RIG.ViewDirection.SOUTHEAST, "Four quarter turns should complete one cycle.")


func _test_immediate_opposite_cancels(rig) -> void:
	rig.set_view_direction(CAMERA_RIG.ViewDirection.SOUTHEAST, false)
	var camera: Camera3D = rig.get_camera()
	var start_position := camera.position
	rig.rotate_clockwise(true)
	rig.rotate_counterclockwise(true)
	test.expect_equal(rig.get_view_direction(), CAMERA_RIG.ViewDirection.SOUTHEAST, "Immediate opposite input should keep the logical start direction.")
	test.expect_false(rig.is_transitioning(), "Immediate opposite input at the endpoint should cancel the transition.")
	test.expect_vector3_approx(camera.position, start_position, "Immediate opposite input should preserve the rendered endpoint.")


func _test_repeated_same_direction_coalesces(rig) -> void:
	rig.set_view_direction(CAMERA_RIG.ViewDirection.SOUTHEAST, false)
	rig.rotate_clockwise(true)
	await create_timer(maxf(rig.rotation_duration * 0.2, 0.04)).timeout
	rig.rotate_clockwise(true)
	rig.rotate_clockwise(true)
	test.expect_equal(rig.get_view_direction(), CAMERA_RIG.ViewDirection.SOUTHWEST, "Repeated clockwise input should retain one adjacent target.")
	await create_timer(maxf(rig.rotation_duration, 0.3)).timeout
	test.expect_false(rig.is_transitioning(), "Coalesced input should finish after one quarter turn.")
	test.expect_equal(rig.get_view_direction(), CAMERA_RIG.ViewDirection.SOUTHWEST, "QQQ should produce one quarter turn.")


func _test_last_opposite_command_retargets(rig) -> void:
	rig.set_view_direction(CAMERA_RIG.ViewDirection.SOUTHEAST, false)
	var camera: Camera3D = rig.get_camera()
	var start_position := camera.position
	rig.rotate_clockwise(true)
	await create_timer(maxf(rig.rotation_duration * 0.45, 0.08)).timeout
	test.expect_false(camera.position.is_equal_approx(start_position), "Transition should be underway before reversal.")
	rig.rotate_clockwise(true)
	rig.rotate_counterclockwise(true)
	test.expect_equal(rig.get_view_direction(), CAMERA_RIG.ViewDirection.SOUTHEAST, "Last opposite command should retarget the origin.")
	await create_timer(maxf(rig.rotation_duration, 0.3)).timeout
	test.expect_false(rig.is_transitioning(), "Retargeted transition should settle without queued turns.")
	test.expect_equal(rig.get_view_direction(), CAMERA_RIG.ViewDirection.SOUTHEAST, "QQE should return to the origin direction.")
	test.expect_vector3_approx(camera.position, start_position, "QQE should return to the rendered start endpoint.")

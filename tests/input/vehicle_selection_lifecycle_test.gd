extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const VEHICLE_SELECTION := preload("res://scripts/input/vehicle_selection_controller.gd")
const VEHICLE_MANAGER := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const VEHICLE_ACTOR := preload("res://scripts/vehicles/vehicle_actor.gd")
const CAMERA_RIG := preload("res://scripts/camera/scene_01_camera_rig.gd")
const CONTRACT := preload("res://tests/support/contract_test.gd")

var test := CONTRACT.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	test.expect_true(packed_scene != null, "Scene 01 should load for vehicle selection tests.")
	if packed_scene == null:
		test.finish(self, "Vehicle selection lifecycle tests")
		return
	var scene := packed_scene.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame

	var selection := scene.get_node_or_null(
		"SceneRoot/GridRoot/VehicleSelectionController"
	) as VEHICLE_SELECTION
	var manager := scene.get_node_or_null(
		"SceneRoot/RobotRoot/Scene01VehicleManager"
	) as VEHICLE_MANAGER
	var camera_rig := scene.get_node_or_null(
		"SceneRoot/CameraRoot/Scene01CameraRig"
	) as CAMERA_RIG
	test.expect_true(selection != null and manager != null and camera_rig != null, "Selection test dependencies should exist.")
	if selection != null and manager != null and camera_rig != null:
		await _test_selection_contract(scene, selection, manager, camera_rig)

	scene.queue_free()
	await process_frame
	test.finish(self, "Vehicle selection lifecycle tests")


func _test_selection_contract(scene: Node, selection, manager, camera_rig) -> void:
	var arm = manager.get_vehicle_by_id(VEHICLE_MANAGER.ARM_VEHICLE_ID)
	var transport = manager.get_vehicle_by_id(VEHICLE_MANAGER.TRANSPORT_VEHICLE_ID)
	test.expect_true(arm != null and transport != null, "Both managed vehicles should exist.")
	if arm == null or transport == null:
		return

	var emitted: Array[Dictionary] = []
	selection.selection_changed.connect(
		func(vehicle_id: StringName, has_selection: bool) -> void:
			emitted.append({"vehicle_id": vehicle_id, "has_selection": has_selection})
	)
	var unmanaged := VEHICLE_ACTOR.new()
	unmanaged.vehicle_preset_id = &"unmanaged"
	test.expect_false(selection.select_vehicle(unmanaged), "Unmanaged Actors should be rejected.")
	unmanaged.free()

	test.expect_true(selection.select_vehicle(arm), "Managed arm should be selectable.")
	_expect_selected(selection, VEHICLE_MANAGER.ARM_VEHICLE_ID, "arm selection")
	test.expect_true(selection.select_vehicle(arm), "Selecting the same Actor should be idempotent.")
	test.expect_equal(emitted.size(), 1, "Idempotent selection should not emit a duplicate change.")

	test.expect_true(selection.select_vehicle(transport), "Selecting another managed Actor should switch selection.")
	_expect_selected(selection, VEHICLE_MANAGER.TRANSPORT_VEHICLE_ID, "transport selection")
	test.expect_equal(emitted.size(), 2, "Switching selection should emit exactly one change.")

	selection.cancel_selection()
	_expect_cleared(selection, "explicit cancel")
	test.expect_equal(emitted.back(), {"vehicle_id": &"", "has_selection": false}, "Cancel should emit a cleared selection.")

	var directions := [
		CAMERA_RIG.ViewDirection.SOUTHEAST,
		CAMERA_RIG.ViewDirection.SOUTHWEST,
		CAMERA_RIG.ViewDirection.NORTHWEST,
		CAMERA_RIG.ViewDirection.NORTHEAST,
	]
	for direction in directions:
		camera_rig.set_view_direction(direction, false)
		await process_frame
		await physics_frame
		selection.cancel_selection()
		var screen_position: Vector2 = camera_rig.get_camera().unproject_position(
			arm.global_position + arm.global_basis.y.normalized() * arm.cell_size * 0.25
		)
		test.expect_true(
			selection.select_from_screen_position(screen_position),
			"Camera direction %d should raycast the arm." % direction
		)
		_expect_selected(selection, VEHICLE_MANAGER.ARM_VEHICLE_ID, "camera direction %d" % direction)

	var empty_world: Vector3 = scene.call("grid_cell_to_world", Vector2i(5, 5))
	var empty_screen: Vector2 = camera_rig.get_camera().unproject_position(empty_world)
	test.expect_false(selection.select_from_screen_position(empty_screen), "Ground-only raycasts should not select a vehicle.")
	_expect_selected(selection, VEHICLE_MANAGER.ARM_VEHICLE_ID, "ground click preserves selection")

	scene.call("reset_scene")
	_expect_cleared(selection, "scene reset")

	test.expect_true(selection.select_vehicle(arm), "Arm should be selectable before Actor replacement.")
	var old_arm_id: int = arm.get_instance_id()
	test.expect_true(bool(scene.call("initialize_grid")), "Grid rebuild should succeed.")
	await process_frame
	await physics_frame
	_expect_cleared(selection, "Actor replacement")
	var replacement_arm = manager.get_vehicle_by_id(VEHICLE_MANAGER.ARM_VEHICLE_ID)
	test.expect_true(replacement_arm != null, "Grid rebuild should expose a replacement arm Actor.")
	if replacement_arm != null:
		test.expect_true(replacement_arm.get_instance_id() != old_arm_id, "Grid rebuild should replace the old Actor instance.")
		test.expect_true(selection.select_vehicle(replacement_arm), "Replacement Actor should be selectable.")
		_expect_selected(selection, VEHICLE_MANAGER.ARM_VEHICLE_ID, "replacement Actor")


func _expect_selected(selection, expected_id: StringName, context: String) -> void:
	test.expect_true(selection.has_selected_vehicle(), "%s should have a selected vehicle." % context)
	test.expect_equal(selection.get_selected_vehicle_id(), expected_id, "%s should expose the selected id." % context)
	test.expect_true(selection.is_selection_highlight_visible(), "%s should show the selection highlight." % context)


func _expect_cleared(selection, context: String) -> void:
	test.expect_false(selection.has_selected_vehicle(), "%s should clear the selected vehicle." % context)
	test.expect_equal(selection.get_selected_vehicle_id(), &"", "%s should clear the selected id." % context)
	test.expect_false(selection.is_selection_highlight_visible(), "%s should hide the selection highlight." % context)
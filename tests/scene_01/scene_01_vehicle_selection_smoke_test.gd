extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const VEHICLE_SELECTION_SCRIPT := preload("res://scripts/input/vehicle_selection_controller.gd")
const VEHICLE_MANAGER_SCRIPT := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const CAMERA_RIG_SCRIPT := preload("res://scripts/camera/scene_01_camera_rig.gd")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	_expect_true(packed_scene != null, "Scene 01 should load for vehicle selection tests.")
	if packed_scene == null:
		_finish()
		return

	var scene := packed_scene.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame

	var selection := scene.get_node_or_null(
		"SceneRoot/GridRoot/VehicleSelectionController"
	) as VEHICLE_SELECTION_SCRIPT
	var manager := scene.get_node_or_null(
		"SceneRoot/RobotRoot/Scene01VehicleManager"
	) as VEHICLE_MANAGER_SCRIPT
	var camera_rig := scene.get_node_or_null(
		"SceneRoot/CameraRoot/Scene01CameraRig"
	) as CAMERA_RIG_SCRIPT
	_expect_true(selection != null, "Scene 01 should contain a vehicle selection controller.")
	_expect_true(manager != null, "Scene 01 should contain its vehicle manager.")
	_expect_true(camera_rig != null, "Scene 01 should contain its camera rig.")

	if selection != null and manager != null and camera_rig != null:
		await _test_selection_flow(scene, selection, manager, camera_rig)

	scene.queue_free()
	await process_frame
	_finish()


func _test_selection_flow(
	scene: Node,
	selection: VEHICLE_SELECTION_SCRIPT,
	manager: VEHICLE_MANAGER_SCRIPT,
	camera_rig: CAMERA_RIG_SCRIPT
) -> void:
	var arm = manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.ARM_VEHICLE_ID)
	var transport = manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.TRANSPORT_VEHICLE_ID)
	_expect_true(arm != null, "Arm vehicle should exist for selection.")
	_expect_true(transport != null, "Transport vehicle should exist for selection.")
	if arm == null or transport == null:
		return

	var emitted: Array[Dictionary] = []
	selection.selection_changed.connect(
		func(vehicle_id: StringName, has_selection: bool) -> void:
			emitted.append({"vehicle_id": vehicle_id, "has_selection": has_selection})
	)

	_expect_true(selection.select_vehicle(arm), "Direct selection should accept a managed vehicle.")
	_expect_equal(
		selection.get_selected_vehicle_id(),
		VEHICLE_MANAGER_SCRIPT.ARM_VEHICLE_ID,
		"Direct selection should expose the selected arm vehicle id."
	)
	_expect_true(selection.is_selection_highlight_visible(), "Selected vehicle should show a highlight.")

	_expect_true(selection.select_vehicle(transport), "Selecting another vehicle should replace the selection.")
	_expect_equal(
		selection.get_selected_vehicle_id(),
		VEHICLE_MANAGER_SCRIPT.TRANSPORT_VEHICLE_ID,
		"Selection should switch to the transport vehicle."
	)
	_expect_equal(emitted.size(), 2, "Selecting two different vehicles should emit two changes.")

	selection.cancel_selection()
	_expect_true(not selection.has_selected_vehicle(), "Cancel should clear the selected vehicle.")
	_expect_true(not selection.is_selection_highlight_visible(), "Cancel should hide the selection highlight.")
	_expect_equal(emitted.size(), 3, "Cancel should emit one cleared selection event.")

	var directions := [
		CAMERA_RIG_SCRIPT.ViewDirection.SOUTHEAST,
		CAMERA_RIG_SCRIPT.ViewDirection.SOUTHWEST,
		CAMERA_RIG_SCRIPT.ViewDirection.NORTHWEST,
		CAMERA_RIG_SCRIPT.ViewDirection.NORTHEAST,
	]
	for direction in directions:
		camera_rig.set_view_direction(direction)
		await process_frame
		await physics_frame
		var screen_position := camera_rig.get_camera().unproject_position(
			arm.global_position + Vector3.UP * arm.cell_size * 0.15
		)
		selection.cancel_selection()
		_expect_true(
			selection.select_from_screen_position(screen_position),
			"Vehicle ray selection should hit the arm vehicle in direction %d." % direction
		)
		_expect_equal(
			selection.get_selected_vehicle_id(),
			VEHICLE_MANAGER_SCRIPT.ARM_VEHICLE_ID,
			"All camera directions should select the same logical vehicle."
		)

	var empty_cell_world: Vector3 = scene.call("grid_cell_to_world", Vector2i(5, 5))
	var empty_screen := camera_rig.get_camera().unproject_position(empty_cell_world)
	_expect_true(
		not selection.select_from_screen_position(empty_screen),
		"A ground-only click should not be treated as a vehicle hit."
	)
	_expect_equal(
		selection.get_selected_vehicle_id(),
		VEHICLE_MANAGER_SCRIPT.ARM_VEHICLE_ID,
		"Clicking a target grid cell should preserve the selected vehicle."
	)

	scene.call("reset_scene")
	_expect_true(not selection.has_selected_vehicle(), "Scene reset should clear vehicle selection.")

	_expect_true(selection.select_vehicle(arm), "Arm should be selectable before grid rebuild.")
	_expect_true(bool(scene.call("initialize_grid")), "Grid rebuild should succeed.")
	await process_frame
	await physics_frame
	_expect_true(not selection.has_selected_vehicle(), "Successful grid rebuild should clear stale vehicle selection.")
	var replacement_arm = manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.ARM_VEHICLE_ID)
	_expect_true(replacement_arm != null and replacement_arm != arm, "Grid rebuild should replace the arm Actor.")
	_expect_true(selection.select_vehicle(replacement_arm), "Replacement vehicle should remain selectable.")


func _finish() -> void:
	if failures == 0:
		print("Scene 01 vehicle selection smoke tests passed.")
		quit(0)
		return
	push_error("Scene 01 vehicle selection tests failed: %d failure(s)." % failures)
	quit(1)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	failures += 1
	push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])


func _expect_true(value: bool, message: String) -> void:
	if value:
		return
	failures += 1
	push_error(message)

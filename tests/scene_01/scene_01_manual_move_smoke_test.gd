extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const VEHICLE_SELECTION_SCRIPT := preload("res://scripts/input/vehicle_selection_controller.gd")
const VEHICLE_MOVE_SCRIPT := preload("res://scripts/input/vehicle_move_controller.gd")
const GRID_SELECTION_SCRIPT := preload("res://scripts/input/grid_selection_controller.gd")
const VEHICLE_MANAGER_SCRIPT := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const VEHICLE_RUNTIME_STATE_SCRIPT := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const CAMERA_RIG_SCRIPT := preload("res://scripts/camera/scene_01_camera_rig.gd")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	_expect_true(packed_scene != null, "Scene 01 should load for manual MoveTo tests.")
	if packed_scene == null:
		_finish()
		return

	var scene := packed_scene.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame

	var vehicle_selection := scene.get_node_or_null(
		"SceneRoot/GridRoot/VehicleSelectionController"
	) as VEHICLE_SELECTION_SCRIPT
	var move_controller := scene.get_node_or_null(
		"SceneRoot/GridRoot/VehicleMoveController"
	) as VEHICLE_MOVE_SCRIPT
	var grid_selection := scene.get_node_or_null(
		"SceneRoot/GridRoot/GridSelectionController"
	) as GRID_SELECTION_SCRIPT
	var manager := scene.get_node_or_null(
		"SceneRoot/RobotRoot/Scene01VehicleManager"
	) as VEHICLE_MANAGER_SCRIPT
	var camera_rig := scene.get_node_or_null(
		"SceneRoot/CameraRoot/Scene01CameraRig"
	) as CAMERA_RIG_SCRIPT

	_expect_true(vehicle_selection != null, "VehicleSelectionController should exist.")
	_expect_true(move_controller != null, "VehicleMoveController should exist.")
	_expect_true(grid_selection != null, "GridSelectionController should exist.")
	_expect_true(manager != null, "VehicleManager should exist.")
	_expect_true(camera_rig != null, "Camera rig should exist.")

	if (
		vehicle_selection != null
		and move_controller != null
		and grid_selection != null
		and manager != null
		and camera_rig != null
	):
		await _test_manual_move_chain(
			scene,
			vehicle_selection,
			move_controller,
			grid_selection,
			manager,
			camera_rig
		)

	scene.queue_free()
	await process_frame
	_finish()


func _test_manual_move_chain(
	scene: Node,
	vehicle_selection: VEHICLE_SELECTION_SCRIPT,
	move_controller: VEHICLE_MOVE_SCRIPT,
	grid_selection: GRID_SELECTION_SCRIPT,
	manager: VEHICLE_MANAGER_SCRIPT,
	camera_rig: CAMERA_RIG_SCRIPT
) -> void:
	var arm = manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.ARM_VEHICLE_ID)
	var transport = manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.TRANSPORT_VEHICLE_ID)
	_expect_true(arm != null and transport != null, "Both preset vehicles should exist.")
	if arm == null or transport == null:
		return

	var accepted: Array[Dictionary] = []
	var rejected: Array[Dictionary] = []
	move_controller.move_accepted.connect(
		func(vehicle_id: StringName, target: Vector2i) -> void:
			accepted.append({"vehicle_id": vehicle_id, "target": target})
	)
	move_controller.move_rejected.connect(
		func(vehicle_id: StringName, target: Vector2i, reason: StringName) -> void:
			rejected.append({"vehicle_id": vehicle_id, "target": target, "reason": reason})
	)

	camera_rig.set_view_direction(CAMERA_RIG_SCRIPT.ViewDirection.NORTHWEST, false)
	await process_frame
	await physics_frame
	var arm_screen := camera_rig.get_camera().unproject_position(
		arm.global_position + arm.global_basis.y.normalized() * arm.cell_size * 0.25
	)
	_expect_true(
		vehicle_selection.select_from_screen_position(arm_screen),
		"Camera ray should select the arm vehicle."
	)

	var target := Vector2i(5, 2)
	var target_screen := camera_rig.get_camera().unproject_position(
		scene.call("grid_cell_to_world", target)
	)
	_expect_true(
		grid_selection.select_from_screen_position(target_screen),
		"Camera ray should select the MoveTo target anchor."
	)
	_expect_true(move_controller.is_target_preview_visible(), "Selected target should show a footprint preview.")
	_expect_true(move_controller.is_target_preview_valid(), "Reachable target preview should be valid.")
	_expect_true(grid_selection.confirm_selection(), "Enter-equivalent confirmation should emit selection_confirmed.")
	_expect_equal(accepted.size(), 1, "Valid MoveTo should be accepted once.")
	_expect_equal(arm.runtime_state.motion_state, VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.MOVING, "Accepted command should start moving.")
	_expect_true(arm.runtime_state.active_move_command != null, "Accepted command should be stored by runtime state.")
	_expect_true(not grid_selection.has_selected_cell(), "Accepted command should clear the ground target.")
	_expect_true(not move_controller.is_target_preview_visible(), "Accepted command should hide target preview.")

	arm.advance_move(0.2)
	var progress_before_transform := arm.get_segment_progress()
	scene.call("preview_rotate_grid", 1)
	_expect_float_approx(
		arm.get_segment_progress(),
		progress_before_transform,
		"GridRoot rotation should preserve logical movement progress."
	)
	var active_command = arm.runtime_state.active_move_command
	var expected_position: Vector3 = scene.call(
		"grid_footprint_center_to_world",
		active_command.get_current_anchor(),
		arm.definition.footprint
	).lerp(
		scene.call(
			"grid_footprint_center_to_world",
			active_command.get_next_anchor(),
			arm.definition.footprint
		),
		progress_before_transform
	)
	_expect_vector3_approx(
		arm.global_position,
		expected_position,
		"Moving Actor should remain on the transformed logical segment."
	)

	var safety_steps := 0
	while (
		arm.runtime_state.motion_state == VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.MOVING
		and safety_steps < 100
	):
		arm.advance_move(0.1)
		safety_steps += 1
	_expect_true(safety_steps < 100, "MoveTo execution should terminate.")
	_expect_equal(arm.runtime_state.anchor_cell, target, "Vehicle should reach the confirmed target anchor.")
	_expect_equal(arm.runtime_state.motion_state, VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.WAITING, "Arrival should restore Waiting.")

	var blocked_target: Vector2i = transport.runtime_state.anchor_cell
	_expect_true(
		grid_selection.select_from_world_position(scene.call("grid_cell_to_world", blocked_target)),
		"Occupied target anchor should still be selectable as ground."
	)
	_expect_true(move_controller.is_target_preview_visible(), "Occupied target should show a preview.")
	_expect_true(not move_controller.is_target_preview_valid(), "Other vehicle occupancy should invalidate the preview.")
	_expect_true(grid_selection.confirm_selection(), "Ground confirmation should reach MoveTo validation.")
	_expect_equal(rejected.size(), 1, "Occupied target should emit one rejection.")
	_expect_equal(
		move_controller.get_last_rejection_reason(),
		VEHICLE_MOVE_SCRIPT.REJECTION_NO_PATH,
		"Occupied target should be rejected as no_path."
	)
	_expect_equal(arm.runtime_state.motion_state, VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.BLOCKED, "Rejected planning should enter Blocked.")
	_expect_true(grid_selection.has_selected_cell(), "Rejected target should remain selected for correction.")

	scene.call("reset_scene")
	_expect_equal(arm.runtime_state.anchor_cell, Vector2i(2, 2), "Reset should restore arm start anchor.")
	_expect_equal(arm.runtime_state.motion_state, VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.WAITING, "Reset should restore Waiting.")
	_expect_true(not vehicle_selection.has_selected_vehicle(), "Reset should clear vehicle selection.")
	_expect_true(not grid_selection.has_selected_cell(), "Reset should clear ground selection.")
	_expect_true(not move_controller.is_target_preview_visible(), "Reset should hide target preview.")

	_expect_true(
		grid_selection.select_from_world_position(scene.call("grid_cell_to_world", Vector2i(4, 2))),
		"A target can be selected without a vehicle."
	)
	_expect_true(grid_selection.confirm_selection(), "Ground confirmation should still emit without a vehicle.")
	_expect_equal(
		move_controller.get_last_rejection_reason(),
		VEHICLE_MOVE_SCRIPT.REJECTION_NO_VEHICLE,
		"Missing vehicle selection should be rejected explicitly."
	)

	grid_selection.cancel_selection()
	_expect_true(vehicle_selection.select_vehicle(arm), "Arm should be selectable for a no-op target.")
	_expect_true(
		grid_selection.select_from_world_position(scene.call("grid_cell_to_world", arm.runtime_state.anchor_cell)),
		"Current anchor should be selectable."
	)
	_expect_true(move_controller.is_target_preview_valid(), "Current anchor should be a valid no-op target.")
	_expect_true(grid_selection.confirm_selection(), "No-op MoveTo should be accepted.")
	_expect_equal(arm.runtime_state.motion_state, VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.WAITING, "No-op MoveTo should remain Waiting.")
	_expect_true(arm.runtime_state.active_move_command == null, "No-op MoveTo should not retain a command.")


func _finish() -> void:
	if failures == 0:
		print("Scene 01 manual MoveTo smoke tests passed.")
		quit(0)
		return
	push_error("Scene 01 manual MoveTo tests failed: %d failure(s)." % failures)
	quit(1)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	failures += 1
	push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])


func _expect_float_approx(actual: float, expected: float, message: String) -> void:
	if is_equal_approx(actual, expected):
		return
	failures += 1
	push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])


func _expect_vector3_approx(actual: Vector3, expected: Vector3, message: String) -> void:
	if actual.is_equal_approx(expected):
		return
	failures += 1
	push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])


func _expect_true(value: bool, message: String) -> void:
	if value:
		return
	failures += 1
	push_error(message)

extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const VEHICLE_SELECTION := preload("res://scripts/input/vehicle_selection_controller.gd")
const VEHICLE_MOVE := preload("res://scripts/input/vehicle_move_controller.gd")
const GRID_SELECTION := preload("res://scripts/input/grid_selection_controller.gd")
const VEHICLE_MANAGER := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const RUNTIME := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const CAMERA_RIG := preload("res://scripts/camera/scene_01_camera_rig.gd")
const CONTRACT := preload("res://tests/support/contract_test.gd")

var test := CONTRACT.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	test.expect_true(packed_scene != null, "Scene 01 should load for manual move integration tests.")
	if packed_scene == null:
		test.finish(self, "Scene 01 manual move integration tests")
		return
	var scene := packed_scene.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame

	var vehicle_selection := scene.get_node_or_null(
		"SceneRoot/GridRoot/VehicleSelectionController"
	) as VEHICLE_SELECTION
	var move_controller := scene.get_node_or_null(
		"SceneRoot/GridRoot/VehicleMoveController"
	) as VEHICLE_MOVE
	var grid_selection := scene.get_node_or_null(
		"SceneRoot/GridRoot/GridSelectionController"
	) as GRID_SELECTION
	var manager := scene.get_node_or_null(
		"SceneRoot/RobotRoot/Scene01VehicleManager"
	) as VEHICLE_MANAGER
	var camera_rig := scene.get_node_or_null(
		"SceneRoot/CameraRoot/Scene01CameraRig"
	) as CAMERA_RIG
	test.expect_true(
		vehicle_selection != null and move_controller != null and grid_selection != null and manager != null and camera_rig != null,
		"Manual move integration dependencies should exist."
	)
	if vehicle_selection != null and move_controller != null and grid_selection != null and manager != null and camera_rig != null:
		await _test_2x2_screen_mapping_matrix(
			scene,
			vehicle_selection,
			move_controller,
			grid_selection,
			manager,
			camera_rig
		)
		await _test_user_flow(scene, vehicle_selection, move_controller, grid_selection, manager, camera_rig)

	scene.queue_free()
	await process_frame
	test.finish(self, "Scene 01 manual move integration tests")


func _test_2x2_screen_mapping_matrix(
	scene: Node,
	vehicle_selection,
	move_controller,
	grid_selection,
	manager,
	camera_rig
) -> void:
	var arm = manager.get_vehicle_by_id(VEHICLE_MANAGER.ARM_VEHICLE_ID)
	test.expect_true(arm != null, "2x2 mapping should expose the arm vehicle.")
	if arm == null:
		return
	test.expect_true(vehicle_selection.select_vehicle(arm), "2x2 mapping should select the arm.")
	test.expect_equal(grid_selection.get_target_footprint(), Vector2i(2, 2), "Selected arm should configure 2x2 snapping.")

	var targets: Array[Vector2i] = [Vector2i(5, 2), Vector2i(5, 4)]
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
		for target in targets:
			_expect_2x2_screen_target(
				scene,
				camera_rig.get_camera(),
				grid_selection,
				move_controller,
				target,
				"fixed direction %d" % direction
			)

	var original_duration: float = camera_rig.rotation_duration
	camera_rig.rotation_duration = 1.0
	camera_rig.set_view_direction(CAMERA_RIG.ViewDirection.SOUTHEAST, false)
	camera_rig.rotate_clockwise(true)
	await create_timer(0.2).timeout
	test.expect_true(camera_rig.is_transitioning(), "2x2 mapping should sample an active camera transition.")
	for target in targets:
		_expect_2x2_screen_target(
			scene,
			camera_rig.get_camera(),
			grid_selection,
			move_controller,
			target,
			"mid-transition"
		)
	camera_rig.set_view_direction(CAMERA_RIG.ViewDirection.SOUTHWEST, false)
	camera_rig.rotation_duration = original_duration
	grid_selection.cancel_selection()
	vehicle_selection.cancel_selection()


func _expect_2x2_screen_target(
	scene: Node,
	camera: Camera3D,
	grid_selection,
	move_controller,
	target: Vector2i,
	context: String
) -> void:
	test.expect_true(camera != null, "%s should expose a camera." % context)
	if camera == null:
		return
	var world_center: Vector3 = scene.call("grid_footprint_center_to_world", target, Vector2i(2, 2))
	var screen_position: Vector2 = camera.unproject_position(world_center)
	test.expect_true(
		grid_selection.update_hover_from_screen_position(screen_position),
		"%s should raycast target %s." % [context, str(target)]
	)
	test.expect_equal(
		grid_selection.selected_cell,
		target,
		"%s should preserve the nearest 2x2 intersection anchor." % context
	)
	var path: Array[Vector2i] = move_controller.get_preview_path()
	test.expect_false(path.is_empty(), "%s should expose a preview path." % context)
	if not path.is_empty():
		test.expect_equal(path.back(), target, "%s preview should end at the mapped anchor." % context)


func _test_user_flow(scene: Node, vehicle_selection, move_controller, grid_selection, manager, camera_rig) -> void:
	var arm = manager.get_vehicle_by_id(VEHICLE_MANAGER.ARM_VEHICLE_ID)
	test.expect_true(arm != null, "Arm vehicle should exist.")
	if arm == null:
		return

	camera_rig.set_view_direction(CAMERA_RIG.ViewDirection.NORTHWEST, false)
	await process_frame
	await physics_frame
	var arm_screen: Vector2 = camera_rig.get_camera().unproject_position(
		arm.global_position + arm.global_basis.y.normalized() * arm.cell_size * 0.25
	)
	test.expect_true(vehicle_selection.select_from_screen_position(arm_screen), "Screen ray should select the arm.")

	var target := Vector2i(5, 2)
	var target_world: Vector3 = scene.call("grid_footprint_center_to_world", target, arm.definition.footprint)
	var target_screen: Vector2 = camera_rig.get_camera().unproject_position(target_world)
	test.expect_true(grid_selection.update_hover_from_screen_position(target_screen), "Screen hover should update the MoveTo target.")
	test.expect_equal(grid_selection.selected_cell, target, "Hover should resolve the expected 2x2 anchor.")
	test.expect_true(move_controller.is_target_preview_valid(), "Reachable hover should show a valid target.")
	test.expect_true(move_controller.is_path_preview_visible(), "Reachable hover should show a path.")
	test.expect_true(grid_selection.confirm_selection(), "Enter-equivalent confirmation should submit MoveTo.")
	test.expect_equal(arm.runtime_state.motion_state, RUNTIME.MotionState.MOVING, "Accepted MoveTo should enter Moving.")

	arm.advance_move(0.2)
	var progress_before_transform: float = arm.get_segment_progress()
	scene.call("preview_rotate_grid", 1)
	test.expect_float_approx(arm.get_segment_progress(), progress_before_transform, "Grid rotation should preserve logical progress.")
	var active_command = arm.runtime_state.active_move_command
	var current_world: Vector3 = scene.call(
		"grid_footprint_center_to_world",
		active_command.get_current_anchor(),
		arm.definition.footprint
	)
	var next_world: Vector3 = scene.call(
		"grid_footprint_center_to_world",
		active_command.get_next_anchor(),
		arm.definition.footprint
	)
	test.expect_vector3_approx(
		arm.global_position,
		current_world.lerp(next_world, progress_before_transform),
		"Moving Actor should remain on the transformed logical segment."
	)

	_complete_move(arm)
	test.expect_equal(arm.runtime_state.anchor_cell, target, "Vehicle should reach the confirmed target.")
	test.expect_equal(arm.runtime_state.motion_state, RUNTIME.MotionState.WAITING, "Arrival should restore Waiting.")
	test.expect_true(vehicle_selection.has_selected_vehicle(), "Arrival should retain vehicle selection.")

	var second_target := Vector2i(6, 2)
	var second_world: Vector3 = scene.call("grid_footprint_center_to_world", second_target, arm.definition.footprint)
	test.expect_true(grid_selection.update_hover_from_world_position(second_world), "A second target should be hoverable.")
	test.expect_true(grid_selection.confirm_selection(), "A second MoveTo should start.")
	arm.advance_move(0.1)
	scene.call("reset_scene")
	test.expect_equal(arm.runtime_state.anchor_cell, Vector2i(2, 2), "Reset should restore the initial arm anchor.")
	test.expect_equal(arm.runtime_state.motion_state, RUNTIME.MotionState.WAITING, "Reset should restore Waiting.")
	test.expect_false(vehicle_selection.has_selected_vehicle(), "Reset should clear vehicle selection.")
	test.expect_false(grid_selection.has_selected_cell(), "Reset should clear the target.")
	test.expect_false(move_controller.is_target_preview_visible(), "Reset should hide target prediction.")
	test.expect_false(move_controller.is_path_preview_visible(), "Reset should hide path prediction.")


func _complete_move(actor) -> void:
	var safety_steps := 0
	while actor.runtime_state.motion_state == RUNTIME.MotionState.MOVING and safety_steps < 100:
		actor.advance_move(0.1)
		safety_steps += 1
	test.expect_true(safety_steps < 100, "MoveTo execution should terminate within the safety bound.")
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
	_test_debug_ui_contract(scene)
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


func _test_debug_ui_contract(scene: Node) -> void:
	var ui = scene.get_node_or_null("UIRoot")
	var panel := scene.get_node_or_null("UIRoot/RootControl/Panel") as PanelContainer
	var body_paths := [
		"UIRoot/RootControl/Panel/Margin/VBox/Instructions",
		"UIRoot/RootControl/Panel/Margin/VBox/ScopeNote",
		"UIRoot/RootControl/Panel/Margin/VBox/RotateRow",
		"UIRoot/RootControl/Panel/Margin/VBox/TransformRow",
		"UIRoot/RootControl/Panel/Margin/VBox/ResetRow",
		"UIRoot/RootControl/Panel/Margin/VBox/StatusLabel",
	]
	test.expect_true(ui != null and panel != null, "Debug UI should expose its collapsible structure.")
	if ui == null or panel == null:
		return
	for path in body_paths:
		test.expect_true(scene.get_node_or_null(path) != null, "Debug UI should preserve stable path %s." % path)
	test.expect_true(bool(ui.call("is_collapsed")), "Debug UI should start collapsed.")
	_expect_body_visibility(scene, body_paths, false, "Collapsed debug UI")
	for node in panel.find_children("*", "Button", true, false):
		var button := node as Button
		test.expect_equal(button.focus_mode, Control.FOCUS_NONE, "%s must ignore Enter/Space focus activation." % button.name)
	ui.call("set_collapsed", false)
	_expect_body_visibility(scene, body_paths, true, "Expanded debug UI")
	ui.call("set_collapsed", true)
	_expect_body_visibility(scene, body_paths, false, "Re-collapsed debug UI")


func _expect_body_visibility(scene: Node, paths: Array, expected: bool, context: String) -> void:
	for path in paths:
		var control := scene.get_node_or_null(path) as Control
		if control != null:
			test.expect_equal(control.visible, expected, "%s should set %s visibility." % [context, path])


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
	test.expect_false(grid_selection.is_live_target_mode(), "Selection alone should not start prediction.")
	test.expect_true(grid_selection.activate_live_target_mode(), "M-equivalent activation should start 2x2 prediction.")
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
	grid_selection.deactivate_live_target_mode()
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
	var transport = manager.get_vehicle_by_id(VEHICLE_MANAGER.TRANSPORT_VEHICLE_ID)
	test.expect_true(arm != null and transport != null, "Both vehicles should exist for the user flow.")
	if arm == null or transport == null:
		return

	camera_rig.set_view_direction(CAMERA_RIG.ViewDirection.NORTHWEST, false)
	await process_frame
	await physics_frame
	var arm_screen: Vector2 = camera_rig.get_camera().unproject_position(
		arm.global_position + arm.global_basis.y.normalized() * arm.cell_size * 0.25
	)
	test.expect_true(vehicle_selection.select_from_screen_position(arm_screen), "Screen ray should select the arm.")
	test.expect_false(grid_selection.is_live_target_mode(), "Selecting a vehicle should not immediately show prediction.")

	var target := Vector2i(5, 2)
	var target_world: Vector3 = scene.call("grid_footprint_center_to_world", target, arm.definition.footprint)
	var target_screen: Vector2 = camera_rig.get_camera().unproject_position(target_world)
	test.expect_false(
		grid_selection.primary_action_from_screen_position(target_screen),
		"Left click on ground should do nothing while a vehicle is selected but MoveTo is not armed."
	)
	test.expect_false(grid_selection.has_selected_cell(), "Unarmed ground click should not create a MoveTo target.")
	test.expect_false(move_controller.is_target_preview_visible(), "Unarmed ground click should not show a target preview.")
	test.expect_false(move_controller.is_path_preview_visible(), "Unarmed ground click should not show a path preview.")

	test.expect_true(grid_selection.activate_live_target_mode(), "M-equivalent command should arm no-op routing.")
	var no_op_click := _left_click(arm_screen)
	vehicle_selection._input(no_op_click)
	test.expect_equal(vehicle_selection.get_selected_vehicle_id(), VEHICLE_MANAGER.ARM_VEHICLE_ID, "M-mode vehicle click must preserve the selected arm.")
	grid_selection._unhandled_input(no_op_click)
	test.expect_equal(arm.runtime_state.motion_state, RUNTIME.MotionState.WAITING, "Vehicle click should submit an accepted no-op.")
	test.expect_false(grid_selection.is_live_target_mode(), "Accepted no-op through the real click chain should exit M mode.")
	test.expect_true(vehicle_selection.has_selected_vehicle(), "Accepted no-op should preserve vehicle selection.")

	test.expect_true(grid_selection.activate_live_target_mode(), "M-equivalent command should re-arm occupancy routing.")
	var transport_screen: Vector2 = camera_rig.get_camera().unproject_position(
		transport.global_position + transport.global_basis.y.normalized() * transport.cell_size * 0.25
	)
	var occupied_click := _left_click(transport_screen)
	vehicle_selection._input(occupied_click)
	test.expect_equal(vehicle_selection.get_selected_vehicle_id(), VEHICLE_MANAGER.ARM_VEHICLE_ID, "M-mode click on another vehicle must not switch selection.")
	grid_selection._unhandled_input(occupied_click)
	test.expect_equal(arm.runtime_state.motion_state, RUNTIME.MotionState.BLOCKED, "Occupied vehicle click should reach footprint rejection.")
	test.expect_true(grid_selection.is_live_target_mode(), "Occupied target rejection should keep M mode armed.")
	test.expect_true(move_controller.is_target_preview_visible(), "Occupied target should retain red target feedback.")
	test.expect_false(move_controller.is_target_preview_valid(), "Occupied target feedback should be invalid.")
	arm.runtime_state.clear_move_command()

	test.expect_true(grid_selection.update_hover_from_screen_position(target_screen), "Screen hover should update the MoveTo target.")
	test.expect_equal(grid_selection.selected_cell, target, "Hover should resolve the expected 2x2 anchor.")
	test.expect_true(move_controller.is_target_preview_valid(), "Reachable hover should show a valid target.")
	test.expect_true(move_controller.is_path_preview_visible(), "Reachable hover should show a path.")
	test.expect_true(grid_selection.primary_action_from_screen_position(target_screen), "Left-click-equivalent primary action should submit MoveTo.")
	test.expect_equal(arm.runtime_state.motion_state, RUNTIME.MotionState.MOVING, "Accepted MoveTo should enter Moving.")
	test.expect_false(grid_selection.is_live_target_mode(), "Accepted left click should leave move command mode.")

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
	test.expect_false(grid_selection.is_live_target_mode(), "Arrival should wait for another M command.")

	test.expect_true(grid_selection.activate_live_target_mode(), "A second M command should arm another move.")
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
	test.expect_false(grid_selection.is_live_target_mode(), "Reset should leave move command mode.")
	test.expect_false(move_controller.is_target_preview_visible(), "Reset should hide target prediction.")
	test.expect_false(move_controller.is_path_preview_visible(), "Reset should hide path prediction.")


func _left_click(screen_position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = screen_position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event


func _complete_move(actor) -> void:
	var safety_steps := 0
	while actor.runtime_state.motion_state == RUNTIME.MotionState.MOVING and safety_steps < 100:
		actor.advance_move(0.1)
		safety_steps += 1
	test.expect_true(safety_steps < 100, "MoveTo execution should terminate within the safety bound.")

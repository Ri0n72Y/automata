extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const VEHICLE_SELECTION := preload("res://scripts/input/vehicle_selection_controller.gd")
const VEHICLE_MOVE := preload("res://scripts/input/vehicle_move_controller.gd")
const GRID_SELECTION := preload("res://scripts/input/grid_selection_controller.gd")
const VEHICLE_MANAGER := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const RUNTIME := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const CONTRACT := preload("res://tests/support/contract_test.gd")

var test := CONTRACT.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	test.expect_true(packed_scene != null, "Scene 01 should load for prediction contract tests.")
	if packed_scene == null:
		test.finish(self, "Vehicle prediction state matrix tests")
		return
	var scene := packed_scene.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame

	var context := _scene_context(scene)
	if not context.is_empty():
		_test_visibility_matrix(context)
		_test_cancel_inputs(context)
		_test_transition_lifecycle(context)

	scene.queue_free()
	await process_frame
	test.finish(self, "Vehicle prediction state matrix tests")


func _scene_context(scene: Node) -> Dictionary:
	var grid_root := scene.get_node_or_null("SceneRoot/GridRoot") as Node3D
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
	for item in [grid_root, vehicle_selection, move_controller, grid_selection, manager]:
		test.expect_true(item != null, "Prediction test scene dependencies should exist.")
	if grid_root == null or vehicle_selection == null or move_controller == null or grid_selection == null or manager == null:
		return {}
	var arm = manager.get_vehicle_by_id(VEHICLE_MANAGER.ARM_VEHICLE_ID)
	var transport = manager.get_vehicle_by_id(VEHICLE_MANAGER.TRANSPORT_VEHICLE_ID)
	test.expect_true(arm != null and transport != null, "Both vehicles should exist.")
	if arm == null or transport == null:
		return {}
	return {
		"grid_root": grid_root,
		"vehicle_selection": vehicle_selection,
		"move_controller": move_controller,
		"grid_selection": grid_selection,
		"arm": arm,
		"transport": transport,
	}


func _test_visibility_matrix(context: Dictionary) -> void:
	var grid_root: Node3D = context["grid_root"]
	var vehicle_selection = context["vehicle_selection"]
	var move_controller = context["move_controller"]
	var grid_selection = context["grid_selection"]
	var arm = context["arm"]
	var hover_world: Vector3 = grid_root.to_global(Vector3(5.08, 0.0, 4.02))

	grid_selection.update_hover_from_world_position(hover_world)
	_expect_state("no vehicle selected", grid_selection, move_controller, false, false, false, false)

	test.expect_true(vehicle_selection.select_vehicle(arm), "Arm should be selectable.")
	test.expect_equal(grid_selection.get_target_footprint(), Vector2i(2, 2), "Selected footprint should configure move-command snapping.")
	grid_selection.update_hover_from_world_position(hover_world)
	_expect_state("selected but not armed", grid_selection, move_controller, true, false, false, false)

	test.expect_true(grid_selection.activate_live_target_mode(), "M-equivalent activation should arm MoveTo prediction.")
	_expect_state("selected and armed", grid_selection, move_controller, true, true, true, true)
	_expect_single_cell_highlights_hidden(grid_selection, "selected and armed")

	move_controller.set_vehicle_ui_open(true)
	_expect_state("external vehicle UI open", grid_selection, move_controller, false, false, false, false)
	move_controller.set_vehicle_ui_open(false)
	_expect_state("external vehicle UI closed", grid_selection, move_controller, true, false, false, false)
	test.expect_true(grid_selection.activate_live_target_mode(), "Closing an external UI should require a fresh move command.")
	_expect_state("re-armed after UI close", grid_selection, move_controller, true, true, true, true)

	test.expect_true(arm.runtime_state.begin_move_planning(), "Planning state should begin from Waiting.")
	move_controller.sync_visuals()
	_expect_state("selected Planning", grid_selection, move_controller, true, true, false, false)
	arm.runtime_state.fail_move_planning()
	move_controller.sync_visuals()
	_expect_state("selected Blocked", grid_selection, move_controller, true, true, true, true)
	arm.runtime_state.clear_move_command()
	move_controller.sync_visuals()
	_expect_state("selected Waiting after clear", grid_selection, move_controller, true, true, true, true)
	grid_selection.deactivate_live_target_mode()


func _test_cancel_inputs(context: Dictionary) -> void:
	var vehicle_selection = context["vehicle_selection"]
	var move_controller = context["move_controller"]
	var grid_selection = context["grid_selection"]
	var arm = context["arm"]
	test.expect_true(vehicle_selection.select_vehicle(arm), "Cancel-input test should select the arm.")

	test.expect_true(grid_selection.activate_live_target_mode(), "Right-click test should arm MoveTo.")
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	vehicle_selection._unhandled_input(right_click)
	grid_selection._unhandled_input(right_click)
	test.expect_false(grid_selection.is_live_target_mode(), "Right click should exit MoveTo mode.")
	test.expect_true(vehicle_selection.has_selected_vehicle(), "Right click should preserve vehicle selection while exiting MoveTo mode.")
	test.expect_false(move_controller.is_target_preview_visible(), "Right click should hide target prediction.")
	test.expect_false(move_controller.is_path_preview_visible(), "Right click should hide path prediction.")

	test.expect_true(grid_selection.activate_live_target_mode(), "Escape test should re-arm MoveTo.")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	vehicle_selection._unhandled_input(escape)
	grid_selection._unhandled_input(escape)
	test.expect_false(grid_selection.is_live_target_mode(), "Escape should exit MoveTo mode.")
	test.expect_true(vehicle_selection.has_selected_vehicle(), "Escape should preserve vehicle selection while exiting MoveTo mode.")
	test.expect_false(move_controller.is_target_preview_visible(), "Escape should hide target prediction.")
	test.expect_false(move_controller.is_path_preview_visible(), "Escape should hide path prediction.")


func _test_transition_lifecycle(context: Dictionary) -> void:
	var grid_root: Node3D = context["grid_root"]
	var vehicle_selection = context["vehicle_selection"]
	var move_controller = context["move_controller"]
	var grid_selection = context["grid_selection"]
	var arm = context["arm"]
	var transport = context["transport"]

	test.expect_true(vehicle_selection.select_vehicle(arm), "Transition test should select the arm.")
	test.expect_true(grid_selection.activate_live_target_mode(), "Transition test should arm MoveTo.")
	var initial_target: Vector3 = grid_root.to_global(Vector3(5.08, 0.0, 4.02))
	grid_selection.update_hover_from_world_position(initial_target)
	test.expect_true(grid_selection.confirm_selection(), "Armed prediction should start MoveTo.")
	test.expect_equal(arm.runtime_state.motion_state, RUNTIME.MotionState.MOVING, "Confirmation should enter Moving.")
	_expect_state("move started", grid_selection, move_controller, false, false, false, false)

	var latest_hover: Vector3 = grid_root.to_global(Vector3(9.05, 0.0, 3.05))
	test.expect_true(grid_selection.update_hover_from_world_position(latest_hover), "Moving hover should remain safe as ordinary ground hover.")
	_expect_state("Moving with hover", grid_selection, move_controller, false, false, false, false)
	test.expect_false(grid_selection.activate_live_target_mode(), "Move command cannot be re-armed while the vehicle is Moving.")

	_complete_move(arm)
	test.expect_equal(arm.runtime_state.motion_state, RUNTIME.MotionState.WAITING, "Completion should restore Waiting.")
	_expect_state("move completed but not re-armed", grid_selection, move_controller, true, false, false, false)
	test.expect_true(grid_selection.activate_live_target_mode(), "A fresh M command should restore prediction after arrival.")
	_expect_state("re-armed after arrival", grid_selection, move_controller, true, true, true, true)

	var completed_callable := Callable(move_controller, "_on_observed_vehicle_move_completed")
	var blocked_callable := Callable(move_controller, "_on_observed_vehicle_move_blocked")
	test.expect_true(vehicle_selection.select_vehicle(transport), "Selection should switch to transport.")
	test.expect_false(arm.move_completed.is_connected(completed_callable), "Old Actor completion signal should disconnect.")
	test.expect_false(arm.move_blocked.is_connected(blocked_callable), "Old Actor blocked signal should disconnect.")
	test.expect_true(transport.move_completed.is_connected(completed_callable), "Current Actor completion signal should connect.")
	test.expect_true(transport.move_blocked.is_connected(blocked_callable), "Current Actor blocked signal should connect.")
	_expect_state("switched idle vehicle", grid_selection, move_controller, true, false, false, false)
	test.expect_true(grid_selection.activate_live_target_mode(), "Switched vehicle should require its own move command.")
	var switched_path: Array[Vector2i] = move_controller.get_preview_path()
	if not switched_path.is_empty():
		test.expect_equal(switched_path.front(), transport.runtime_state.anchor_cell, "Switched prediction should start from the current vehicle.")

	test.expect_true(grid_selection.confirm_selection(), "Transport prediction should start a move.")
	_expect_state("transport Moving", grid_selection, move_controller, false, false, false, false)
	transport.cancel_move()
	test.expect_equal(transport.runtime_state.motion_state, RUNTIME.MotionState.BLOCKED, "Cancel should enter Blocked.")
	_expect_state("transport Blocked but not armed", grid_selection, move_controller, true, false, false, false)
	test.expect_true(grid_selection.activate_live_target_mode(), "Blocked vehicle can accept a corrected move command.")
	_expect_state("transport Blocked and re-armed", grid_selection, move_controller, true, true, true, true)

	vehicle_selection.cancel_selection()
	_expect_state("selection cancelled", grid_selection, move_controller, false, false, false, false)
	test.expect_false(transport.move_completed.is_connected(completed_callable), "Cancel should disconnect completion signal.")
	test.expect_false(transport.move_blocked.is_connected(blocked_callable), "Cancel should disconnect blocked signal.")


func _expect_state(
	name: String,
	grid_selection,
	move_controller,
	expected_available: bool,
	expected_armed: bool,
	expected_target: bool,
	expected_path: bool
) -> void:
	test.expect_equal(grid_selection.is_live_target_available(), expected_available, "%s availability." % name)
	test.expect_equal(grid_selection.is_live_target_mode(), expected_armed, "%s armed mode." % name)
	test.expect_equal(move_controller.is_target_preview_visible(), expected_target, "%s target preview." % name)
	test.expect_equal(move_controller.is_path_preview_visible(), expected_path, "%s path preview." % name)


func _expect_single_cell_highlights_hidden(grid_selection, context: String) -> void:
	var hover := grid_selection.get_node_or_null("HoverHighlight") as MeshInstance3D
	var selected := grid_selection.get_node_or_null("SelectedHighlight") as MeshInstance3D
	test.expect_true(hover != null and not hover.visible, "%s should hide the single-cell hover fill." % context)
	test.expect_true(selected != null and not selected.visible, "%s should hide the single-cell selected fill." % context)


func _complete_move(actor) -> void:
	var safety_steps := 0
	while actor.runtime_state.motion_state == RUNTIME.MotionState.MOVING and safety_steps < 100:
		actor.advance_move(0.1)
		safety_steps += 1
	test.expect_true(safety_steps < 100, "Movement should terminate within the safety bound.")

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
	test.expect_true(packed_scene != null, "Scene 01 should load for move controller tests.")
	if packed_scene == null:
		test.finish(self, "Vehicle move controller contract tests")
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
	test.expect_true(
		vehicle_selection != null and move_controller != null and grid_selection != null and manager != null,
		"Move controller test dependencies should exist."
	)
	if vehicle_selection != null and move_controller != null and grid_selection != null and manager != null:
		_test_submission_boundaries(scene, vehicle_selection, move_controller, grid_selection, manager)

	scene.queue_free()
	await process_frame
	test.finish(self, "Vehicle move controller contract tests")


func _test_submission_boundaries(scene: Node, vehicle_selection, move_controller, grid_selection, manager) -> void:
	var arm = manager.get_vehicle_by_id(VEHICLE_MANAGER.ARM_VEHICLE_ID)
	var transport = manager.get_vehicle_by_id(VEHICLE_MANAGER.TRANSPORT_VEHICLE_ID)
	test.expect_true(arm != null and transport != null, "Both vehicles should exist.")
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

	var no_vehicle_target := Vector2i(4, 2)
	_select_anchor(scene, grid_selection, no_vehicle_target)
	test.expect_true(grid_selection.confirm_selection(), "Ground confirmation should emit without a vehicle.")
	_expect_last_rejection(rejected, &"", no_vehicle_target, VEHICLE_MOVE.REJECTION_NO_VEHICLE, "no vehicle selected")

	grid_selection.cancel_selection()
	test.expect_true(vehicle_selection.select_vehicle(arm), "Arm should be selectable.")
	var no_op_target: Vector2i = arm.runtime_state.anchor_cell
	_select_anchor(scene, grid_selection, no_op_target)
	test.expect_true(move_controller.is_target_preview_valid(), "Current anchor should be a valid no-op target.")
	test.expect_true(grid_selection.confirm_selection(), "No-op target should be accepted.")
	test.expect_equal(accepted.back(), {"vehicle_id": VEHICLE_MANAGER.ARM_VEHICLE_ID, "target": no_op_target}, "No-op acceptance payload.")
	test.expect_equal(arm.runtime_state.motion_state, RUNTIME.MotionState.WAITING, "No-op should remain Waiting.")
	test.expect_true(arm.runtime_state.active_move_command == null, "No-op should not retain a command.")

	var invalid_cases: Array[Dictionary] = [
		{
			"name": "other vehicle occupancy",
			"target": transport.runtime_state.anchor_cell,
		},
		{
			"name": "footprint crossing the boundary",
			"target": Vector2i(10, 5),
		},
	]
	for case in invalid_cases:
		_select_anchor(scene, grid_selection, case["target"])
		test.expect_true(move_controller.is_target_preview_visible(), "%s should show target feedback." % case["name"])
		test.expect_false(move_controller.is_target_preview_valid(), "%s should be invalid." % case["name"])
		test.expect_true(grid_selection.confirm_selection(), "%s should reach command validation." % case["name"])
		_expect_last_rejection(
			rejected,
			VEHICLE_MANAGER.ARM_VEHICLE_ID,
			case["target"],
			VEHICLE_MOVE.REJECTION_NO_PATH,
			case["name"]
		)
		test.expect_equal(arm.runtime_state.motion_state, RUNTIME.MotionState.BLOCKED, "%s should enter Blocked." % case["name"])
		test.expect_true(grid_selection.has_selected_cell(), "%s should retain the target for correction." % case["name"])

	arm.runtime_state.clear_move_command()
	test.expect_true(arm.runtime_state.begin_move_planning(), "Busy boundary should enter Planning.")
	var busy_target := Vector2i(5, 2)
	test.expect_false(move_controller.request_selected_vehicle_move(busy_target), "Planning vehicle should reject another request.")
	_expect_last_rejection(
		rejected,
		VEHICLE_MANAGER.ARM_VEHICLE_ID,
		busy_target,
		VEHICLE_MOVE.REJECTION_BUSY,
		"busy vehicle"
	)
	arm.runtime_state.clear_move_command()

	_select_anchor(scene, grid_selection, busy_target)
	test.expect_true(move_controller.is_target_preview_valid(), "Reachable target should be valid.")
	test.expect_true(grid_selection.confirm_selection(), "Reachable target should be accepted.")
	test.expect_equal(accepted.back(), {"vehicle_id": VEHICLE_MANAGER.ARM_VEHICLE_ID, "target": busy_target}, "Valid acceptance payload.")
	test.expect_equal(arm.runtime_state.motion_state, RUNTIME.MotionState.MOVING, "Valid request should enter Moving.")
	test.expect_true(arm.runtime_state.active_move_command != null, "Valid request should retain the active command.")
	test.expect_false(grid_selection.has_selected_cell(), "Accepted movement should clear the current target.")
	arm.reset_actor()


func _select_anchor(scene: Node, grid_selection, anchor: Vector2i) -> void:
	var world_position: Vector3 = scene.call("grid_cell_to_world", anchor)
	test.expect_true(
		grid_selection.select_from_world_position(world_position),
		"Anchor %s should be selectable as a ground position." % str(anchor)
	)


func _expect_last_rejection(
	rejected: Array[Dictionary],
	expected_vehicle: StringName,
	expected_target: Vector2i,
	expected_reason: StringName,
	context: String
) -> void:
	test.expect_false(rejected.is_empty(), "%s should emit a rejection." % context)
	if rejected.is_empty():
		return
	test.expect_equal(
		rejected.back(),
		{"vehicle_id": expected_vehicle, "target": expected_target, "reason": expected_reason},
		"%s rejection payload." % context
	)

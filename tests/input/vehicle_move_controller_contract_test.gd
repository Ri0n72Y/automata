extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const VEHICLE_SELECTION := preload("res://scripts/input/vehicle_selection_controller.gd")
const VEHICLE_MOVE := preload("res://scripts/input/vehicle_move_controller.gd")
const GRID_SELECTION := preload("res://scripts/input/grid_selection_controller.gd")
const VEHICLE_MANAGER := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const RUNTIME := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const COMMAND := preload("res://scripts/vehicles/move_command.gd")
const CONTRACT := preload("res://tests/support/contract_test.gd")

var test := CONTRACT.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_move_command_input_map()
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


func _test_move_command_input_map() -> void:
	test.expect_true(InputMap.has_action(GRID_SELECTION.MOVE_COMMAND_ACTION), "Move command should be an Input Map action.")
	var has_m := false
	var has_accept_key := false
	for input_event in InputMap.action_get_events(GRID_SELECTION.MOVE_COMMAND_ACTION):
		var key_event := input_event as InputEventKey
		if key_event == null:
			continue
		if key_event.keycode == KEY_M:
			has_m = true
		if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_SPACE:
			has_accept_key = true
	test.expect_true(has_m, "Move command should default to M.")
	test.expect_false(has_accept_key, "Enter and Space must not be bound to MoveTo.")


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
	test.expect_false(move_controller.request_selected_vehicle_move(no_vehicle_target), "Direct request should reject without a vehicle.")
	_expect_last_rejection(rejected, &"", no_vehicle_target, VEHICLE_MOVE.REJECTION_NO_VEHICLE, "no vehicle selected")

	test.expect_true(vehicle_selection.select_vehicle(arm), "Arm should be selectable.")
	test.expect_true(grid_selection.is_live_target_available(), "Vehicle selection should make the move command available.")
	test.expect_false(grid_selection.is_live_target_mode(), "Vehicle selection alone should not show prediction.")
	var accepted_before_unarmed := accepted.size()
	var rejected_before_unarmed := rejected.size()
	grid_selection.selection_confirmed.emit(Vector2i(5, 2))
	test.expect_equal(accepted.size(), accepted_before_unarmed, "Unarmed confirmation signal must not accept movement.")
	test.expect_equal(rejected.size(), rejected_before_unarmed, "Unarmed confirmation signal must be ignored without rejection noise.")
	test.expect_equal(arm.runtime_state.motion_state, RUNTIME.MotionState.WAITING, "Unarmed confirmation preserves Waiting.")

	test.expect_true(grid_selection.activate_live_target_mode(), "M-equivalent activation should arm prediction.")
	var no_op_target: Vector2i = arm.runtime_state.anchor_cell
	_select_anchor(scene, grid_selection, no_op_target)
	test.expect_true(move_controller.is_target_preview_valid(), "Current anchor should be a valid no-op target.")
	test.expect_true(grid_selection.confirm_selection(), "No-op target should be accepted.")
	test.expect_equal(accepted.back(), {"vehicle_id": VEHICLE_MANAGER.ARM_VEHICLE_ID, "target": no_op_target}, "No-op acceptance payload.")
	test.expect_equal(arm.runtime_state.motion_state, RUNTIME.MotionState.WAITING, "No-op should remain Waiting.")
	test.expect_true(arm.runtime_state.active_move_command == null, "No-op should not retain a command.")
	test.expect_false(grid_selection.is_live_target_mode(), "Accepted no-op should leave move command mode.")
	test.expect_true(grid_selection.activate_live_target_mode(), "A new M command should re-arm after no-op.")

	var invalid_cases: Array[Dictionary] = [
		{"name": "other vehicle occupancy", "target": transport.runtime_state.anchor_cell},
		{"name": "left edge footprint", "target": Vector2i(0, 2)},
		{"name": "right edge footprint", "target": Vector2i(10, 2)},
		{"name": "bottom edge footprint", "target": Vector2i(4, 0)},
		{"name": "top edge footprint", "target": Vector2i(4, 6)},
		{"name": "bottom-left corner footprint", "target": Vector2i(0, 0)},
		{"name": "bottom-right corner footprint", "target": Vector2i(10, 0)},
		{"name": "top-left corner footprint", "target": Vector2i(0, 6)},
		{"name": "top-right corner footprint", "target": Vector2i(10, 6)},
	]
	for case in invalid_cases:
		_select_anchor(scene, grid_selection, case["target"])
		test.expect_true(move_controller.is_target_preview_visible(), "%s should show target feedback." % case["name"])
		test.expect_false(move_controller.is_target_preview_valid(), "%s should be invalid." % case["name"])
		test.expect_true(grid_selection.confirm_selection(), "%s should reach footprint validation." % case["name"])
		_expect_last_rejection(
			rejected,
			VEHICLE_MANAGER.ARM_VEHICLE_ID,
			case["target"],
			VEHICLE_MOVE.REJECTION_NO_PATH,
			case["name"]
		)
		test.expect_equal(arm.runtime_state.motion_state, RUNTIME.MotionState.BLOCKED, "%s should enter Blocked." % case["name"])
		test.expect_true(grid_selection.has_selected_cell(), "%s should retain the target for correction." % case["name"])
		test.expect_true(grid_selection.is_live_target_mode(), "%s rejection should keep move command mode armed." % case["name"])

	arm.runtime_state.clear_move_command()
	var transport_command: COMMAND = COMMAND.new()
	var transport_start: Vector2i = transport.runtime_state.anchor_cell
	var transport_target := transport_start + Vector2i.LEFT
	test.expect_true(
		transport_command.configure(transport_target, [transport_start, transport_target]),
		"Concurrent lock fixture command should configure."
	)
	test.expect_true(transport.start_move(transport_command), "Transport should start the concurrent lock fixture move.")
	test.expect_false(vehicle_selection.select_vehicle(transport), "Another active vehicle should prevent selection switching.")
	var global_busy_target := Vector2i(5, 2)
	test.expect_false(move_controller.request_selected_vehicle_move(global_busy_target), "Another active vehicle should reject a direct move request.")
	_expect_last_rejection(
		rejected,
		VEHICLE_MANAGER.ARM_VEHICLE_ID,
		global_busy_target,
		VEHICLE_MOVE.REJECTION_BUSY,
		"another active vehicle"
	)
	test.expect_equal(arm.runtime_state.motion_state, RUNTIME.MotionState.WAITING, "Global lock rejection should preserve selected vehicle Waiting.")
	transport.reset_actor()

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
	test.expect_false(grid_selection.is_live_target_mode(), "Accepted movement should leave move command mode.")
	test.expect_false(grid_selection.is_live_target_available(), "Move command should remain locked during movement.")
	arm.reset_actor()


func _select_anchor(scene: Node, grid_selection, anchor: Vector2i) -> void:
	var world_position: Vector3 = scene.call("grid_cell_to_world", anchor)
	test.expect_true(
		grid_selection.select_from_world_position(world_position),
		"Anchor %s should be selectable as a ground position." % str(anchor)
	)
	test.expect_equal(grid_selection.selected_cell, anchor, "Anchor %s should remain the selected target." % str(anchor))


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

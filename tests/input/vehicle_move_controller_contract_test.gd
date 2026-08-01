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
	_test_command_input_map()
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
		await _test_submission_boundaries(
			scene,
			vehicle_selection,
			move_controller,
			grid_selection,
			manager
		)
		await _test_real_physics_frame_coordination(manager)

	scene.queue_free()
	await process_frame
	test.finish(self, "Vehicle move controller contract tests")


func _test_command_input_map() -> void:
	test.expect_true(
		InputMap.has_action(GRID_SELECTION.MOVE_COMMAND_ACTION),
		"Move command should be an Input Map action."
	)
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

	test.expect_true(
		InputMap.has_action(VEHICLE_MOVE.STOP_TASK_ACTION),
		"Stop task should be an Input Map action."
	)
	var has_x := false
	for input_event in InputMap.action_get_events(VEHICLE_MOVE.STOP_TASK_ACTION):
		var key_event := input_event as InputEventKey
		if key_event != null and key_event.keycode == KEY_X:
			has_x = true
	test.expect_true(has_x, "Stop task should default to X.")


func _test_submission_boundaries(
	scene: Node,
	vehicle_selection,
	move_controller,
	grid_selection,
	manager
) -> void:
	var arm = manager.get_vehicle_by_id(VEHICLE_MANAGER.ARM_VEHICLE_ID)
	var transport = manager.get_vehicle_by_id(VEHICLE_MANAGER.TRANSPORT_VEHICLE_ID)
	test.expect_true(arm != null and transport != null, "Both vehicles should exist.")
	if arm == null or transport == null:
		return

	var accepted: Array[Dictionary] = []
	var rejected: Array[Dictionary] = []
	var stopped: Array[StringName] = []
	move_controller.move_accepted.connect(
		func(vehicle_id: StringName, target: Vector2i) -> void:
			accepted.append({"vehicle_id": vehicle_id, "target": target})
	)
	move_controller.move_rejected.connect(
		func(vehicle_id: StringName, target: Vector2i, reason: StringName) -> void:
			rejected.append({"vehicle_id": vehicle_id, "target": target, "reason": reason})
	)
	move_controller.move_stopped.connect(
		func(vehicle_id: StringName) -> void:
			stopped.append(vehicle_id)
	)

	var no_vehicle_target := Vector2i(4, 2)
	test.expect_false(
		move_controller.request_selected_vehicle_move(no_vehicle_target),
		"Direct request should reject without a vehicle."
	)
	_expect_last_rejection(
		rejected,
		&"",
		no_vehicle_target,
		VEHICLE_MOVE.REJECTION_NO_VEHICLE,
		"no vehicle selected"
	)

	test.expect_true(vehicle_selection.select_vehicle(arm), "Arm should be selectable.")
	test.expect_true(
		grid_selection.is_live_target_available(),
		"Vehicle selection should make the move command available."
	)
	test.expect_false(
		grid_selection.is_live_target_mode(),
		"Vehicle selection alone should not show prediction."
	)
	var accepted_before_unarmed := accepted.size()
	var rejected_before_unarmed := rejected.size()
	grid_selection.selection_confirmed.emit(Vector2i(5, 2))
	test.expect_equal(
		accepted.size(),
		accepted_before_unarmed,
		"Unarmed confirmation signal must not accept movement."
	)
	test.expect_equal(
		rejected.size(),
		rejected_before_unarmed,
		"Unarmed confirmation signal must be ignored without rejection noise."
	)
	test.expect_equal(
		arm.runtime_state.motion_state,
		RUNTIME.MotionState.WAITING,
		"Unarmed confirmation preserves Waiting."
	)

	test.expect_true(
		grid_selection.activate_live_target_mode(),
		"M-equivalent activation should arm prediction."
	)
	var no_op_target: Vector2i = arm.runtime_state.anchor_cell
	_select_anchor(scene, grid_selection, no_op_target)
	test.expect_true(
		move_controller.is_target_preview_valid(),
		"Current anchor should be a valid no-op target."
	)
	test.expect_true(grid_selection.confirm_selection(), "No-op target should be accepted.")
	test.expect_equal(
		accepted.back(),
		{"vehicle_id": VEHICLE_MANAGER.ARM_VEHICLE_ID, "target": no_op_target},
		"No-op acceptance payload."
	)
	test.expect_equal(
		arm.runtime_state.motion_state,
		RUNTIME.MotionState.WAITING,
		"No-op should remain Waiting."
	)
	test.expect_true(
		arm.runtime_state.active_move_command == null,
		"No-op should not retain a command."
	)
	test.expect_false(
		grid_selection.is_live_target_mode(),
		"Accepted no-op should leave move command mode."
	)
	test.expect_true(
		grid_selection.activate_live_target_mode(),
		"A new M command should re-arm after no-op."
	)

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
		test.expect_true(
			move_controller.is_target_preview_visible(),
			"%s should show target feedback." % case["name"]
		)
		test.expect_false(
			move_controller.is_target_preview_valid(),
			"%s should be invalid." % case["name"]
		)
		test.expect_true(
			grid_selection.confirm_selection(),
			"%s should reach footprint validation." % case["name"]
		)
		_expect_last_rejection(
			rejected,
			VEHICLE_MANAGER.ARM_VEHICLE_ID,
			case["target"],
			VEHICLE_MOVE.REJECTION_NO_PATH,
			case["name"]
		)
		test.expect_equal(
			arm.runtime_state.motion_state,
			RUNTIME.MotionState.BLOCKED,
			"%s should enter Blocked." % case["name"]
		)
		test.expect_true(
			grid_selection.has_selected_cell(),
			"%s should retain the target for correction." % case["name"]
		)
		test.expect_true(
			grid_selection.is_live_target_mode(),
			"%s rejection should keep move command mode armed." % case["name"]
		)

	_test_concurrent_selection_availability(
		vehicle_selection,
		move_controller,
		grid_selection,
		arm,
		transport
	)
	await _test_manual_stop(
		vehicle_selection,
		move_controller,
		grid_selection,
		arm,
		transport,
		stopped
	)
	_test_continuous_collision_boundaries(move_controller, arm, transport)

	test.expect_true(
		vehicle_selection.select_vehicle(arm),
		"Arm should be selectable after collision fixtures reset."
	)
	test.expect_true(
		arm.runtime_state.begin_move_planning(),
		"Busy boundary should enter Planning."
	)
	var busy_target := Vector2i(5, 2)
	test.expect_false(
		move_controller.request_selected_vehicle_move(busy_target),
		"Planning vehicle should reject another request."
	)
	_expect_last_rejection(
		rejected,
		VEHICLE_MANAGER.ARM_VEHICLE_ID,
		busy_target,
		VEHICLE_MOVE.REJECTION_BUSY,
		"busy vehicle"
	)
	arm.runtime_state.clear_move_command()
	move_controller._sync_live_target_mode()

	test.expect_true(
		grid_selection.activate_live_target_mode(),
		"A fresh M command should arm the final valid request."
	)
	_select_anchor(scene, grid_selection, busy_target)
	test.expect_true(
		move_controller.is_target_preview_valid(),
		"Reachable target should be valid."
	)
	test.expect_true(grid_selection.confirm_selection(), "Reachable target should be accepted.")
	test.expect_equal(
		accepted.back(),
		{"vehicle_id": VEHICLE_MANAGER.ARM_VEHICLE_ID, "target": busy_target},
		"Valid acceptance payload."
	)
	test.expect_equal(
		arm.runtime_state.motion_state,
		RUNTIME.MotionState.MOVING,
		"Valid request should enter Moving."
	)
	test.expect_true(
		arm.runtime_state.active_move_command != null,
		"Valid request should retain the active command."
	)
	test.expect_false(
		grid_selection.has_selected_cell(),
		"Accepted movement should clear the current target."
	)
	test.expect_false(
		grid_selection.is_live_target_mode(),
		"Accepted movement should leave move command mode."
	)
	test.expect_false(
		grid_selection.is_live_target_available(),
		"Selected moving vehicle should lock its own move command."
	)
	arm.reset_actor()
	transport.reset_actor()


func _test_concurrent_selection_availability(
	vehicle_selection,
	move_controller,
	grid_selection,
	arm,
	transport
) -> void:
	arm.runtime_state.clear_move_command()
	transport.runtime_state.clear_move_command()
	grid_selection.deactivate_live_target_mode()
	var arm_start: Vector2i = arm.runtime_state.anchor_cell
	var arm_target: Vector2i = arm_start + Vector2i.RIGHT
	test.expect_true(
		arm.start_move(_command(arm_target, [arm_start, arm_target])),
		"Arm should start an independent task."
	)
	test.expect_true(
		vehicle_selection.select_vehicle(transport),
		"A moving arm must not prevent selecting transport."
	)
	test.expect_true(
		grid_selection.is_live_target_available(),
		"Waiting transport should expose its move command while arm moves."
	)
	test.expect_true(
		vehicle_selection.select_vehicle(arm),
		"A moving vehicle may be reselected for inspection."
	)
	test.expect_false(
		grid_selection.is_live_target_available(),
		"Reselected Moving vehicle must not advertise another move command."
	)
	test.expect_false(
		grid_selection.activate_live_target_mode(),
		"Moving vehicle must reject M activation."
	)
	test.expect_true(
		vehicle_selection.select_vehicle(transport),
		"Transport should remain selectable after inspecting moving arm."
	)
	test.expect_true(
		grid_selection.is_live_target_available(),
		"Switching back to Waiting transport restores command availability."
	)
	var transport_target: Vector2i = transport.runtime_state.anchor_cell + Vector2i.LEFT
	test.expect_true(
		move_controller.request_selected_vehicle_move(transport_target),
		"Transport should accept a non-conflicting task while arm moves."
	)
	test.expect_false(
		grid_selection.is_live_target_available(),
		"Programmatic move acceptance must immediately mark selected transport busy."
	)
	move_controller._physics_process(0.1)
	test.expect_equal(
		arm.runtime_state.motion_state,
		RUNTIME.MotionState.MOVING,
		"Arm task should continue after selection changes."
	)
	test.expect_equal(
		transport.runtime_state.motion_state,
		RUNTIME.MotionState.MOVING,
		"Transport should run concurrently."
	)
	arm.reset_actor()
	transport.reset_actor()


func _test_manual_stop(
	vehicle_selection,
	move_controller,
	grid_selection,
	arm,
	transport,
	stopped: Array[StringName]
) -> void:
	grid_selection.deactivate_live_target_mode()
	_place_vehicle(arm, Vector2i(1, 1))
	_place_vehicle(transport, Vector2i(6, 4))
	test.expect_true(
		arm.start_move(_command(
			Vector2i(5, 1),
			[
				Vector2i(1, 1),
				Vector2i(2, 1),
				Vector2i(3, 1),
				Vector2i(4, 1),
				Vector2i(5, 1),
			]
		)),
		"Arm task should start for manual stop."
	)
	test.expect_true(
		transport.start_move(_command(
			Vector2i(5, 4),
			[Vector2i(6, 4), Vector2i(5, 4)]
		)),
		"Transport task should continue independently during arm stop."
	)
	move_controller.set_physics_process(false)
	var stopped_before := stopped.size()
	vehicle_selection.cancel_selection()
	await _push_key(KEY_X)
	test.expect_equal(
		arm.runtime_state.motion_state,
		RUNTIME.MotionState.MOVING,
		"Viewport X without a selected vehicle must not stop arm."
	)
	test.expect_equal(
		transport.runtime_state.motion_state,
		RUNTIME.MotionState.MOVING,
		"Viewport X without a selected vehicle must not stop transport."
	)
	test.expect_equal(
		stopped.size(),
		stopped_before,
		"Viewport X without a selection must not emit move_stopped."
	)

	test.expect_true(vehicle_selection.select_vehicle(arm), "Arm should be selected for manual stop.")
	var modifier_cases: Array[Dictionary] = [
		{"name": "Shift", "shift": true, "ctrl": false, "alt": false, "meta": false},
		{"name": "Ctrl", "shift": false, "ctrl": true, "alt": false, "meta": false},
		{"name": "Alt", "shift": false, "ctrl": false, "alt": true, "meta": false},
		{"name": "Meta", "shift": false, "ctrl": false, "alt": false, "meta": true},
	]
	for case in modifier_cases:
		await _push_key(
			KEY_X,
			bool(case["shift"]),
			bool(case["ctrl"]),
			bool(case["alt"]),
			bool(case["meta"])
		)
		test.expect_equal(
			arm.runtime_state.motion_state,
			RUNTIME.MotionState.MOVING,
			"%s+X through Viewport must not stop the selected task." % case["name"]
		)
		test.expect_equal(
			stopped.size(),
			stopped_before,
			"%s+X must not emit move_stopped." % case["name"]
		)

	var last_reached_anchor: Vector2i = arm.runtime_state.anchor_cell
	await _push_key(KEY_X)
	test.expect_equal(
		arm.runtime_state.motion_state,
		RUNTIME.MotionState.BLOCKED,
		"Viewport X should stop the selected Moving task."
	)
	test.expect_true(
		arm.runtime_state.active_move_command == null,
		"Manual stop should clear the selected vehicle command."
	)
	test.expect_equal(
		arm.runtime_state.anchor_cell,
		last_reached_anchor,
		"Manual stop should return to the last reached anchor."
	)
	test.expect_equal(
		transport.runtime_state.motion_state,
		RUNTIME.MotionState.MOVING,
		"Manual stop must not affect another vehicle task."
	)
	test.expect_equal(
		vehicle_selection.get_selected_vehicle(),
		arm,
		"Manual stop should preserve vehicle selection."
	)
	test.expect_true(
		grid_selection.is_live_target_available(),
		"Stopped vehicle should immediately accept a replacement task."
	)
	test.expect_equal(
		stopped.size(),
		stopped_before + 1,
		"Manual stop should emit exactly one stop event."
	)
	test.expect_equal(
		stopped.back(),
		VEHICLE_MANAGER.ARM_VEHICLE_ID,
		"Manual stop should identify the selected vehicle."
	)

	await _push_key(KEY_X)
	test.expect_equal(
		arm.runtime_state.motion_state,
		RUNTIME.MotionState.BLOCKED,
		"Viewport X should ignore an already Blocked vehicle."
	)
	test.expect_equal(
		stopped.size(),
		stopped_before + 1,
		"Blocked duplicate X must not emit another stop event."
	)

	arm.reset_actor()
	await _push_key(KEY_X)
	test.expect_equal(
		arm.runtime_state.motion_state,
		RUNTIME.MotionState.WAITING,
		"Viewport X should ignore a Waiting vehicle."
	)
	test.expect_equal(
		stopped.size(),
		stopped_before + 1,
		"Waiting X must not emit another stop event."
	)
	transport.reset_actor()
	move_controller.set_physics_process(true)


func _test_continuous_collision_boundaries(move_controller, arm, transport) -> void:
	_place_vehicle(arm, Vector2i(3, 3))
	_place_vehicle(transport, Vector2i(6, 3))
	test.expect_true(
		arm.start_move(_command(Vector2i(4, 3), [Vector2i(3, 3), Vector2i(4, 3)])),
		"Head-on arm task should start."
	)
	test.expect_true(
		transport.start_move(_command(Vector2i(5, 3), [Vector2i(6, 3), Vector2i(5, 3)])),
		"Head-on transport task should start."
	)
	move_controller._physics_process(0.5)
	test.expect_equal(
		arm.runtime_state.motion_state,
		RUNTIME.MotionState.BLOCKED,
		"Same-frame head-on arm collision should block."
	)
	test.expect_equal(
		transport.runtime_state.motion_state,
		RUNTIME.MotionState.BLOCKED,
		"Same-frame head-on transport collision should block."
	)
	test.expect_true(
		arm.runtime_state.active_move_command == null,
		"Colliding arm should clear its active command."
	)
	test.expect_true(
		transport.runtime_state.active_move_command == null,
		"Colliding transport should clear its active command."
	)

	_place_vehicle(arm, Vector2i(1, 1))
	_place_vehicle(transport, Vector2i(4, 1))
	test.expect_true(
		arm.start_move(_command(
			Vector2i(5, 1),
			[Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1)]
		)),
		"Long arm task should start for tunneling coverage."
	)
	move_controller._physics_process(2.0)
	test.expect_equal(
		arm.runtime_state.motion_state,
		RUNTIME.MotionState.BLOCKED,
		"Large-delta multi-segment traversal must not tunnel through a static vehicle."
	)
	test.expect_equal(
		transport.runtime_state.motion_state,
		RUNTIME.MotionState.WAITING,
		"Static collision target should remain Waiting."
	)
	test.expect_equal(
		arm.runtime_state.anchor_cell,
		Vector2i(2, 1),
		"Large-delta collision should retain the last safe completed anchor."
	)

	_place_vehicle(arm, Vector2i(1, 1))
	_place_vehicle(transport, Vector2i(4, 1))
	test.expect_true(
		arm.start_move(_command(
			Vector2i(5, 1),
			[Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(5, 1)]
		)),
		"Small-step arm task should start for frame-invariance coverage."
	)
	for _step in range(20):
		move_controller._physics_process(0.1)
		if arm.runtime_state.motion_state == RUNTIME.MotionState.BLOCKED:
			break
	test.expect_equal(
		arm.runtime_state.motion_state,
		RUNTIME.MotionState.BLOCKED,
		"Small-step traversal should detect the same static collision."
	)
	test.expect_equal(
		arm.runtime_state.anchor_cell,
		Vector2i(2, 1),
		"Collision safe anchor must be invariant across physics-frame sizes."
	)

	_place_vehicle(arm, Vector2i(1, 3))
	_place_vehicle(transport, Vector2i(8, 3))
	test.expect_true(
		arm.start_move(_command(
			Vector2i(5, 3),
			[
				Vector2i(1, 3),
				Vector2i(2, 3),
				Vector2i(3, 3),
				Vector2i(4, 3),
				Vector2i(5, 3),
			]
		)),
		"Large-delta moving arm task should start with multiple safe nodes."
	)
	test.expect_true(
		transport.start_move(_command(
			Vector2i(4, 3),
			[
				Vector2i(8, 3),
				Vector2i(7, 3),
				Vector2i(6, 3),
				Vector2i(5, 3),
				Vector2i(4, 3),
			]
		)),
		"Large-delta moving transport task should start with multiple safe nodes."
	)
	move_controller._physics_process(2.0)
	test.expect_equal(
		arm.runtime_state.motion_state,
		RUNTIME.MotionState.BLOCKED,
		"Large-delta moving collision should block arm."
	)
	test.expect_equal(
		transport.runtime_state.motion_state,
		RUNTIME.MotionState.BLOCKED,
		"Large-delta moving collision should block transport."
	)
	var large_arm_safe_anchor: Vector2i = arm.runtime_state.anchor_cell
	var large_transport_safe_anchor: Vector2i = transport.runtime_state.anchor_cell
	test.expect_equal(
		large_arm_safe_anchor,
		Vector2i(3, 3),
		"Arm should retain its last safe completed node before moving collision."
	)
	test.expect_equal(
		large_transport_safe_anchor,
		Vector2i(6, 3),
		"Transport should retain its last safe completed node before moving collision."
	)
	test.expect_false(
		_vehicle_footprints_overlap(arm, transport),
		"Blocked moving vehicles must end on non-overlapping safe footprints."
	)

	_place_vehicle(arm, Vector2i(1, 3))
	_place_vehicle(transport, Vector2i(8, 3))
	test.expect_true(
		arm.start_move(_command(
			Vector2i(5, 3),
			[
				Vector2i(1, 3),
				Vector2i(2, 3),
				Vector2i(3, 3),
				Vector2i(4, 3),
				Vector2i(5, 3),
			]
		)),
		"Small-step moving arm task should start for frame-invariance coverage."
	)
	test.expect_true(
		transport.start_move(_command(
			Vector2i(4, 3),
			[
				Vector2i(8, 3),
				Vector2i(7, 3),
				Vector2i(6, 3),
				Vector2i(5, 3),
				Vector2i(4, 3),
			]
		)),
		"Small-step moving transport task should start for frame-invariance coverage."
	)
	for _step in range(30):
		move_controller._physics_process(0.1)
		if (
			arm.runtime_state.motion_state == RUNTIME.MotionState.BLOCKED
			and transport.runtime_state.motion_state == RUNTIME.MotionState.BLOCKED
		):
			break
	test.expect_equal(
		arm.runtime_state.motion_state,
		RUNTIME.MotionState.BLOCKED,
		"Small-step moving collision should block arm."
	)
	test.expect_equal(
		transport.runtime_state.motion_state,
		RUNTIME.MotionState.BLOCKED,
		"Small-step moving collision should block transport."
	)
	test.expect_equal(
		arm.runtime_state.anchor_cell,
		large_arm_safe_anchor,
		"Arm safe anchor must be invariant across physics-frame sizes."
	)
	test.expect_equal(
		transport.runtime_state.anchor_cell,
		large_transport_safe_anchor,
		"Transport safe anchor must be invariant across physics-frame sizes."
	)
	test.expect_false(
		_vehicle_footprints_overlap(arm, transport),
		"Small-step blocked vehicles must end on non-overlapping safe footprints."
	)

	_place_vehicle(arm, Vector2i(2, 3))
	_place_vehicle(transport, Vector2i(7, 3))
	test.expect_true(
		arm.start_move(_command(Vector2i(3, 3), [Vector2i(2, 3), Vector2i(3, 3)])),
		"Early-finishing arm task should start."
	)
	test.expect_true(
		transport.start_move(_command(
			Vector2i(4, 3),
			[Vector2i(7, 3), Vector2i(6, 3), Vector2i(5, 3), Vector2i(4, 3)]
		)),
		"Later transport collision task should start."
	)
	move_controller._physics_process(1.0)
	test.expect_equal(
		arm.runtime_state.motion_state,
		RUNTIME.MotionState.WAITING,
		"Vehicle completed before the collision time must remain Waiting."
	)
	test.expect_equal(
		arm.runtime_state.anchor_cell,
		Vector2i(3, 3),
		"Early-finishing vehicle should retain its completed target."
	)
	test.expect_equal(
		transport.runtime_state.motion_state,
		RUNTIME.MotionState.BLOCKED,
		"Vehicle moving into the completed vehicle should enter Blocked."
	)
	test.expect_equal(
		transport.runtime_state.anchor_cell,
		Vector2i(5, 3),
		"Later collision should retain transport's last safe completed anchor."
	)

	_place_vehicle(arm, Vector2i(1, 1))
	_place_vehicle(transport, Vector2i(4, 1))
	test.expect_true(
		arm.start_move(_command(Vector2i(2, 1), [Vector2i(1, 1), Vector2i(2, 1)])),
		"Edge-contact arm task should start."
	)
	move_controller._physics_process(0.5)
	test.expect_equal(
		arm.runtime_state.motion_state,
		RUNTIME.MotionState.WAITING,
		"Footprints touching only at an edge must not collide."
	)
	test.expect_equal(
		arm.runtime_state.anchor_cell,
		Vector2i(2, 1),
		"Edge-contact movement should complete normally."
	)
	test.expect_equal(
		transport.runtime_state.motion_state,
		RUNTIME.MotionState.WAITING,
		"Edge-contact transport remains Waiting."
	)

	arm.reset_actor()
	transport.reset_actor()


func _vehicle_footprints_overlap(first, second) -> bool:
	var first_anchor: Vector2i = first.runtime_state.anchor_cell
	var second_anchor: Vector2i = second.runtime_state.anchor_cell
	var first_footprint: Vector2i = first.definition.footprint
	var second_footprint: Vector2i = second.definition.footprint
	return (
		first_anchor.x < second_anchor.x + second_footprint.x
		and first_anchor.x + first_footprint.x > second_anchor.x
		and first_anchor.y < second_anchor.y + second_footprint.y
		and first_anchor.y + first_footprint.y > second_anchor.y
	)


func _test_real_physics_frame_coordination(manager) -> void:
	var arm = manager.get_vehicle_by_id(VEHICLE_MANAGER.ARM_VEHICLE_ID)
	var transport = manager.get_vehicle_by_id(VEHICLE_MANAGER.TRANSPORT_VEHICLE_ID)
	if arm == null or transport == null:
		test.expect_true(false, "Real physics coordination requires both vehicles.")
		return
	_place_vehicle(arm, Vector2i(3, 3))
	_place_vehicle(transport, Vector2i(6, 3))
	test.expect_true(
		arm.start_move(_command(Vector2i(4, 3), [Vector2i(3, 3), Vector2i(4, 3)])),
		"Real-frame arm collision task should start."
	)
	test.expect_true(
		transport.start_move(_command(Vector2i(5, 3), [Vector2i(6, 3), Vector2i(5, 3)])),
		"Real-frame transport collision task should start."
	)
	test.expect_false(
		arm.is_physics_processing(),
		"Coordinator should disable actor-owned physics processing for arm."
	)
	test.expect_false(
		transport.is_physics_processing(),
		"Coordinator should disable actor-owned physics processing for transport."
	)
	for _frame in range(45):
		await physics_frame
		if (
			arm.runtime_state.motion_state == RUNTIME.MotionState.BLOCKED
			and transport.runtime_state.motion_state == RUNTIME.MotionState.BLOCKED
		):
			break
	test.expect_equal(
		arm.runtime_state.motion_state,
		RUNTIME.MotionState.BLOCKED,
		"Real physics frames should block colliding arm task."
	)
	test.expect_equal(
		transport.runtime_state.motion_state,
		RUNTIME.MotionState.BLOCKED,
		"Real physics frames should block colliding transport task."
	)
	arm.reset_actor()
	transport.reset_actor()


func _push_key(
	keycode: int,
	shifted: bool = false,
	controlled: bool = false,
	alted: bool = false,
	metaed: bool = false
) -> void:
	root.push_input(_key_event(keycode, true, shifted, controlled, alted, metaed))
	await process_frame
	root.push_input(_key_event(keycode, false, shifted, controlled, alted, metaed))
	await process_frame


func _place_vehicle(vehicle, anchor: Vector2i) -> void:
	vehicle.reset_actor()
	vehicle.runtime_state.anchor_cell = anchor
	vehicle.sync_from_state()


func _command(target: Vector2i, path: Array[Vector2i]) -> COMMAND:
	var command: COMMAND = COMMAND.new()
	test.expect_true(command.configure(target, path), "Test command should configure.")
	return command


func _key_event(
	keycode: int,
	pressed: bool,
	shifted: bool = false,
	controlled: bool = false,
	alted: bool = false,
	metaed: bool = false
) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = pressed
	event.keycode = keycode
	event.shift_pressed = shifted
	event.ctrl_pressed = controlled
	event.alt_pressed = alted
	event.meta_pressed = metaed
	return event


func _select_anchor(scene: Node, grid_selection, anchor: Vector2i) -> void:
	var world_position: Vector3 = scene.call("grid_cell_to_world", anchor)
	test.expect_true(
		grid_selection.select_from_world_position(world_position),
		"Anchor %s should be selectable as a ground position." % str(anchor)
	)
	test.expect_equal(
		grid_selection.selected_cell,
		anchor,
		"Anchor %s should remain the selected target." % str(anchor)
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

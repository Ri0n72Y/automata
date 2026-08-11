extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const LifecycleStateScript := preload("res://scripts/scene_01/scene_01_lifecycle_state.gd")
const LifecycleControllerScript := preload("res://scripts/scene_01/scene_01_lifecycle_controller.gd")
const LifecycleControlsScript := preload("res://scripts/scene_01/scene_01_lifecycle_controls.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const VehicleSelectionScript := preload("res://scripts/input/vehicle_selection_controller.gd")
const GridSelectionScript := preload("res://scripts/input/grid_selection_controller.gd")
const VehicleMoveScript := preload("res://scripts/input/vehicle_move_controller.gd")
const GrabDropControllerScript := preload("res://scripts/input/vehicle_grab_drop_controller.gd")
const GrabDropResultScript := preload("res://scripts/vehicles/grab_drop_result.gd")

var failures: int = 0
var lifecycle_events: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var baseline_root_child_count: int = root.get_child_count()
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for lifecycle smoke test.")
	if packed == null:
		_finish()
		return

	var scene := packed.instantiate() as LifecycleControllerScript
	_expect_true(scene != null, "Scene 01 root should use the lifecycle controller.")
	if scene == null:
		_finish()
		return
	root.add_child(scene)
	await process_frame
	_bind_lifecycle_events(scene)

	var lifecycle_ui := scene.get_node_or_null("LifecycleUIRoot") as LifecycleControlsScript
	var run_pause_button := scene.get_node_or_null(
		"LifecycleUIRoot/RootControl/Panel/Margin/Controls/RunPauseButton"
	) as Button
	var speed_button := scene.get_node_or_null(
		"LifecycleUIRoot/RootControl/Panel/Margin/Controls/SpeedButton"
	) as Button
	var reset_button := scene.get_node_or_null(
		"LifecycleUIRoot/RootControl/Panel/Margin/Controls/ResetButton"
	) as Button
	var vehicle_manager := scene.get_node_or_null(
		"SceneRoot/RobotRoot/Scene01VehicleManager"
	) as VehicleManagerScript
	var vehicle_selection := scene.get_node_or_null(
		"SceneRoot/GridRoot/VehicleSelectionController"
	) as VehicleSelectionScript
	var grid_selection := scene.get_node_or_null(
		"SceneRoot/GridRoot/GridSelectionController"
	) as GridSelectionScript
	var move_controller := scene.get_node_or_null(
		"SceneRoot/GridRoot/VehicleMoveController"
	) as VehicleMoveScript
	var grab_drop_controller := scene.get_node_or_null(
		"SceneRoot/GridRoot/VehicleGrabDropController"
	) as GrabDropControllerScript

	_expect_true(lifecycle_ui != null, "Scene 01 should contain top lifecycle controls.")
	_expect_true(run_pause_button != null, "Lifecycle controls should have one run/pause button.")
	_expect_true(speed_button != null, "Lifecycle controls should have a speed button.")
	_expect_true(reset_button != null, "Lifecycle controls should have a reset button.")
	_expect_true(
		vehicle_manager != null
		and vehicle_selection != null
		and grid_selection != null
		and move_controller != null
		and grab_drop_controller != null,
		"Lifecycle integration dependencies should exist."
	)
	if (
		lifecycle_ui == null
		or run_pause_button == null
		or speed_button == null
		or reset_button == null
		or vehicle_manager == null
		or vehicle_selection == null
		or grid_selection == null
		or move_controller == null
		or grab_drop_controller == null
	):
		scene.queue_free()
		await process_frame
		_finish()
		return

	_expect_equal(scene.get_lifecycle_state(), LifecycleStateScript.State.READY, "Scene should start READY.")
	_expect_equal(scene.get_simulation_speed(), 1.0, "Scene should start at 1x.")
	_expect_equal(run_pause_button.text, "▶", "READY should show play icon.")
	_expect_equal(speed_button.text, "1×", "READY should show 1x.")

	var arm := vehicle_manager.get_vehicle_by_id(&"arm_vehicle")
	var transport := vehicle_manager.get_vehicle_by_id(&"transport_vehicle")
	_expect_true(arm != null, "Arm vehicle should exist.")
	_expect_true(transport != null, "Transport vehicle should exist.")
	if arm == null or transport == null:
		scene.queue_free()
		await process_frame
		_finish()
		return
	_expect_true(vehicle_selection.select_vehicle(arm), "Test should select arm vehicle.")

	lifecycle_ui._on_run_pause_pressed()
	_expect_equal(scene.get_lifecycle_state(), LifecycleStateScript.State.RUNNING, "Play should enter RUNNING.")
	_expect_equal(run_pause_button.text, "⏸", "RUNNING should show pause icon.")

	lifecycle_ui._on_run_pause_pressed()
	_expect_equal(scene.get_lifecycle_state(), LifecycleStateScript.State.PAUSED, "Idle pause should enter PAUSED.")
	_expect_false(
		grid_selection.activate_live_target_mode(),
		"PAUSED should reject M-equivalent target mode even while vehicle is Waiting."
	)
	_expect_false(
		grab_drop_controller.rotate_selected_arm(1),
		"PAUSED should reject arm rotation even while vehicle is Waiting."
	)
	lifecycle_ui._on_run_pause_pressed()
	_expect_equal(scene.get_lifecycle_state(), LifecycleStateScript.State.RUNNING, "Idle resume should return RUNNING.")

	_expect_true(
		move_controller.request_selected_vehicle_move(Vector2i(4, 2)),
		"RUNNING should accept a valid MoveTo."
	)

	move_controller._physics_process(0.20)
	var position_before_pause: Vector3 = arm.global_position
	var timer_before_pause: float = scene.timer
	lifecycle_ui._on_run_pause_pressed()
	_expect_equal(scene.get_lifecycle_state(), LifecycleStateScript.State.PAUSED, "Pause should enter PAUSED.")
	_expect_equal(run_pause_button.text, "▶", "PAUSED should show play icon.")
	move_controller._physics_process(1.0)
	scene._process(1.0)
	_expect_vector_approx(arm.global_position, position_before_pause, "Paused vehicle should not advance.")
	_expect_float_approx(scene.timer, timer_before_pause, "Paused scene timer should not advance.")
	_expect_false(
		move_controller.request_selected_vehicle_stop(),
		"PAUSED should reject X-equivalent stop requests."
	)

	lifecycle_ui._on_speed_pressed()
	_expect_equal(scene.get_simulation_speed(), 2.0, "Speed button should cycle 1x to 2x while paused.")
	_expect_equal(speed_button.text, "2×", "Speed label should update while paused.")
	lifecycle_ui._on_run_pause_pressed()
	_expect_equal(scene.get_lifecycle_state(), LifecycleStateScript.State.RUNNING, "Play from PAUSED should resume.")
	move_controller._physics_process(0.20)
	_expect_true(
		arm.global_position.distance_to(position_before_pause) > 0.01,
		"Resumed vehicle should continue from its paused progress."
	)

	lifecycle_ui._on_reset_pressed()
	_expect_equal(scene.get_lifecycle_state(), LifecycleStateScript.State.READY, "Reset should return READY.")
	_expect_equal(scene.get_simulation_speed(), 1.0, "Reset should restore 1x.")
	_expect_equal(run_pause_button.text, "▶", "Reset should restore play icon.")
	_expect_equal(speed_button.text, "1×", "Reset should restore 1x label.")
	_expect_equal(arm.runtime_state.anchor_cell, Vector2i(2, 2), "Reset should restore arm anchor.")
	_expect_false(arm.runtime_state.arm_has_item, "Reset should leave arm empty.")
	_expect_equal(transport.runtime_state.tray_count, 0, "Reset should empty transport tray.")
	_expect_equal(scene.box_count, 3, "Reset should restore standard box to 3/8.")

	_expect_false(
		grid_selection.toggle_live_target_mode(),
		"Unavailable M-equivalent command should remain rejected without selection."
	)
	_expect_false(
		grab_drop_controller.rotate_selected_arm(1),
		"Missing selection should not execute arm rotation."
	)
	_expect_equal(
		scene.get_lifecycle_state(),
		LifecycleStateScript.State.READY,
		"Rejected commands without a selected vehicle should not start lifecycle."
	)

	_expect_true(vehicle_selection.select_vehicle(transport), "Transport should be selectable for invalid arm command coverage.")
	_expect_false(
		grab_drop_controller.rotate_selected_arm(1),
		"Transport should reject arm rotation because it has no grab capability."
	)
	var transport_grab_result := grab_drop_controller.request_selected_grab_drop()
	_expect_equal(
		transport_grab_result.status,
		GrabDropResultScript.Status.NO_CAPABILITY,
		"Transport GrabDrop should reject with NO_CAPABILITY."
	)
	_expect_equal(
		scene.get_lifecycle_state(),
		LifecycleStateScript.State.READY,
		"Rejected A/D/C commands on a non-arm vehicle must not start lifecycle."
	)

	_expect_true(vehicle_selection.select_vehicle(arm), "Arm should be selectable again after invalid transport commands.")
	_expect_true(
		grab_drop_controller.rotate_selected_arm(1),
		"First valid gameplay command from READY should auto-start the scene."
	)
	_expect_equal(
		scene.get_lifecycle_state(),
		LifecycleStateScript.State.RUNNING,
		"Valid READY gameplay command should enter RUNNING."
	)

	_expect_true(scene.set_simulation_speed(4.0), "4x should be accepted before reset event ordering test.")
	scene.pause_scene()
	lifecycle_events.clear()
	scene.reset_scene()
	_expect_equal(
		lifecycle_events,
		[
			{"kind": "speed", "previous": 4.0, "current": 1.0},
			{
				"kind": "state",
				"previous": LifecycleStateScript.State.PAUSED,
				"current": LifecycleStateScript.State.READY,
			},
			{"kind": "reset"},
		],
		"Scene reset should publish speed, state, then reset-completed in a stable order."
	)

	lifecycle_events.clear()
	scene.reset_scene()
	scene.reset_scene()
	_expect_equal(scene.get_lifecycle_state(), LifecycleStateScript.State.READY, "Repeated reset should be idempotent.")
	_expect_equal(scene.get_simulation_speed(), 1.0, "Repeated reset should preserve 1x.")
	_expect_equal(arm.runtime_state.anchor_cell, Vector2i(2, 2), "Repeated reset should preserve arm anchor.")
	_expect_equal(
		lifecycle_events,
		[
			{"kind": "reset"},
			{"kind": "reset"},
		],
		"Each explicit idempotent Reset should publish reset-completed without duplicate state/speed transitions."
	)

	var scene_instance_id: int = scene.get_instance_id()
	var lifecycle_ui_instance_id: int = lifecycle_ui.get_instance_id()
	scene.queue_free()
	await process_frame
	_expect_false(is_instance_id_valid(scene_instance_id), "Freed Scene 01 root should not remain alive.")
	_expect_false(is_instance_id_valid(lifecycle_ui_instance_id), "Freed lifecycle UI should not remain alive.")
	_expect_equal(
		root.get_child_count(),
		baseline_root_child_count,
		"Leaving Scene 01 should restore the root child count without leaked scene nodes."
	)

	var reentered_scene := packed.instantiate() as LifecycleControllerScript
	_expect_true(reentered_scene != null, "Scene 01 should instantiate again after leaving.")
	if reentered_scene != null:
		root.add_child(reentered_scene)
		await process_frame
		_expect_equal(
			reentered_scene.get_lifecycle_state(),
			LifecycleStateScript.State.READY,
			"Re-entered Scene 01 should start READY."
		)
		_expect_equal(
			reentered_scene.get_simulation_speed(),
			1.0,
			"Re-entered Scene 01 should start at 1x."
		)
		_expect_true(
			reentered_scene.get_node_or_null("LifecycleUIRoot") != null,
			"Re-entered Scene 01 should recreate exactly one lifecycle UI root at its canonical path."
		)
		_expect_true(
			reentered_scene.get_node_or_null("SceneRoot/RobotRoot/Scene01VehicleManager") != null,
			"Re-entered Scene 01 should recreate its vehicle manager."
		)
		_expect_equal(
			root.get_child_count(),
			baseline_root_child_count + 1,
			"Re-entering Scene 01 should add exactly one scene root."
		)
		reentered_scene.queue_free()
		await process_frame
		_expect_equal(
			root.get_child_count(),
			baseline_root_child_count,
			"Leaving the re-entered Scene 01 should again restore the root child count."
		)

	_finish()


func _bind_lifecycle_events(scene: LifecycleControllerScript) -> void:
	scene.lifecycle_state_changed.connect(_on_scene_lifecycle_state_changed)
	scene.simulation_speed_changed.connect(_on_scene_simulation_speed_changed)
	scene.lifecycle_reset_completed.connect(_on_scene_lifecycle_reset_completed)


func _on_scene_lifecycle_state_changed(previous_state: int, current_state: int) -> void:
	lifecycle_events.append(
		{"kind": "state", "previous": previous_state, "current": current_state}
	)


func _on_scene_simulation_speed_changed(previous_speed: float, current_speed: float) -> void:
	lifecycle_events.append(
		{"kind": "speed", "previous": previous_speed, "current": current_speed}
	)


func _on_scene_lifecycle_reset_completed() -> void:
	lifecycle_events.append({"kind": "reset"})


func _finish() -> void:
	if failures == 0:
		print("Scene 01 lifecycle smoke tests passed.")
		quit(0)
		return
	push_error("Scene 01 lifecycle smoke tests failed: %d failure(s)." % failures)
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


func _expect_false(value: bool, message: String) -> void:
	if not value:
		return
	failures += 1
	push_error(message)


func _expect_float_approx(actual: float, expected: float, message: String) -> void:
	if is_equal_approx(actual, expected):
		return
	failures += 1
	push_error("%s Expected %.6f, got %.6f." % [message, expected, actual])


func _expect_vector_approx(actual: Vector3, expected: Vector3, message: String) -> void:
	if actual.is_equal_approx(expected):
		return
	failures += 1
	push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])

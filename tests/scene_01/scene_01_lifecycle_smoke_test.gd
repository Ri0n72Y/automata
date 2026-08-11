extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const LifecycleStateScript := preload("res://scripts/scene_01/scene_01_lifecycle_state.gd")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for lifecycle smoke test.")
	if packed == null:
		_finish()
		return

	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame

	var lifecycle_ui := scene.get_node_or_null("LifecycleUIRoot")
	var run_pause_button := scene.get_node_or_null(
		"LifecycleUIRoot/RootControl/Panel/Margin/Controls/RunPauseButton"
	) as Button
	var speed_button := scene.get_node_or_null(
		"LifecycleUIRoot/RootControl/Panel/Margin/Controls/SpeedButton"
	) as Button
	var reset_button := scene.get_node_or_null(
		"LifecycleUIRoot/RootControl/Panel/Margin/Controls/ResetButton"
	) as Button
	var vehicle_manager := scene.get_node_or_null("SceneRoot/RobotRoot/Scene01VehicleManager")
	var vehicle_selection := scene.get_node_or_null("SceneRoot/GridRoot/VehicleSelectionController")
	var move_controller := scene.get_node_or_null("SceneRoot/GridRoot/VehicleMoveController")
	var grab_drop_controller := scene.get_node_or_null("SceneRoot/GridRoot/VehicleGrabDropController")

	_expect_true(lifecycle_ui != null, "Scene 01 should contain top lifecycle controls.")
	_expect_true(run_pause_button != null, "Lifecycle controls should have one run/pause button.")
	_expect_true(speed_button != null, "Lifecycle controls should have a speed button.")
	_expect_true(reset_button != null, "Lifecycle controls should have a reset button.")
	_expect_equal(scene.get_lifecycle_state(), LifecycleStateScript.State.READY, "Scene should start READY.")
	_expect_equal(scene.get_simulation_speed(), 1.0, "Scene should start at 1x.")
	_expect_equal(run_pause_button.text, "▶", "READY should show play icon.")
	_expect_equal(speed_button.text, "1×", "READY should show 1x.")

	var arm = vehicle_manager.get_vehicle_by_id(&"arm_vehicle")
	_expect_true(vehicle_selection.select_vehicle(arm), "Test should select arm vehicle.")

	lifecycle_ui._on_run_pause_pressed()
	_expect_equal(scene.get_lifecycle_state(), LifecycleStateScript.State.RUNNING, "Play should enter RUNNING.")
	_expect_equal(run_pause_button.text, "⏸", "RUNNING should show pause icon.")
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
	_expect_false(
		grab_drop_controller.rotate_selected_arm(1),
		"PAUSED should reject arm rotation commands."
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
	var transport = vehicle_manager.get_vehicle_by_id(&"transport_vehicle")
	_expect_equal(transport.runtime_state.tray_count, 0, "Reset should empty transport tray.")
	_expect_equal(scene.box_count, 3, "Reset should restore standard box to 3/8.")

	_expect_false(
		grab_drop_controller.rotate_selected_arm(1),
		"Missing selection should not execute arm rotation."
	)
	_expect_equal(
		scene.get_lifecycle_state(),
		LifecycleStateScript.State.READY,
		"Rejected command without a selected vehicle should not start lifecycle."
	)
	_expect_true(vehicle_selection.select_vehicle(arm), "Arm should be selectable again after Reset.")
	_expect_true(
		grab_drop_controller.rotate_selected_arm(1),
		"First valid gameplay command from READY should auto-start the scene."
	)
	_expect_equal(
		scene.get_lifecycle_state(),
		LifecycleStateScript.State.RUNNING,
		"Valid READY gameplay command should enter RUNNING."
	)

	lifecycle_ui._on_reset_pressed()
	lifecycle_ui._on_reset_pressed()
	_expect_equal(scene.get_lifecycle_state(), LifecycleStateScript.State.READY, "Repeated reset should be idempotent.")
	_expect_equal(scene.get_simulation_speed(), 1.0, "Repeated reset should preserve 1x.")
	_expect_equal(arm.runtime_state.anchor_cell, Vector2i(2, 2), "Repeated reset should preserve arm anchor.")

	scene.queue_free()
	await process_frame
	_finish()


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

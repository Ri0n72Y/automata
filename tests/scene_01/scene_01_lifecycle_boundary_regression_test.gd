extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const LifecycleControllerScript := preload("res://scripts/scene_01/scene_01_lifecycle_controller.gd")
const LifecycleStateScript := preload("res://scripts/scene_01/scene_01_lifecycle_state.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const VehicleSelectionScript := preload("res://scripts/input/vehicle_selection_controller.gd")
const VehicleMoveScript := preload("res://scripts/input/vehicle_move_controller.gd")
const GridSelectionScript := preload("res://scripts/input/grid_selection_controller.gd")
const GrabDropControllerScript := preload("res://scripts/input/vehicle_grab_drop_controller.gd")

var failures: int = 0
var _scene: LifecycleControllerScript
var _reentrant_action: StringName = &""
var _lifecycle_event_log: Array[String] = []
var _run_preparation_failures: Array[StringName] = []
var _grab_drop_completion_count: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for lifecycle boundary regression tests.")
	if packed == null:
		_finish()
		return

	_scene = packed.instantiate() as LifecycleControllerScript
	_expect_true(_scene != null, "Scene 01 should use the lifecycle controller.")
	if _scene == null:
		_finish()
		return
	_scene.lifecycle_state_changed.connect(_on_lifecycle_state_changed)
	_scene.lifecycle_reset_completed.connect(_on_lifecycle_reset_completed)
	_scene.lifecycle_run_preparation_failed.connect(_on_run_preparation_failed)
	root.add_child(_scene)
	await process_frame

	var manager := _scene.get_node_or_null("SceneRoot/RobotRoot/Scene01VehicleManager") as VehicleManagerScript
	var selection := _scene.get_node_or_null("SceneRoot/GridRoot/VehicleSelectionController") as VehicleSelectionScript
	var move := _scene.get_node_or_null("SceneRoot/GridRoot/VehicleMoveController") as VehicleMoveScript
	var grid_selection := _scene.get_node_or_null("SceneRoot/GridRoot/GridSelectionController") as GridSelectionScript
	var grab_drop := _scene.get_node_or_null("SceneRoot/GridRoot/VehicleGrabDropController") as GrabDropControllerScript
	_expect_true(
		manager != null and selection != null and move != null and grid_selection != null and grab_drop != null,
		"Lifecycle boundary regression tests require all gameplay controllers."
	)
	if manager == null or selection == null or move == null or grid_selection == null or grab_drop == null:
		await _cleanup(_scene)
		_finish()
		return

	var arm := manager.get_vehicle_by_id(&"arm_vehicle")
	var transport := manager.get_vehicle_by_id(&"transport_vehicle")
	_expect_true(arm != null and transport != null, "Lifecycle boundary regression tests require both vehicles.")
	if arm == null or transport == null:
		await _cleanup(_scene)
		_finish()
		return

	_expect_true(_scene.is_scene_initialized(), "A valid Scene 01 should report successful initialization.")
	_test_shared_ui_theme()

	_expect_true(selection.select_vehicle(arm), "Arm should be selectable for reentrant Pause coverage.")
	_lifecycle_event_log.clear()
	_reentrant_action = &"pause"
	_expect_false(
		move.request_selected_vehicle_move(Vector2i(4, 2)),
		"A RUNNING listener that immediately pauses must prevent the initiating MoveTo mutation."
	)
	_expect_equal(
		_scene.get_lifecycle_state(),
		LifecycleStateScript.State.PAUSED,
		"Reentrant Pause should settle in PAUSED before the command boundary returns."
	)
	_expect_true(arm.runtime_state.active_move_command == null, "Reentrant Pause must not create a MoveCommand.")
	_expect_equal(
		_lifecycle_event_log,
		["state:0>1", "state:1>2"],
		"RUNNING observers should finish before the queued PAUSED transition is published."
	)

	_expect_true(_scene.reset_scene(), "Reset should recover after reentrant Pause coverage.")
	_expect_true(selection.select_vehicle(arm), "Arm should be selectable for reentrant Reset coverage.")
	var facing_before_reset_attempt: int = arm.runtime_state.facing
	_lifecycle_event_log.clear()
	_reentrant_action = &"reset"
	_expect_false(
		grab_drop.rotate_selected_arm(1),
		"A RUNNING listener that requests Reset must prevent the initiating rotation mutation."
	)
	_expect_equal(_scene.get_lifecycle_state(), LifecycleStateScript.State.READY, "Reentrant Reset should settle in READY.")
	_expect_equal(arm.runtime_state.facing, facing_before_reset_attempt, "Reentrant Reset must prevent arm rotation.")
	_expect_equal(
		_lifecycle_event_log,
		["state:0>1", "state:1>0", "reset"],
		"Reentrant Reset should publish RUNNING completely, then READY, then reset-completed."
	)

	_expect_true(selection.select_vehicle(arm), "Arm should be selectable for active-move Pause coverage.")
	_scene.run_scene()
	_expect_true(move.request_selected_vehicle_move(Vector2i(4, 2)), "Fixture MoveTo should start before Pause.")
	move._physics_process(0.20)
	_scene._process(0.20)
	var command_before_pause = arm.runtime_state.active_move_command
	_expect_true(command_before_pause != null, "Pause fixture requires an active MoveCommand.")
	if command_before_pause != null:
		var position_before_pause: Vector3 = arm.global_position
		var anchor_before_pause: Vector2i = arm.runtime_state.anchor_cell
		var path_index_before_pause: int = command_before_pause.path_index
		var segment_progress_before_pause: float = arm.get_segment_progress()
		var timer_before_pause: float = _scene.timer
		_scene.pause_scene()
		await _push_key(KEY_X)
		move._physics_process(1.0)
		_scene._process(1.0)
		_expect_true(arm.runtime_state.active_move_command == command_before_pause, "PAUSED X must not replace or stop the active MoveCommand.")
		_expect_equal(command_before_pause.path_index, path_index_before_pause, "Pause must preserve MoveCommand path index.")
		_expect_float_approx(arm.get_segment_progress(), segment_progress_before_pause, "Pause must preserve actor segment progress.")
		_expect_vector_approx(arm.global_position, position_before_pause, "Pause must preserve actor position.")
		_expect_equal(arm.runtime_state.anchor_cell, anchor_before_pause, "Pause must preserve discrete anchor.")
		_expect_float_approx(_scene.timer, timer_before_pause, "Pause must preserve scene timer.")

	_expect_true(_scene.reset_scene(), "Reset should recover after active-move Pause coverage.")
	_expect_true(selection.select_vehicle(arm), "Arm should be selectable for idle PAUSED input coverage.")
	_scene.run_scene()
	_scene.pause_scene()
	var facing_before_paused_inputs: int = arm.runtime_state.facing
	_grab_drop_completion_count = 0
	if not grab_drop.grab_drop_completed.is_connected(_on_grab_drop_completed):
		grab_drop.grab_drop_completed.connect(_on_grab_drop_completed)
	await _push_key(KEY_M)
	_expect_false(grid_selection.is_live_target_mode(), "PAUSED M must not enter move target mode.")
	await _push_key(KEY_A)
	_expect_equal(arm.runtime_state.facing, facing_before_paused_inputs, "PAUSED A must not rotate the arm.")
	await _push_key(KEY_D)
	_expect_equal(arm.runtime_state.facing, facing_before_paused_inputs, "PAUSED D must not rotate the arm.")
	await _push_key(KEY_C)
	_expect_equal(_grab_drop_completion_count, 0, "PAUSED C must be blocked before the GrabDrop domain executes.")

	var reset_count_before := _count_event("reset")
	_expect_true(_scene.reset_scene(), "First repeated Reset should succeed.")
	_expect_true(_scene.reset_scene(), "Second repeated Reset should also succeed.")
	_expect_equal(_scene.get_lifecycle_state(), LifecycleStateScript.State.READY, "Repeated Reset should remain READY.")
	_expect_equal(_scene.get_simulation_speed(), 1.0, "Repeated Reset should remain at 1x.")
	_expect_equal(manager.get_vehicle_count(), 2, "Repeated Reset should preserve exactly two vehicles.")
	_expect_equal(arm.runtime_state.anchor_cell, Vector2i(2, 2), "Repeated Reset should restore arm anchor.")
	_expect_equal(transport.runtime_state.tray_count, 0, "Repeated Reset should keep the transport tray empty.")
	_expect_equal(_scene.box_count, 3, "Repeated Reset should keep the standard box at 3/8.")
	_expect_equal(_count_event("reset"), reset_count_before + 2, "Each explicit repeated Reset should publish one reset-completed event.")

	await _cleanup(_scene)
	_scene = null

	var invalid_scene := packed.instantiate() as LifecycleControllerScript
	_expect_true(invalid_scene != null, "Invalid initialization fixture should instantiate.")
	if invalid_scene != null:
		var invalid_manager := invalid_scene.get_node_or_null("SceneRoot/RobotRoot/Scene01VehicleManager") as VehicleManagerScript
		_expect_true(invalid_manager != null, "Invalid initialization fixture requires the vehicle manager.")
		if invalid_manager != null:
			invalid_manager.arm_start_cell = Vector2i(-1, -1)
		_run_preparation_failures.clear()
		invalid_scene.lifecycle_run_preparation_failed.connect(_on_run_preparation_failed)
		root.add_child(invalid_scene)
		await process_frame
		_expect_false(invalid_scene.is_scene_initialized(), "Broken initial vehicle geometry should leave Scene 01 uninitialized.")
		invalid_scene.run_scene()
		_expect_equal(invalid_scene.get_lifecycle_state(), LifecycleStateScript.State.READY, "Uninitialized Scene 01 must not enter RUNNING.")
		_expect_equal(
			_run_preparation_failures,
			[&"scene_not_initialized"],
			"Attempting to run an uninitialized Scene 01 should expose one stable lifecycle failure reason."
		)
		await _cleanup(invalid_scene)

	_finish()


func _test_shared_ui_theme() -> void:
	var guide_root := _scene.get_node_or_null("UIRoot/RootControl") as Control
	var lifecycle_root := _scene.get_node_or_null("LifecycleUIRoot/RootControl") as Control
	_expect_true(guide_root != null and lifecycle_root != null, "Both Scene 01 UI roots should exist.")
	if guide_root == null or lifecycle_root == null:
		return
	_expect_true(guide_root.theme != null and lifecycle_root.theme != null, "Both Scene 01 UI roots should have an explicit theme.")
	if guide_root.theme == null or lifecycle_root.theme == null:
		return
	_expect_true(guide_root.theme == lifecycle_root.theme, "Manual and lifecycle UI should share one Scene 01 theme resource.")
	_expect_true(
		guide_root.theme.default_font != null and guide_root.theme.default_font.get_class() == "SystemFont",
		"Shared Scene 01 UI theme should use a SystemFont fallback for Chinese text and control symbols."
	)


func _on_lifecycle_state_changed(previous_state: int, current_state: int) -> void:
	_lifecycle_event_log.append("state:%d>%d" % [previous_state, current_state])
	if current_state != LifecycleStateScript.State.RUNNING or _scene == null:
		return
	var action := _reentrant_action
	_reentrant_action = &""
	match action:
		&"pause":
			_scene.pause_scene()
		&"reset":
			_scene.reset_scene()


func _on_lifecycle_reset_completed() -> void:
	_lifecycle_event_log.append("reset")


func _on_run_preparation_failed(reason: StringName) -> void:
	_run_preparation_failures.append(reason)


func _on_grab_drop_completed(_vehicle_id: StringName, _action: int, _status: int) -> void:
	_grab_drop_completion_count += 1


func _count_event(event_name: String) -> int:
	var count := 0
	for event in _lifecycle_event_log:
		if event == event_name:
			count += 1
	return count


func _push_key(keycode: int) -> void:
	root.push_input(_key_event(keycode, true))
	await process_frame
	root.push_input(_key_event(keycode, false))
	await process_frame


func _key_event(keycode: int, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = pressed
	event.keycode = keycode
	return event


func _cleanup(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
		await process_frame


func _finish() -> void:
	if failures == 0:
		print("Scene 01 lifecycle boundary regression tests passed.")
		quit(0)
		return
	push_error("Scene 01 lifecycle boundary regression tests failed: %d failure(s)." % failures)
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
	push_error("%s Expected %f, got %f." % [message, expected, actual])


func _expect_vector_approx(actual: Vector3, expected: Vector3, message: String) -> void:
	if actual.is_equal_approx(expected):
		return
	failures += 1
	push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])

extends SceneTree
const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const TutorialScript := preload("res://scripts/scene_01/scene_01_tutorial.gd")
const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const RunnerScript := preload("res://scripts/scene_01/scene_01_program_runner.gd")
const ManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const RuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const GrabDropResultScript := preload("res://scripts/vehicles/grab_drop_result.gd")
var failures := 0
var scene: Node
var tutorial: TutorialScript
var runner: RunnerScript
var manager: ManagerScript
var arm
var selection: Node
var move_controller: Node
var grab_drop: Node
var object_manager: Node
var capability_label: Label
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load with Tutorial composition.")
	if packed == null:
		_finish()
		return
	scene = packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	_bind_scene()
	if tutorial == null or runner == null or manager == null or selection == null or move_controller == null or grab_drop == null or object_manager == null or capability_label == null:
		await _cleanup()
		_finish()
		return
	_test_compile_projection_refresh()
	await _test_skip_and_manual_catch_up()
	await _test_program_progression()
	await _test_reset_alignment()
	await _cleanup()
	_finish()
func _bind_scene() -> void:
	tutorial = scene.get_node_or_null("SceneRoot/Scene01Tutorial") as TutorialScript
	runner = scene.get_node_or_null("SceneRoot/Scene01ProgramRunner") as RunnerScript
	manager = scene.get_node_or_null("SceneRoot/RobotRoot/Scene01VehicleManager") as ManagerScript
	selection = scene.get_node_or_null("SceneRoot/GridRoot/VehicleSelectionController")
	move_controller = scene.get_node_or_null("SceneRoot/GridRoot/VehicleMoveController")
	grab_drop = scene.get_node_or_null("SceneRoot/GridRoot/VehicleGrabDropController")
	object_manager = scene.get_node_or_null("SceneRoot/ObjectRoot/Scene01ObjectManager")
	capability_label = scene.get_node_or_null("TutorialUIRoot/RootControl/TutorialPanel/Margin/VBox/CapabilityLabel") as Label
	arm = manager.get_vehicle_by_id(ManagerScript.ARM_VEHICLE_ID) if manager != null else null
	_expect_true(tutorial != null and arm != null, "Tutorial owner and Arm vehicle should exist.")
	var tutorial_ui = scene.get_node_or_null("TutorialUIRoot")
	var manual_guide = scene.get_node_or_null("UIRoot/RootControl") as Control
	var tutorial_button = scene.get_node_or_null("UIRoot/RootControl/Panel/Margin/VBox/HeaderRow/TutorialButton") as Button
	_expect_true(tutorial_ui != null and manual_guide != null and tutorial_button != null, "Tutorial and shared Manual Guide presentation should exist.")
	_expect_false(tutorial.has_signal("step_changed"), "Tutorial should expose one presentation notification surface.")
	_expect_false(tutorial.has_signal("visibility_changed"), "Tutorial visibility should use the same presentation notification surface.")
	_expect_true(scene.get_node_or_null("TutorialUIRoot/RootControl/ReopenTutorialButton") == null, "Tutorial UI should not own a second floating reopen entry.")
	if manual_guide != null:
		_expect_false(manual_guide.visible, "Visible Tutorial coaching should hide the overlapping generic Manual Guide presentation.")
func _test_compile_projection_refresh() -> void:
	_expect_true(capability_label.text.contains("首次运行后由装配编译确认"), "Tutorial capability copy should begin without invented compile truth.")
	scene.call("run_scene")
	_expect_true(bool(scene.call("is_gameplay_running")), "Top Run should start Scene 01 through the real lifecycle gate.")
	var text := capability_label.text
	_expect_true(text.contains("编译通过") and text.contains("可移动") and text.contains("可抓取") and text.contains("可承载"), "Lifecycle publication should refresh Tutorial capability copy immediately.")
func _test_skip_and_manual_catch_up() -> void:
	var box = object_manager.get_standard_box()
	var score = scene.get_node("SceneRoot/Scene01ScoreTracker")
	var manual_controls = scene.get_node("UIRoot")
	var manual_guide := scene.get_node("UIRoot/RootControl") as Control
	var tutorial_button := scene.get_node("UIRoot/RootControl/Panel/Margin/VBox/HeaderRow/TutorialButton") as Button
	_expect_equal(tutorial.get_step(), TutorialScript.Step.SELECT_ARM, "Tutorial should start by asking for Arm selection.")
	var box_before: int = int(box.get_current_count())
	var manual_before := float(score.call("get_manual_runtime"))
	tutorial.skip_tutorial()
	_expect_false(tutorial.is_visible(), "Skip should hide coaching.")
	_expect_true(manual_guide.visible, "Skip should restore the generic Manual Guide presentation.")
	_expect_equal(box.get_current_count(), box_before, "Skip must not modify StandardBox truth.")
	_expect_equal(float(score.call("get_manual_runtime")), manual_before, "Skip must not modify Scoring truth.")
	_expect_true(selection.call("select_vehicle", arm), "Arm should be selectable while Tutorial is hidden.")
	_expect_equal(tutorial.get_step(), TutorialScript.Step.MANUAL_PICKUP, "Hidden Tutorial should catch up after Arm selection.")
	_expect_true(move_controller.call("request_selected_vehicle_move", Vector2i(1, 3)), "Manual Tutorial flow should use real MoveTo.")
	await _wait_for_vehicle(arm, Vector2i(1, 3))
	_face_arm(RuntimeStateScript.Facing.WEST)
	var grab_result = grab_drop.call("request_selected_grab_drop")
	_expect_true(grab_result != null and grab_result.status == GrabDropResultScript.Status.ACCEPTED, "Manual pickup should use real GrabDrop.")
	_expect_equal(tutorial.get_step(), TutorialScript.Step.MANUAL_DROP, "Real Arm pickup should advance Tutorial.")
	_expect_true(move_controller.call("request_selected_vehicle_move", Vector2i(14, 3)), "Loaded Arm should move to StandardBox.")
	await _wait_for_vehicle(arm, Vector2i(14, 3))
	_face_arm(RuntimeStateScript.Facing.EAST)
	var drop_result = grab_drop.call("request_selected_grab_drop")
	_expect_true(drop_result != null and drop_result.status == GrabDropResultScript.Status.ACCEPTED, "Manual drop should use real GrabDrop.")
	_expect_equal(tutorial.get_step(), TutorialScript.Step.PROGRAM_RUN, "Real StandardBox increment should advance to Program teaching.")
	manual_controls.call("set_collapsed", false)
	_expect_false(bool(manual_controls.call("is_collapsed")), "Manual Guide should be expandable while Tutorial is hidden.")
	_expect_true(tutorial_button.is_visible_in_tree(), "Expanded Manual Guide should keep the Tutorial reopen entry visible.")
	tutorial_button.pressed.emit()
	_expect_true(tutorial.is_visible(), "Manual Guide Tutorial button should reopen coaching at the caught-up step.")
	_expect_false(manual_guide.visible, "Reopen should return the left presentation slot to Tutorial coaching.")
func _test_program_progression() -> void:
	var pickup_only := ProgramScript.new()
	_append_move(pickup_only, ManagerScript.ARM_VEHICLE_ID, Vector2i(2, 3))
	_append_move(pickup_only, ManagerScript.ARM_VEHICLE_ID, Vector2i(1, 3))
	_append_grab(pickup_only, ManagerScript.ARM_VEHICLE_ID)
	_expect_true(runner.start_program(pickup_only), "Successful pickup-only Program should start.")
	await _drive_program()
	_expect_equal(runner.get_state(), RunnerScript.STATE_COMPLETED, "Pickup-only Program should complete.")
	_expect_equal(tutorial.get_step(), TutorialScript.Step.PROGRAM_RUN, "Move + Grab without StandardBox delivery must not satisfy automatic搬运 teaching.")
	var delivery := ProgramScript.new()
	_append_move(delivery, ManagerScript.ARM_VEHICLE_ID, Vector2i(13, 3))
	_append_move(delivery, ManagerScript.ARM_VEHICLE_ID, Vector2i(14, 3))
	_append_grab(delivery, ManagerScript.ARM_VEHICLE_ID)
	_expect_true(runner.start_program(delivery), "Real automatic box delivery Program should start.")
	await _drive_program()
	_expect_equal(tutorial.get_step(), TutorialScript.Step.MULTI_VEHICLE, "Successful Program-owned StandardBox delivery should advance to multi-vehicle teaching.")
	var multi := _build_delivery_program(true)
	_expect_true(runner.start_program(multi), "Explicit Arm + Transport delivery Program should start.")
	await _drive_program()
	_expect_equal(runner.get_state(), RunnerScript.STATE_COMPLETED, "Explicit multi-vehicle Program should complete.")
	_expect_equal(tutorial.get_step(), TutorialScript.Step.DONE, "One successful delivery Program containing Transport Move should complete Tutorial.")
func _build_delivery_program(include_transport: bool) -> Scene01Program:
	var program := ProgramScript.new()
	_append_move(program, ManagerScript.ARM_VEHICLE_ID, Vector2i(2, 3))
	_append_move(program, ManagerScript.ARM_VEHICLE_ID, Vector2i(1, 3))
	_append_grab(program, ManagerScript.ARM_VEHICLE_ID)
	_append_move(program, ManagerScript.ARM_VEHICLE_ID, Vector2i(13, 3))
	_append_move(program, ManagerScript.ARM_VEHICLE_ID, Vector2i(14, 3))
	_append_grab(program, ManagerScript.ARM_VEHICLE_ID)
	if include_transport:
		_append_move(program, ManagerScript.TRANSPORT_VEHICLE_ID, Vector2i(8, 4))
	return program
func _test_reset_alignment() -> void:
	_expect_true(scene.call("reset_scene_state"), "Lifecycle Reset should remain the only gameplay reset path.")
	await process_frame
	_expect_equal(tutorial.get_step(), TutorialScript.Step.SELECT_ARM, "Reset should return Tutorial progress to the real initial state.")
	_expect_true(tutorial.is_visible(), "Reset should not silently hide an open Tutorial.")
	_expect_equal(selection.call("get_selected_vehicle_id"), &"", "Reset should still own vehicle selection truth.")
	_expect_equal(object_manager.get_standard_box().get_current_count(), 3, "Reset should still own StandardBox truth.")
func _append_move(program: Scene01Program, vehicle_id: StringName, target: Vector2i) -> void:
	var index := program.append_statement(ProgramScript.StatementType.MOVE_TO)
	program.set_statement_vehicle(index, vehicle_id)
	program.set_move_target(index, target)
func _append_grab(program: Scene01Program, vehicle_id: StringName) -> void:
	var index := program.append_statement(ProgramScript.StatementType.GRAB_DROP)
	program.set_statement_vehicle(index, vehicle_id)
func _drive_program() -> void:
	var guard := 0
	while runner.get_state() == RunnerScript.STATE_RUNNING and guard < 4000:
		move_controller._physics_process(0.05)
		await process_frame
		guard += 1
	_expect_true(guard < 4000, "Program should reach a terminal state without hanging.")
func _wait_for_vehicle(vehicle, target: Vector2i) -> void:
	var guard := 0
	while vehicle.runtime_state.motion_state == RuntimeStateScript.MotionState.MOVING and guard < 4000:
		move_controller._physics_process(0.05)
		guard += 1
		if guard % 200 == 0:
			await process_frame
	_expect_equal(vehicle.runtime_state.anchor_cell, target, "Vehicle should reach Tutorial target %s." % str(target))
func _face_arm(target_facing: int) -> void:
	var guard := 0
	while arm.runtime_state.facing != target_facing and guard < 4:
		grab_drop.call("rotate_selected_arm", 1)
		guard += 1
	_expect_equal(arm.runtime_state.facing, target_facing, "Arm should face the Tutorial interaction target.")
func _cleanup() -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
		await process_frame
func _finish() -> void:
	if failures == 0:
		print("Scene 01 Tutorial tests passed.")
		quit(0)
		return
	push_error("Scene 01 Tutorial tests failed: %d failure(s)." % failures)
	quit(1)
func _expect_true(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _expect_false(value: bool, message: String) -> void:
	_expect_true(not value, message)
func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures += 1
		push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])

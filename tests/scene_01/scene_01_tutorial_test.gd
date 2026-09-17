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
	if tutorial == null or runner == null or manager == null or selection == null or move_controller == null or grab_drop == null or object_manager == null:
		await _cleanup()
		_finish()
		return
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
	arm = manager.get_vehicle_by_id(ManagerScript.ARM_VEHICLE_ID) if manager != null else null
	_expect_true(tutorial != null and arm != null, "Tutorial owner and Arm vehicle should exist.")
	var tutorial_ui = scene.get_node_or_null("TutorialUIRoot")
	_expect_true(tutorial_ui != null, "Tutorial coaching UI should be in the production scene.")
	if tutorial_ui != null:
		var tutorial_panel := tutorial_ui.get_node("%TutorialPanel") as Control
		var manual_panel := scene.get_node("UIRoot/RootControl/Panel") as Control
		_expect_false(tutorial_panel.get_global_rect().intersects(manual_panel.get_global_rect()), "Tutorial panel should not cover the manual guide.")


func _test_skip_and_manual_catch_up() -> void:
	var box = object_manager.get_standard_box()
	var score = scene.get_node("SceneRoot/Scene01ScoreTracker")
	_expect_equal(tutorial.get_step(), TutorialScript.Step.SELECT_ARM, "Tutorial should start by asking for Arm selection.")
	var box_before := box.get_current_count()
	var manual_before := float(score.call("get_manual_runtime"))
	tutorial.skip_tutorial()
	_expect_false(tutorial.is_visible(), "Skip should hide coaching.")
	_expect_equal(box.get_current_count(), box_before, "Skip must not modify StandardBox truth.")
	_expect_equal(float(score.call("get_manual_runtime")), manual_before, "Skip must not modify Scoring truth.")
	_expect_true(selection.call("select_vehicle", arm), "Arm should be selectable while Tutorial is hidden.")
	_expect_equal(tutorial.get_step(), TutorialScript.Step.MANUAL_PICKUP, "Hidden Tutorial should catch up after Arm selection.")
	_expect_true(move_controller.call("request_selected_vehicle_move", Vector2i(1, 3)), "Manual Tutorial flow should use the real MoveTo command.")
	await _wait_for_vehicle(arm, Vector2i(1, 3))
	_face_arm(RuntimeStateScript.Facing.WEST)
	var grab_result = grab_drop.call("request_selected_grab_drop")
	_expect_true(grab_result != null and grab_result.status == GrabDropResultScript.Status.ACCEPTED, "Manual Tutorial pickup should use the real GrabDrop command.")
	_expect_equal(tutorial.get_step(), TutorialScript.Step.MANUAL_DROP, "Real Arm pickup should advance Tutorial.")
	_expect_true(move_controller.call("request_selected_vehicle_move", Vector2i(14, 3)), "Loaded Arm should move to StandardBox through the real controller.")
	await _wait_for_vehicle(arm, Vector2i(14, 3))
	_face_arm(RuntimeStateScript.Facing.EAST)
	var drop_result = grab_drop.call("request_selected_grab_drop")
	_expect_true(drop_result != null and drop_result.status == GrabDropResultScript.Status.ACCEPTED, "Manual Tutorial drop should use the real GrabDrop command.")
	_expect_equal(tutorial.get_step(), TutorialScript.Step.PROGRAM_RUN, "Real StandardBox increment should advance to Program teaching.")
	tutorial.reopen_tutorial()
	_expect_true(tutorial.is_visible(), "Reopen should show coaching at the caught-up step.")
	var capability_text := tutorial.get_capability_summary()
	_expect_true(capability_text.contains("可移动") and capability_text.contains("可抓取") and capability_text.contains("可承载"), "Tutorial capability copy should project formal CompileGate results after Run starts.")


func _test_program_progression() -> void:
	var basic := ProgramScript.new()
	_append_move(basic, ManagerScript.ARM_VEHICLE_ID, Vector2i(1, 3))
	_append_grab(basic, ManagerScript.ARM_VEHICLE_ID)
	_expect_true(runner.start_program(basic), "Basic Arm Program should start from the Tutorial step.")
	await _drive_program()
	_expect_equal(runner.get_state(), RunnerScript.STATE_COMPLETED, "Basic Arm Program should complete.")
	_expect_equal(tutorial.get_step(), TutorialScript.Step.MULTI_VEHICLE, "Successful Arm MoveTo + GrabDrop should advance to multi-vehicle teaching.")
	var multi := ProgramScript.new()
	_append_move(multi, ManagerScript.ARM_VEHICLE_ID, Vector2i(14, 3))
	_append_grab(multi, ManagerScript.ARM_VEHICLE_ID)
	_append_move(multi, ManagerScript.TRANSPORT_VEHICLE_ID, Vector2i(8, 4))
	_expect_true(runner.start_program(multi), "Explicit Arm + Transport Program should start.")
	await _drive_program()
	_expect_equal(runner.get_state(), RunnerScript.STATE_COMPLETED, "Explicit multi-vehicle Program should complete.")
	_expect_equal(tutorial.get_step(), TutorialScript.Step.DONE, "One successful Program containing Arm flow + Transport Move should complete Tutorial.")


func _test_reset_alignment() -> void:
	_expect_true(scene.call("reset_scene_state"), "Lifecycle Reset should remain the only gameplay reset path.")
	await process_frame
	_expect_equal(tutorial.get_step(), TutorialScript.Step.SELECT_ARM, "Reset should return Tutorial presentation progress to the real initial state.")
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

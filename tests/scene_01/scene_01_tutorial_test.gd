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
var progress_label: Label
var previous_button: Button
var next_button: Button
var skip_button: Button

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
	if tutorial == null or runner == null or manager == null or arm == null:
		await _cleanup()
		_finish()
		return
	_test_navigation_and_compile_projection()
	await _test_event_driven_manual_progression()
	await _test_program_progression()
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
	progress_label = scene.get_node_or_null("TutorialUIRoot/RootControl/TutorialPanel/Margin/VBox/Header/ProgressLabel") as Label
	previous_button = scene.get_node_or_null("TutorialUIRoot/RootControl/TutorialPanel/Margin/VBox/ButtonRow/PreviousButton") as Button
	next_button = scene.get_node_or_null("TutorialUIRoot/RootControl/TutorialPanel/Margin/VBox/ButtonRow/NextButton") as Button
	skip_button = scene.get_node_or_null("TutorialUIRoot/RootControl/TutorialPanel/Margin/VBox/ButtonRow/SkipButton") as Button
	arm = manager.get_vehicle_by_id(ManagerScript.ARM_VEHICLE_ID) if manager != null else null
	_expect_true(tutorial != null and arm != null and progress_label != null and previous_button != null and next_button != null and skip_button != null, "Tutorial owner and navigation controls should exist.")

func _test_navigation_and_compile_projection() -> void:
	_expect_equal(tutorial.get_step(), TutorialScript.Step.SELECT_ARM, "Tutorial view should start at step 1.")
	_expect_equal(tutorial.get_progress_step(), TutorialScript.Step.SELECT_ARM, "Tutorial progress should start locked at step 1.")
	_expect_true(previous_button.disabled, "Previous should be disabled on first step.")
	_expect_true(next_button.disabled, "Next should be disabled until a real action unlocks another step.")
	next_button.pressed.emit()
	_expect_equal(tutorial.get_step(), TutorialScript.Step.SELECT_ARM, "Next must not unlock Tutorial progress.")
	_expect_true(capability_label.text.contains("首次运行后确认"), "Capability copy should begin without invented compile truth.")
	scene.call("run_scene")
	var text := capability_label.text
	_expect_true(text.contains("编译通过") and text.contains("可移动") and text.contains("可抓取") and text.contains("可承载"), "Lifecycle publication should refresh Tutorial capability copy.")

func _test_event_driven_manual_progression() -> void:
	var manual_guide := scene.get_node("UIRoot/RootControl") as Control
	tutorial.skip_tutorial()
	_expect_false(tutorial.is_visible(), "Skip should only hide Tutorial presentation.")
	_expect_true(manual_guide.visible, "Skip should restore Manual Guide.")
	_expect_true(selection.call("select_vehicle", arm), "Arm selection should use the real selection owner.")
	_expect_equal(tutorial.get_progress_step(), TutorialScript.Step.MANUAL_PICKUP, "Arm selection event should unlock exactly one expected step.")
	_expect_equal(tutorial.get_step(), TutorialScript.Step.MANUAL_PICKUP, "View should follow progress while the player is reading the frontier.")
	_expect_true(move_controller.call("request_selected_vehicle_move", Vector2i(1, 3)), "Manual flow should use real MoveTo.")
	await _wait_for_vehicle(arm, Vector2i(1, 3))
	_face_arm(RuntimeStateScript.Facing.WEST)
	var grab_result = grab_drop.call("request_selected_grab_drop")
	_expect_true(grab_result != null and grab_result.status == GrabDropResultScript.Status.ACCEPTED, "Manual pickup should use real GrabDrop.")
	_expect_equal(tutorial.get_progress_step(), TutorialScript.Step.MANUAL_DROP, "Pickup event should unlock Manual Drop.")
	_expect_equal(tutorial.get_step(), TutorialScript.Step.MANUAL_DROP, "View should follow the newly unlocked Manual Drop page.")
	tutorial.previous_step()
	_expect_equal(tutorial.get_step(), TutorialScript.Step.MANUAL_PICKUP, "Previous should allow reviewing an earlier page.")
	_expect_equal(tutorial.get_progress_step(), TutorialScript.Step.MANUAL_DROP, "Previous must not roll back gameplay progress.")
	tutorial.reopen_tutorial()
	_expect_equal(tutorial.get_step(), TutorialScript.Step.MANUAL_PICKUP, "Reopen must preserve the review page without inferring gameplay state.")
	_expect_equal(tutorial.get_progress_step(), TutorialScript.Step.MANUAL_DROP, "Reopen must preserve real progress.")
	next_button.pressed.emit()
	_expect_equal(tutorial.get_step(), TutorialScript.Step.MANUAL_DROP, "Next should browse only up to the unlocked progress frontier.")
	_expect_true(move_controller.call("request_selected_vehicle_move", Vector2i(14, 3)), "Loaded Arm should move to StandardBox.")
	await _wait_for_vehicle(arm, Vector2i(14, 3))
	_face_arm(RuntimeStateScript.Facing.EAST)
	var box = object_manager.get_standard_box()
	var before := int(box.get_current_count())
	var drop_result = grab_drop.call("request_selected_grab_drop")
	_expect_true(drop_result != null and drop_result.status == GrabDropResultScript.Status.ACCEPTED, "Manual drop should use real GrabDrop.")
	_expect_equal(box.get_current_count(), before + 1, "Fixture should produce the actual StandardBox +1 action.")
	_expect_equal(tutorial.get_progress_step(), TutorialScript.Step.PROGRAM_RUN, "StandardBox +1 event should unlock Program teaching.")
	_expect_equal(tutorial.get_step(), TutorialScript.Step.PROGRAM_RUN, "View should follow Program teaching at the frontier.")
	tutorial.previous_step()
	_expect_equal(tutorial.get_step(), TutorialScript.Step.MANUAL_DROP, "Player should be able to review Manual Drop after Program is unlocked.")
	_expect_equal(tutorial.get_progress_step(), TutorialScript.Step.PROGRAM_RUN, "Review navigation must not change Program progress.")
	_expect_true(scene.call("reset_scene_state"), "Lifecycle Reset should remain the gameplay reset path.")
	await process_frame
	_expect_equal(tutorial.get_step(), TutorialScript.Step.MANUAL_DROP, "Reset must preserve an older Tutorial review page.")
	_expect_equal(tutorial.get_progress_step(), TutorialScript.Step.PROGRAM_RUN, "Reset must preserve the independently unlocked Tutorial progress.")
	_expect_true(tutorial.is_visible(), "Reset must preserve Tutorial visibility.")
	_expect_equal(object_manager.get_standard_box().get_current_count(), 3, "Reset should still restore gameplay truth independently.")
	next_button.pressed.emit()
	_expect_equal(tutorial.get_step(), TutorialScript.Step.PROGRAM_RUN, "Next should return to the unlocked Program frontier after Reset.")

func _test_program_progression() -> void:
	var pickup_only := ProgramScript.new()
	_append_move(pickup_only, ManagerScript.ARM_VEHICLE_ID, Vector2i(2, 3))
	_append_move(pickup_only, ManagerScript.ARM_VEHICLE_ID, Vector2i(1, 3))
	_append_face(pickup_only, ManagerScript.ARM_VEHICLE_ID, RuntimeStateScript.Facing.WEST)
	_append_grab(pickup_only, ManagerScript.ARM_VEHICLE_ID)
	_expect_true(runner.start_program(pickup_only), "Pickup-only Program should start with explicit Face.")
	await _drive_program()
	_expect_equal(tutorial.get_step(), TutorialScript.Step.PROGRAM_RUN, "Move + Face + Grab without box delivery must not advance Program teaching.")
	_expect_true(scene.call("reset_scene_state"), "Reset should prepare a clean delivery fixture without changing Tutorial step.")
	await process_frame
	var delivery := _build_delivery_program(false)
	_expect_true(runner.start_program(delivery), "Face-enabled automatic delivery should start.")
	await _drive_program()
	_expect_equal(tutorial.get_progress_step(), TutorialScript.Step.MULTI_VEHICLE, "Program-owned StandardBox delivery should unlock multi-vehicle teaching.")
	_expect_equal(tutorial.get_step(), TutorialScript.Step.MULTI_VEHICLE, "View should follow multi-vehicle teaching at the frontier.")
	tutorial.previous_step()
	_expect_equal(tutorial.get_step(), TutorialScript.Step.PROGRAM_RUN, "Previous should browse back without changing multi-vehicle progress.")
	_expect_equal(tutorial.get_progress_step(), TutorialScript.Step.MULTI_VEHICLE, "Browsing back after Program success must keep multi-vehicle progress.")
	var reviewed_multi := _build_delivery_program(true)
	_expect_true(runner.start_program(reviewed_multi), "Successful multi-vehicle Program should still count while an older Tutorial page is being viewed.")
	await _drive_program()
	_expect_equal(tutorial.get_progress_step(), TutorialScript.Step.DONE, "Program completion must advance real progress independently of the viewed page.")
	_expect_equal(tutorial.get_step(), TutorialScript.Step.PROGRAM_RUN, "Progress events should not yank the player away from an older review page.")
	_expect_equal(progress_label.text, "步骤 4 / 5", "Completed progress while reviewing Program should still label the viewed page.")
	_expect_equal(skip_button.text, "跳过教学", "Completed progress while reviewing an older page should keep page-local navigation copy.")
	next_button.pressed.emit()
	_expect_equal(tutorial.get_step(), TutorialScript.Step.MULTI_VEHICLE, "Next should browse forward through already unlocked pages.")
	next_button.pressed.emit()
	_expect_equal(tutorial.get_step(), TutorialScript.Step.DONE, "Next should reach DONE only after DONE was unlocked by gameplay.")
	_expect_equal(progress_label.text, "完成", "DONE view should switch the Tutorial page label to completion.")
	_expect_equal(skip_button.text, "关闭教学", "DONE view should expose completion-specific close copy.")
	_expect_true(scene.call("reset_scene_state"), "Reset should preserve completed Tutorial state.")
	await process_frame
	_expect_equal(tutorial.get_progress_step(), TutorialScript.Step.DONE, "Reset must preserve completed progress.")
	return

func _build_delivery_program(include_transport: bool) -> Scene01Program:
	var program := ProgramScript.new()
	_append_move(program, ManagerScript.ARM_VEHICLE_ID, Vector2i(2, 3))
	_append_move(program, ManagerScript.ARM_VEHICLE_ID, Vector2i(1, 3))
	_append_face(program, ManagerScript.ARM_VEHICLE_ID, RuntimeStateScript.Facing.WEST)
	_append_grab(program, ManagerScript.ARM_VEHICLE_ID)
	_append_move(program, ManagerScript.ARM_VEHICLE_ID, Vector2i(13, 3))
	_append_move(program, ManagerScript.ARM_VEHICLE_ID, Vector2i(14, 3))
	_append_face(program, ManagerScript.ARM_VEHICLE_ID, RuntimeStateScript.Facing.EAST)
	_append_grab(program, ManagerScript.ARM_VEHICLE_ID)
	if include_transport:
		_append_move(program, ManagerScript.TRANSPORT_VEHICLE_ID, Vector2i(8, 4))
	return program

func _append_move(program: Scene01Program, vehicle_id: StringName, target: Vector2i) -> void:
	var index := program.append_statement(ProgramScript.StatementType.MOVE_TO)
	program.set_statement_vehicle(index, vehicle_id)
	program.set_move_target(index, target)
func _append_face(program: Scene01Program, vehicle_id: StringName, facing: int) -> void:
	var index := program.append_statement(ProgramScript.StatementType.FACE)
	program.set_statement_vehicle(index, vehicle_id)
	program.set_facing(index, facing)
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

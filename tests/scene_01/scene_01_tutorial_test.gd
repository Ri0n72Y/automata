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
var goal_label: Label
var next_button: Button


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
	if tutorial == null or runner == null or arm == null:
		await _cleanup()
		_finish()
		return
	await _test_independent_goals()
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
	goal_label = scene.get_node_or_null("TutorialUIRoot/RootControl/TutorialPanel/Margin/VBox/GoalLabel") as Label
	next_button = scene.get_node_or_null("TutorialUIRoot/RootControl/TutorialPanel/Margin/VBox/ButtonRow/NextButton") as Button
	arm = manager.get_vehicle_by_id(ManagerScript.ARM_VEHICLE_ID) if manager != null else null
	_expect_true(tutorial != null and runner != null and arm != null and goal_label != null and next_button != null, "Tutorial owner and minimal presentation controls should exist.")


func _test_independent_goals() -> void:
	_expect_equal(tutorial.get_completed_goal_count(), 0, "Tutorial should start with zero completed goals.")
	_expect_true(goal_label.text.contains("0/1") and goal_label.text.contains("3/8"), "Tutorial should expose both page goal and current scene goal.")
	_expect_true(bool(scene.call("set_simulation_speed", 4.0)), "Tutorial fixture should use the existing lifecycle speed control.")

	# Pages are help/navigation, not an unlock chain.
	for expected in [
		TutorialScript.Step.MANUAL_PICKUP,
		TutorialScript.Step.MANUAL_DROP,
		TutorialScript.Step.PROGRAM_RUN,
		TutorialScript.Step.MULTI_VEHICLE,
	]:
		next_button.pressed.emit()
		_expect_equal(tutorial.get_step(), expected, "Next should freely browse all five teaching pages.")
	_expect_true(next_button.disabled, "Completion page should remain locked until all five independent goals are satisfied.")

	# Complete the automation goals first; manual goals must not be prerequisites.
	var automated := _build_delivery_program(true)
	_expect_true(runner.start_program(automated), "Multi-vehicle delivery should start before any manual Tutorial goal.")
	await _drive_program()
	_expect_true(tutorial.is_goal_complete(TutorialScript.Step.PROGRAM_RUN), "Program delivery should independently complete the automation goal.")
	_expect_true(tutorial.is_goal_complete(TutorialScript.Step.MULTI_VEHICLE), "The same successful run should independently complete the multi-vehicle goal.")
	_expect_equal(tutorial.get_completed_goal_count(), 2, "Only the two automation goals should be complete so far.")

	_expect_true(scene.call("reset_scene_state"), "Reset should restore gameplay without erasing Tutorial goal history.")
	await process_frame
	_expect_equal(tutorial.get_step(), TutorialScript.Step.MULTI_VEHICLE, "Reset should preserve the currently viewed teaching page.")
	_expect_equal(tutorial.get_completed_goal_count(), 2, "Reset should preserve completed Tutorial goals.")
	_expect_true(goal_label.text.contains("3/8"), "Scene goal display should return to the reset StandardBox count.")

	# Complete the three manual goals afterwards.
	_expect_true(selection.call("select_vehicle", arm), "Arm selection should use the real selection owner.")
	_expect_true(tutorial.is_goal_complete(TutorialScript.Step.SELECT_ARM), "Arm selection should independently complete its goal.")
	_expect_true(move_controller.call("request_selected_vehicle_move", Vector2i(1, 3)), "Manual pickup should use real MoveTo.")
	await _wait_for_vehicle(arm, Vector2i(1, 3))
	await _turn_arm_to(RuntimeStateScript.Facing.WEST)
	var grab_result = grab_drop.call("request_selected_grab_drop")
	_expect_true(grab_result != null and grab_result.status == GrabDropResultScript.Status.ACCEPTED, "Manual pickup should use real GrabDrop.")
	_expect_true(tutorial.is_goal_complete(TutorialScript.Step.MANUAL_PICKUP), "Manual pickup should independently complete its goal.")

	_expect_true(move_controller.call("request_selected_vehicle_move", Vector2i(14, 3)), "Loaded Arm should move to StandardBox.")
	await _wait_for_vehicle(arm, Vector2i(14, 3))
	await _turn_arm_to(RuntimeStateScript.Facing.EAST)
	var drop_result = grab_drop.call("request_selected_grab_drop")
	_expect_true(drop_result != null and drop_result.status == GrabDropResultScript.Status.ACCEPTED, "Manual drop should use real GrabDrop.")
	_expect_true(tutorial.is_goal_complete(TutorialScript.Step.MANUAL_DROP), "StandardBox +1 should independently complete the manual packing goal.")
	_expect_equal(tutorial.get_completed_goal_count(), 5, "All independent Tutorial goals should now be complete.")
	_expect_true(goal_label.text.contains("1/1") and goal_label.text.contains("4/8"), "Goal copy should show completion and current StandardBox progress.")

	_expect_false(next_button.disabled, "Completion page should unlock at 5/5.")
	next_button.pressed.emit()
	_expect_equal(tutorial.get_step(), TutorialScript.Step.DONE, "DONE is a presentation page unlocked by 5/5 goals.")

	# Skip remains an allowed player choice and does not mutate task truth.
	tutorial.skip_tutorial()
	_expect_false(tutorial.is_visible(), "Skip should hide Tutorial presentation.")
	tutorial.reopen_tutorial()
	_expect_true(tutorial.is_visible(), "Tutorial can be reopened without changing goals.")
	_expect_equal(tutorial.get_completed_goal_count(), 5, "Skip/reopen must preserve completed goals.")


func _build_delivery_program(include_transport: bool) -> Scene01Program:
	var program := ProgramScript.new()
	_append_move(program, ManagerScript.ARM_VEHICLE_ID, Vector2i(2, 3))
	_append_move(program, ManagerScript.ARM_VEHICLE_ID, Vector2i(1, 3))
	_append_rotate(program, ManagerScript.ARM_VEHICLE_ID, 1)
	_append_rotate(program, ManagerScript.ARM_VEHICLE_ID, 1)
	_append_grab(program, ManagerScript.ARM_VEHICLE_ID)
	_append_move(program, ManagerScript.ARM_VEHICLE_ID, Vector2i(13, 3))
	_append_move(program, ManagerScript.ARM_VEHICLE_ID, Vector2i(14, 3))
	_append_rotate(program, ManagerScript.ARM_VEHICLE_ID, 1)
	_append_rotate(program, ManagerScript.ARM_VEHICLE_ID, 1)
	_append_grab(program, ManagerScript.ARM_VEHICLE_ID)
	if include_transport:
		_append_move(program, ManagerScript.TRANSPORT_VEHICLE_ID, Vector2i(8, 4))
	return program


func _append_move(program: Scene01Program, vehicle_id: StringName, target: Vector2i) -> void:
	var index := program.append_statement(ProgramScript.StatementType.MOVE_TO)
	program.set_statement_vehicle(index, vehicle_id)
	program.set_move_target(index, target)


func _append_rotate(program: Scene01Program, vehicle_id: StringName, direction: int) -> void:
	var index := program.append_statement(ProgramScript.StatementType.ROTATE)
	program.set_statement_vehicle(index, vehicle_id)
	program.set_turn_direction(index, direction)


func _append_grab(program: Scene01Program, vehicle_id: StringName) -> void:
	var index := program.append_statement(ProgramScript.StatementType.GRAB_DROP)
	program.set_statement_vehicle(index, vehicle_id)


func _drive_program() -> void:
	var frames := 0
	while runner.get_state() == RunnerScript.STATE_RUNNING and frames < 2400:
		move_controller._physics_process(0.05)
		grab_drop._physics_process(0.05)
		await process_frame
		frames += 1
	_expect_true(frames < 2400, "Program should reach a terminal state without hanging.")
	_expect_equal(
		runner.get_state(),
		RunnerScript.STATE_COMPLETED,
		"Tutorial Program fixture should complete successfully; last error: %s." % String(runner.get_last_error())
	)


func _wait_for_vehicle(vehicle, target: Vector2i) -> void:
	var frames := 0
	while vehicle.runtime_state.anchor_cell != target and frames < 1200:
		move_controller._physics_process(0.05)
		if frames % 20 == 0:
			await process_frame
		frames += 1
	_expect_true(frames < 1200, "Vehicle should reach Tutorial target without hanging.")
	_expect_equal(vehicle.runtime_state.anchor_cell, target, "Vehicle should reach Tutorial target %s." % str(target))


func _turn_arm_to(target_facing: int) -> void:
	var turns := 0
	while arm.runtime_state.facing != target_facing and turns < 4:
		_expect_true(bool(grab_drop.call("rotate_selected_arm", 1)), "Manual facing should use the shared clockwise turn owner.")
		var frames := 0
		while arm.is_turning() and frames < 120:
			grab_drop._physics_process(0.05)
			await process_frame
			frames += 1
		_expect_true(frames < 120, "Manual turn animation should complete.")
		turns += 1
	_expect_equal(arm.runtime_state.facing, target_facing, "Arm should face the interaction target.")


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

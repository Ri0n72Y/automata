extends SceneTree

const TutorialScript := preload("res://scripts/scene_01/scene_01_tutorial.gd")
const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const RunnerScript := preload("res://scripts/scene_01/scene_01_program_runner.gd")
const ManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")

var failures := 0


func _init() -> void:
	_test_goal_state_machine()
	_finish()


func _test_goal_state_machine() -> void:
	var tutorial := TutorialScript.new()
	var runner := RunnerScript.new()
	tutorial.set("_runner", runner)

	_expect_equal(tutorial.get_step(), TutorialScript.Step.SELECT_ARM, "Tutorial should start on Select Arm.")
	_expect_equal(tutorial.get_completed_goal_count(), 0, "Tutorial should start with no completed goals.")

	for expected in [
		TutorialScript.Step.MANUAL_PICKUP,
		TutorialScript.Step.MANUAL_DROP,
		TutorialScript.Step.PROGRAM_RUN,
		TutorialScript.Step.MULTI_VEHICLE,
	]:
		tutorial.next_step()
		_expect_equal(tutorial.get_step(), expected, "Teaching pages should be freely navigable.")

	tutorial.next_step()
	_expect_equal(tutorial.get_step(), TutorialScript.Step.MULTI_VEHICLE, "DONE should stay locked before 5/5 goals.")

	tutorial.call("_on_selection_changed", ManagerScript.ARM_VEHICLE_ID, true)
	_expect_true(tutorial.is_goal_complete(TutorialScript.Step.SELECT_ARM), "Selecting Arm should complete Select Arm.")

	runner.set("_state", RunnerScript.STATE_IDLE)
	tutorial.call("_on_arm_has_item_changed", false, true)
	_expect_true(tutorial.is_goal_complete(TutorialScript.Step.MANUAL_PICKUP), "Manual carry should complete pickup.")
	tutorial.call("_on_standard_box_count_changed", 3, 4)
	_expect_true(tutorial.is_goal_complete(TutorialScript.Step.MANUAL_DROP), "Manual box increment should complete drop.")

	runner.set("_state", RunnerScript.STATE_RUNNING)
	tutorial.call("_on_program_started")
	tutorial.call("_on_program_command_started", 0, ProgramScript.StatementType.MOVE_TO, ManagerScript.ARM_VEHICLE_ID)
	tutorial.call("_on_program_command_started", 1, ProgramScript.StatementType.GRAB_DROP, ManagerScript.ARM_VEHICLE_ID)
	tutorial.call("_on_standard_box_count_changed", 4, 5)
	tutorial.call("_on_program_command_started", 2, ProgramScript.StatementType.MOVE_TO, ManagerScript.TRANSPORT_VEHICLE_ID)
	tutorial.call("_on_program_completed")

	_expect_true(tutorial.is_goal_complete(TutorialScript.Step.PROGRAM_RUN), "Arm delivery Program should complete Program goal.")
	_expect_true(tutorial.is_goal_complete(TutorialScript.Step.MULTI_VEHICLE), "Transport participation should complete multi-vehicle goal.")
	_expect_equal(tutorial.get_completed_goal_count(), 5, "Five independent goals should complete exactly once.")
	_expect_true(tutorial.are_all_goals_complete(), "All goals should report complete.")

	tutorial.next_step()
	_expect_equal(tutorial.get_step(), TutorialScript.Step.DONE, "DONE should unlock at 5/5.")

	tutorial.skip_tutorial()
	_expect_false(tutorial.is_visible(), "Skip should hide Tutorial presentation.")
	tutorial.reopen_tutorial()
	_expect_true(tutorial.is_visible(), "Tutorial should reopen without changing goal truth.")
	_expect_equal(tutorial.get_completed_goal_count(), 5, "Presentation visibility must not mutate goals.")

	tutorial.free()
	runner.free()


func _finish() -> void:
	if failures == 0:
		print("Scene 01 Tutorial owner contract tests passed.")
		quit(0)
		return
	push_error("Scene 01 Tutorial owner contract tests failed: %d failure(s)." % failures)
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

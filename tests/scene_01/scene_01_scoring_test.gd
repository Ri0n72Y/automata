extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const ContractTestScript := preload("res://tests/support/contract_test.gd")
const ScoreTrackerScript := preload("res://scripts/scene_01/scene_01_score_tracker.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const SelectionScript := preload("res://scripts/input/vehicle_selection_controller.gd")
const MoveScript := preload("res://scripts/scene_01/scene_01_lifecycle_vehicle_move_controller.gd")
const ProgramRunnerScript := preload("res://scripts/scene_01/scene_01_program_runner.gd")
const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const AssemblyAdapterScript := preload("res://scripts/scene_01/scene_01_assembly_definition_adapter.gd")
const StandardBlockScript := preload("res://scripts/objects/standard_block.gd")

var test := ContractTestScript.new()
var observed_program_completion_time := -1.0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	test.expect_true(packed != null, "Scene 01 should load for scoring test.")
	if packed == null:
		test.finish(self, "Scene 01 scoring tests")
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame

	var score := scene.get_node("SceneRoot/Scene01ScoreTracker") as ScoreTrackerScript
	var manager := scene.get_node("SceneRoot/RobotRoot/Scene01VehicleManager") as VehicleManagerScript
	var selection := scene.get_node("SceneRoot/GridRoot/VehicleSelectionController") as SelectionScript
	var move := scene.get_node("SceneRoot/GridRoot/VehicleMoveController") as MoveScript
	var grab_drop = scene.get_node("SceneRoot/GridRoot/VehicleGrabDropController")
	var runner := scene.get_node("SceneRoot/Scene01ProgramRunner") as ProgramRunnerScript
	var box = scene.get_node("SceneRoot/ObjectRoot/Scene01ObjectManager").get_standard_box()
	var score_label := scene.get_node("HUDRoot/RootControl/CompletionPanel/Margin/VBox/ScorePlaceholder") as Label
	var arm = manager.get_vehicle_by_id(VehicleManagerScript.ARM_VEHICLE_ID)
	var transport = manager.get_vehicle_by_id(VehicleManagerScript.TRANSPORT_VEHICLE_ID)
	var transport_origin: Vector2i = transport.runtime_state.anchor_cell
	test.expect_true(score != null and arm != null and transport != null, "Scoring production wiring should exist.")

	test.expect_false(score.has_component_count(), "Component count should be unavailable before Run.")
	scene.call("run_scene")
	var expected_components := 0
	var adapter := AssemblyAdapterScript.new()
	for vehicle_node in manager.get_vehicles():
		var definition = adapter.build_definition(vehicle_node)
		test.expect_true(definition != null, "Participating vehicle should have an AssemblyDefinition.")
		if definition != null:
			expected_components += definition.get_components().size()
	test.expect_true(score.has_component_count(), "Run should capture participating component count.")
	test.expect_equal(score.get_component_count(), expected_components, "Score should count formal assembly components.")

	test.expect_true(selection.select_vehicle(arm), "Arm should be selectable for manual runtime.")
	test.expect_true(move.request_selected_vehicle_move(Vector2i(3, 2)), "Manual MoveTo should start.")
	scene.timer = 2.0
	test.expect_true(move.request_selected_vehicle_stop(), "Manual Stop should finish the control segment.")
	test.expect_float_approx(score.get_manual_runtime(), 2.0, "Manual runtime should use Mission timer duration.")

	var program := ProgramScript.new()
	var program_move := program.append_statement(ProgramScript.StatementType.MOVE_TO)
	program.set_statement_vehicle(program_move, VehicleManagerScript.TRANSPORT_VEHICLE_ID)
	program.set_move_target(program_move, Vector2i(8, 4))
	test.expect_true(runner.start_program(program), "Transport Program should enter automated runtime.")
	await process_frame
	test.expect_equal(runner.get_state(), ProgramRunnerScript.STATE_RUNNING, "Program must really be running before takeover.")
	scene.timer = 2.0
	test.expect_true(move.request_selected_vehicle_move(Vector2i(4, 2)), "Player takeover should remain available while Program runs.")
	scene.timer = 4.0
	test.expect_true(move.request_selected_vehicle_stop(), "Player takeover should stop through the shared controller.")
	test.expect_float_approx(score.get_manual_runtime(), 4.0, "Takeover must count as manual runtime.")
	test.expect_float_approx(score.get_automated_runtime(), 0.0, "Takeover time must not count as automated runtime.")
	scene.timer = 5.0
	scene.call("pause_scene")
	test.expect_float_approx(score.get_automated_runtime(), 1.0, "Automation should resume after takeover ends.")
	test.expect_float_approx(score.get_automation_rate(), 0.2, "Takeover should reduce runtime-based automation ratio.")
	scene.call("resume_scene")

	var frames := 0
	while runner.get_state() == ProgramRunnerScript.STATE_RUNNING and frames < 240:
		await physics_frame
		frames += 1
	test.expect_equal(runner.get_state(), ProgramRunnerScript.STATE_COMPLETED, "Real Transport Program should complete after takeover.")
	var program_end_time := score.get_elapsed_time()
	var program_automated := score.get_automated_runtime()
	test.expect_true(program_automated > 1.0, "Automation should continue accruing after takeover until Program completion.")
	test.expect_true(absf(program_automated - (program_end_time - 4.0)) < 0.05, "Automation runtime should match real post-takeover scheduling within one-frame tolerance.")

	while box.get_current_count() < box.get_capacity() - 1:
		test.expect_true(box.put_item(StandardBlockScript.create()).is_success(), "Fixture should prepare box at 7/8.")
	arm.runtime_state.anchor_cell = Vector2i(14, 3)
	arm.sync_from_state()
	test.expect_true(arm.runtime_state.claim_carried_item(StandardBlockScript.create()), "Arm should carry final block.")
	var final_drop = grab_drop.request_selected_grab_drop()
	test.expect_true(final_drop != null and final_drop.is_success(), "Real final Drop should complete Mission.")
	test.expect_float_approx(score.get_elapsed_time(), program_end_time, "Completion should freeze the current Mission time.")
	test.expect_float_approx(score.get_manual_runtime(), 4.0, "Manual runtime should freeze at completion.")
	test.expect_float_approx(score.get_automated_runtime(), program_automated, "Automated runtime should freeze at completion.")
	var final_rate := program_automated / (program_automated + 4.0)
	test.expect_float_approx(score.get_automation_rate(), final_rate, "Completion should freeze runtime automation ratio.")
	test.expect_true(score_label.text.contains("时间 %.1f秒" % program_end_time), "Result panel should display completion time.")
	test.expect_true(score_label.text.contains("组件 %d" % expected_components), "Result panel should display component count.")
	test.expect_true(score_label.text.contains("自动化率 %d%%" % roundi(final_rate * 100.0)), "Result panel should display runtime automation ratio.")

	await process_frame
	test.expect_equal(runner.get_state(), ProgramRunnerScript.STATE_COMPLETED, "Program should remain completed after Mission finalizes.")
	test.expect_true(selection.select_vehicle(transport), "Transport should remain controllable after completion.")
	test.expect_true(move.request_selected_vehicle_move(transport_origin), "Post-completion MoveTo should still be a real command.")
	scene.timer = program_end_time + 10.0
	test.expect_true(move.request_selected_vehicle_stop(), "Post-completion MoveTo should be stoppable.")
	test.expect_float_approx(score.get_manual_runtime(), 4.0, "Post-completion commands must not mutate final score.")
	test.expect_float_approx(score.get_automation_rate(), final_rate, "Final automation ratio must remain frozen.")

	test.expect_true(bool(scene.call("reset_scene")), "Scene Reset should succeed.")
	test.expect_false(score.has_component_count(), "Reset should clear component snapshot.")
	test.expect_float_approx(score.get_manual_runtime(), 0.0, "Reset should clear manual runtime.")
	test.expect_float_approx(score.get_automated_runtime(), 0.0, "Reset should clear automated runtime.")
	test.expect_float_approx(score.get_elapsed_time(), 0.0, "Reset should expose Mission time zero.")

	scene.call("run_scene")
	test.expect_true(selection.select_vehicle(arm), "Arm should start overlapping manual regression.")
	test.expect_true(move.request_selected_vehicle_move(Vector2i(3, 2)), "Arm overlapping manual Move should start.")
	scene.timer = 1.0
	test.expect_true(selection.select_vehicle(transport), "Transport should be selectable while Arm moves.")
	test.expect_true(move.request_selected_vehicle_move(Vector2i(8, 4)), "Transport overlapping manual Move should start.")
	scene.timer = 2.0
	test.expect_true(selection.select_vehicle(arm) and move.request_selected_vehicle_stop(), "Arm overlapping Move should stop first.")
	test.expect_float_approx(score.get_manual_runtime(), 2.0, "Overlapping manual moves should count elapsed union time once.")
	scene.timer = 3.0
	test.expect_true(selection.select_vehicle(transport) and move.request_selected_vehicle_stop(), "Transport overlapping Move should stop last.")
	test.expect_float_approx(score.get_manual_runtime(), 3.0, "Two overlapping manual moves must not double-count shared time.")
	test.expect_true(bool(scene.call("reset_scene")), "Overlap regression Reset should restore scoring baseline.")
	scene.call("run_scene")
	var move_program := ProgramScript.new()
	var program_move_index := move_program.append_statement(ProgramScript.StatementType.MOVE_TO)
	move_program.set_statement_vehicle(program_move_index, VehicleManagerScript.ARM_VEHICLE_ID)
	test.expect_true(move_program.set_move_target(program_move_index, arm.runtime_state.anchor_cell), "Program MoveTo fixture should configure.")
	test.expect_true(runner.start_program(move_program), "Program MoveTo should start after Reset.")
	await process_frame
	await process_frame
	test.expect_equal(runner.get_state(), ProgramRunnerScript.STATE_COMPLETED, "Zero-distance Program MoveTo should complete.")
	test.expect_float_approx(score.get_manual_runtime(), 0.0, "Program-owned MoveTo must not be counted as manual takeover.")

	test.expect_true(bool(scene.call("reset_scene")), "Second Reset should prepare multi-vehicle scoring regression.")
	test.expect_true(bool(scene.call("set_simulation_speed", 4.0)), "Multi-vehicle scoring regression should use 4x wall-clock acceleration.")
	scene.call("run_scene")
	var multi := ProgramScript.new()
	var arm_move := multi.append_statement(ProgramScript.StatementType.MOVE_TO)
	multi.set_statement_vehicle(arm_move, VehicleManagerScript.ARM_VEHICLE_ID)
	multi.set_move_target(arm_move, Vector2i(3, 2))
	var transport_move := multi.append_statement(ProgramScript.StatementType.MOVE_TO)
	multi.set_statement_vehicle(transport_move, VehicleManagerScript.TRANSPORT_VEHICLE_ID)
	multi.set_move_target(transport_move, Vector2i(8, 4))
	observed_program_completion_time = -1.0
	runner.execution_completed.connect(_capture_program_completion.bind(score), CONNECT_ONE_SHOT)
	var program_start_time := score.get_elapsed_time()
	test.expect_true(runner.start_program(multi), "One Program should automate real Arm and Transport moves.")
	frames = 0
	while runner.get_state() == ProgramRunnerScript.STATE_RUNNING and frames < 240:
		await physics_frame
		frames += 1
	test.expect_equal(runner.get_state(), ProgramRunnerScript.STATE_COMPLETED, "Multi-vehicle Program should complete real serial moves.")
	var automated_elapsed := score.get_automated_runtime()
	var execution_elapsed := observed_program_completion_time - program_start_time
	test.expect_float_approx(score.get_manual_runtime(), 0.0, "Transport Program Move must not be misclassified as manual.")
	test.expect_true(automated_elapsed > 0.0, "Real multi-vehicle Program should accrue automated simulation runtime.")
	test.expect_true(observed_program_completion_time >= program_start_time, "Program completion should capture simulation time at the completion signal.")
	test.expect_true(absf(automated_elapsed - execution_elapsed) < 0.0001, "Automation runtime should match exact Program execution simulation time.")
	test.expect_float_approx(score.get_automation_rate(), 1.0, "Multi-vehicle Program should score 100% automation.")

	scene.queue_free()
	await process_frame
	test.finish(self, "Scene 01 scoring tests")

func _capture_program_completion(score: ScoreTrackerScript) -> void:
	observed_program_completion_time = score.get_elapsed_time()

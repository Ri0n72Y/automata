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
	var score_label := scene.get_node(
		"HUDRoot/RootControl/CompletionPanel/Margin/VBox/ScorePlaceholder"
	) as Label
	var arm = manager.get_vehicle_by_id(VehicleManagerScript.ARM_VEHICLE_ID)
	var transport = manager.get_vehicle_by_id(VehicleManagerScript.TRANSPORT_VEHICLE_ID)
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
	program.reset()
	program.vehicle_id = VehicleManagerScript.ARM_VEHICLE_ID
	test.expect_true(runner.start_program(program), "Start-only program should enter automated runtime.")
	scene.timer = 5.0
	scene.call("pause_scene")
	test.expect_float_approx(score.get_automated_runtime(), 3.0, "Pause should close automated runtime at Mission time.")
	test.expect_float_approx(score.get_automation_rate(), 0.6, "Automation should be runtime-based, not action-based.")
	scene.call("resume_scene")

	while box.get_current_count() < box.get_capacity() - 1:
		test.expect_true(box.put_item(StandardBlockScript.create()).is_success(), "Fixture should prepare box at 7/8.")
	arm.runtime_state.anchor_cell = Vector2i(14, 3)
	arm.sync_from_state()
	test.expect_true(arm.runtime_state.claim_carried_item(StandardBlockScript.create()), "Arm should carry final block.")
	scene.timer = 7.0
	var final_drop = grab_drop.request_selected_grab_drop()
	test.expect_true(final_drop != null and final_drop.is_success(), "Real final Drop should complete Mission.")
	test.expect_float_approx(score.get_elapsed_time(), 7.0, "Completion time should be Mission frozen time.")
	test.expect_float_approx(score.get_manual_runtime(), 2.0, "Manual runtime should freeze at completion.")
	test.expect_float_approx(score.get_automated_runtime(), 5.0, "Automated runtime should freeze at completion.")
	var final_rate := 5.0 / 7.0
	test.expect_float_approx(score.get_automation_rate(), final_rate, "Completion should freeze runtime automation ratio.")
	test.expect_true(score_label.text.contains("时间 7.0s"), "Result panel should display completion time.")
	test.expect_true(score_label.text.contains("组件 %d" % expected_components), "Result panel should display component count.")
	test.expect_true(score_label.text.contains("自动化率 71%"), "Result panel should display runtime automation ratio.")

	await process_frame
	await process_frame
	test.expect_equal(runner.get_state(), ProgramRunnerScript.STATE_COMPLETED, "Program should complete normally after Mission finalizes.")
	test.expect_true(selection.select_vehicle(transport), "Transport should remain controllable after completion.")
	test.expect_true(move.request_selected_vehicle_move(Vector2i(8, 4)), "Post-completion MoveTo should still be a real command.")
	scene.timer = 20.0
	test.expect_true(move.request_selected_vehicle_stop(), "Post-completion MoveTo should be stoppable.")
	test.expect_float_approx(score.get_manual_runtime(), 2.0, "Post-completion commands must not mutate final score.")
	test.expect_float_approx(score.get_automation_rate(), final_rate, "Final automation ratio must remain frozen.")

	test.expect_true(bool(scene.call("reset_scene")), "Scene Reset should succeed.")
	test.expect_false(score.has_component_count(), "Reset should clear component snapshot.")
	test.expect_float_approx(score.get_manual_runtime(), 0.0, "Reset should clear manual runtime.")
	test.expect_float_approx(score.get_automated_runtime(), 0.0, "Reset should clear automated runtime.")
	test.expect_float_approx(score.get_elapsed_time(), 0.0, "Reset should expose Mission time zero.")

	scene.queue_free()
	await process_frame
	test.finish(self, "Scene 01 scoring tests")

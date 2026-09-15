extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const ContractTestScript := preload("res://tests/support/contract_test.gd")
const ScoreTrackerScript := preload("res://scripts/scene_01/scene_01_score_tracker.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const ProgramRunnerScript := preload("res://scripts/scene_01/scene_01_program_runner.gd")
const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const GrabDropResultScript := preload("res://scripts/vehicles/grab_drop_result.gd")
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
	var gate = scene.get_node("SceneRoot/Scene01AssemblyCompileGate")
	var runner := scene.get_node("SceneRoot/Scene01ProgramRunner") as ProgramRunnerScript
	var grab_drop = scene.get_node("SceneRoot/GridRoot/VehicleGrabDropController")
	var score_label := scene.get_node(
		"HUDRoot/RootControl/CompletionPanel/Margin/VBox/ScorePlaceholder"
	) as Label
	var arm = manager.get_vehicle_by_id(VehicleManagerScript.ARM_VEHICLE_ID)
	test.expect_true(score != null and arm != null, "Scoring test requires production scorer and arm vehicle.")

	test.expect_false(score.has_cost(), "Cost should be unavailable before the run starts.")
	scene.call("run_scene")
	var expected_cost := 0
	for vehicle_node in manager.get_vehicles():
		var result = gate.get_compile_result(vehicle_node.get_vehicle_id())
		test.expect_true(result != null and result.is_success(), "Run should publish compiled vehicle metrics.")
		if result != null:
			expected_cost += result.get_metrics().get_cost()
	test.expect_true(score.has_cost(), "Run start should capture the fixed assembly cost.")
	test.expect_equal(score.get_total_cost(), expected_cost, "Score cost should equal formal compile metrics.")

	arm.move_completed.emit(Vector2i(3, 2))
	grab_drop.grab_drop_completed.emit(
		VehicleManagerScript.ARM_VEHICLE_ID,
		GrabDropResultScript.Action.GRAB,
		GrabDropResultScript.Status.ACCEPTED
	)
	grab_drop.grab_drop_completed.emit(
		VehicleManagerScript.ARM_VEHICLE_ID,
		GrabDropResultScript.Action.NONE,
		GrabDropResultScript.Status.NO_TARGET
	)
	test.expect_equal(score.get_total_actions(), 2, "Only successful manual actions should count.")
	test.expect_equal(score.get_manual_actions(), 2, "Manual successes should remain manual.")

	runner.execution_started.emit(VehicleManagerScript.ARM_VEHICLE_ID)
	runner.node_started.emit(1, ProgramScript.NodeType.MOVE_TO)
	arm.move_completed.emit(Vector2i(4, 2))
	runner.node_started.emit(2, ProgramScript.NodeType.GRAB_DROP)
	grab_drop.grab_drop_completed.emit(
		VehicleManagerScript.ARM_VEHICLE_ID,
		GrabDropResultScript.Action.DROP,
		GrabDropResultScript.Status.ACCEPTED
	)
	runner.execution_completed.emit(VehicleManagerScript.ARM_VEHICLE_ID)
	test.expect_equal(score.get_total_actions(), 4, "Automated successes should share the same action count.")
	test.expect_equal(score.get_automated_actions(), 2, "Program actions should count as automated.")
	test.expect_float_approx(score.get_automation_rate(), 0.5, "Automation rate should be automated / total successful actions.")

	scene.timer = 12.5
	var box = scene.get_node("SceneRoot/ObjectRoot/Scene01ObjectManager").get_standard_box()
	while box.get_current_count() < box.get_capacity():
		test.expect_true(box.put_item(StandardBlockScript.create()).is_success(), "Completion fixture should fill the box.")
	scene.timer = 99.0
	test.expect_float_approx(score.get_elapsed_time(), 12.5, "Score time should delegate to frozen Mission elapsed time.")
	test.expect_true(score_label.text.contains("时间 12.5s"), "Result panel should display Mission time.")
	test.expect_true(score_label.text.contains("成本 %d" % expected_cost), "Result panel should display compile cost.")
	test.expect_true(score_label.text.contains("自动化率 50%"), "Result panel should display automation rate.")

	test.expect_true(bool(scene.call("reset_scene")), "Scene Reset should succeed.")
	test.expect_false(score.has_cost(), "Reset should clear the captured cost.")
	test.expect_equal(score.get_total_actions(), 0, "Reset should clear successful action counts.")
	test.expect_float_approx(score.get_elapsed_time(), 0.0, "Reset should expose Mission time zero.")

	scene.queue_free()
	await process_frame
	test.finish(self, "Scene 01 scoring tests")

extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const ValidatorScript := preload("res://scripts/scene_01/scene_01_program_validator.gd")
const ProgramRunnerScript := preload("res://scripts/scene_01/scene_01_program_runner.gd")
const CompileGateScript := preload("res://scripts/scene_01/scene_01_assembly_compile_gate.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_model_validation_and_save()
	await _test_production_runner()
	_finish()


func _test_model_validation_and_save() -> void:
	var program := _build_cycle_program(&"arm_vehicle")
	var validator := ValidatorScript.new()
	_expect_true(validator.validate(program, Vector2i(16, 10)).is_empty(), "Valid basic program should pass graph validation.")
	_expect_equal(validator.required_capabilities(program).size(), 2, "MoveTo + GrabDrop should require exactly two assembly capabilities.")

	var invalid_repeat_count := program.duplicate_program()
	var repeat_id := invalid_repeat_count.get_tail_node_id()
	invalid_repeat_count.set_repeat(repeat_id, 0, 2)
	var diagnostics := validator.validate(invalid_repeat_count, Vector2i(16, 10))
	_expect_true(_has_diagnostic(diagnostics, &"invalid_repeat_count"), "Repeat 0 should be rejected before runtime.")

	var invalid_repeat_target := program.duplicate_program()
	repeat_id = invalid_repeat_target.get_tail_node_id()
	invalid_repeat_target.set_repeat(repeat_id, 5, invalid_repeat_target.start_node_id)
	diagnostics = validator.validate(invalid_repeat_target, Vector2i(16, 10))
	_expect_true(_has_diagnostic(diagnostics, &"invalid_repeat_target"), "Repeat should reject Start as a loop target.")

	var invalid_cycle := program.duplicate_program()
	var first_node := invalid_cycle.get_node_data(invalid_cycle.start_node_id)
	var first_executable_id := int(first_node.get("next_id", ProgramScript.NO_NODE_ID))
	repeat_id = invalid_cycle.get_tail_node_id()
	invalid_cycle.connect_nodes(repeat_id, first_executable_id)
	diagnostics = validator.validate(invalid_cycle, Vector2i(16, 10))
	_expect_true(_has_diagnostic(diagnostics, &"next_cycle"), "Ordinary next links must not create a cycle.")

	var save_path := "user://scene_01_program_system_test.tres"
	_expect_equal(ResourceSaver.save(program, save_path), OK, "Program resource should save without UI dependencies.")
	var loaded := ResourceLoader.load(save_path) as Scene01Program
	_expect_true(loaded != null, "Saved program should load as Scene01Program.")
	if loaded != null:
		_expect_equal(loaded.vehicle_id, &"arm_vehicle", "Saved program should preserve vehicle id.")
		_expect_equal(loaded.nodes.size(), program.nodes.size(), "Saved program should preserve node data.")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func _test_production_runner() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load with ProgramRunner wiring.")
	if packed == null:
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame

	var runner := scene.get_node_or_null("SceneRoot/Scene01ProgramRunner") as ProgramRunnerScript
	var compile_gate := scene.get_node_or_null("SceneRoot/Scene01AssemblyCompileGate") as CompileGateScript
	var manager := scene.get_node_or_null("SceneRoot/RobotRoot/Scene01VehicleManager") as Scene01VehicleManager
	var object_manager := scene.get_node_or_null("SceneRoot/ObjectRoot/Scene01ObjectManager") as Scene01ObjectManager
	_expect_true(
		runner != null and compile_gate != null and manager != null and object_manager != null,
		"Production scene should expose program runner dependencies."
	)
	if runner == null or compile_gate == null or manager == null or object_manager == null:
		scene.queue_free()
		await process_frame
		return

	var pile := object_manager.get_block_pile()
	var box := object_manager.get_standard_box()
	_expect_true(pile != null and box != null, "Program integration requires pile and StandardBox.")
	if pile == null or box == null:
		scene.queue_free()
		await process_frame
		return

	var pile_cells: Array[Vector2i] = [Vector2i(3, 3)]
	var box_cells: Array[Vector2i] = [Vector2i(4, 3)]
	pile.set_interaction_cells(pile_cells)
	box.set_interaction_cells(box_cells)
	object_manager.refresh_ground_cell_policy()

	_expect_true(bool(scene.call("set_simulation_speed", 4.0)), "Program integration should use existing lifecycle simulation speed.")
	var program := _build_cycle_program(&"arm_vehicle")
	_expect_true(runner.start_program(program), "Valid Arm program should pass compile/capability preflight and start.")
	_expect_equal(runner.get_state(), ProgramRunnerScript.STATE_RUNNING, "Runner should enter RUNNING without creating a second lifecycle state.")
	var active_node := runner.get_current_node_id()
	_expect_false(runner.start_program(program), "A second Start must not replace the active runtime snapshot.")
	_expect_equal(runner.get_state(), ProgramRunnerScript.STATE_RUNNING, "Rejected reentry must leave the active program running.")
	_expect_equal(runner.get_current_node_id(), active_node, "Rejected reentry must preserve the program counter.")

	var paused_node := runner.get_current_node_id()
	scene.call("pause_scene")
	for _frame in range(5):
		await process_frame
	_expect_equal(runner.get_current_node_id(), paused_node, "PAUSED lifecycle should freeze the program counter.")
	scene.call("resume_scene")

	var frames := 0
	while runner.get_state() == ProgramRunnerScript.STATE_RUNNING and frames < 1200:
		await physics_frame
		frames += 1
	_expect_equal(runner.get_state(), ProgramRunnerScript.STATE_COMPLETED, "Repeat program should complete through shared commands.")
	_expect_equal(box.get_current_count(), 8, "Program should move five blocks and fill StandardBox to 8/8.")
	_expect_true(bool(scene.call("is_mission_completed")), "Program completion should flow through the existing Mission owner.")
	_expect_true(
		compile_gate.get_compile_result(&"arm_vehicle") != null,
		"Completed program should retain the formal compile publication for downstream scoring."
	)

	_expect_true(bool(scene.call("reset_scene_state")), "Lifecycle Reset should remain the single scene reset path.")
	await process_frame
	_expect_equal(runner.get_state(), ProgramRunnerScript.STATE_IDLE, "Reset should cancel program execution and return runner to IDLE.")
	_expect_equal(box.get_current_count(), 3, "Reset should restore StandardBox through the existing object owner.")
	_expect_true(
		compile_gate.get_compile_result(&"arm_vehicle") == null,
		"Reset should end the previous program compile publication lifetime."
	)

	var transport_program := ProgramScript.new()
	transport_program.reset()
	transport_program.vehicle_id = &"transport_vehicle"
	transport_program.append_node(ProgramScript.NodeType.GRAB_DROP)
	_expect_false(runner.start_program(transport_program), "Transport program should be rejected before runtime when GrabDrop capability is missing.")
	_expect_equal(runner.get_last_error(), &"program_capability_rejected", "Capability rejection should come from the formal assembly compile path.")

	scene.queue_free()
	await process_frame


func _build_cycle_program(vehicle_id: StringName) -> Scene01Program:
	var program := ProgramScript.new()
	program.reset()
	program.vehicle_id = vehicle_id

	var first_move := program.append_node(ProgramScript.NodeType.MOVE_TO)
	program.set_move_target(first_move, Vector2i(3, 5))
	var pile_approach := program.append_node(ProgramScript.NodeType.MOVE_TO)
	program.set_move_target(pile_approach, Vector2i(3, 4))
	program.append_node(ProgramScript.NodeType.GRAB_DROP)
	var box_stage := program.append_node(ProgramScript.NodeType.MOVE_TO)
	program.set_move_target(box_stage, Vector2i(4, 5))
	var box_approach := program.append_node(ProgramScript.NodeType.MOVE_TO)
	program.set_move_target(box_approach, Vector2i(4, 4))
	program.append_node(ProgramScript.NodeType.GRAB_DROP)
	var repeat_id := program.append_node(ProgramScript.NodeType.REPEAT)
	program.set_repeat(repeat_id, 5, first_move)
	return program


func _has_diagnostic(diagnostics: Array[Dictionary], code: StringName) -> bool:
	for diagnostic in diagnostics:
		if StringName(diagnostic.get("code", &"")) == code:
			return true
	return false


func _finish() -> void:
	if failures == 0:
		print("Scene 01 program system tests passed.")
		quit(0)
		return
	push_error("Scene 01 program system tests failed: %d failure(s)." % failures)
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
	_expect_true(not value, message)

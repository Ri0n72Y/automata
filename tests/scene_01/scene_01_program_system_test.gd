extends SceneTree
const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const ValidatorScript := preload("res://scripts/scene_01/scene_01_program_validator.gd")
const ProgramRunnerScript := preload("res://scripts/scene_01/scene_01_program_runner.gd")
const CompileGateScript := preload("res://scripts/scene_01/scene_01_assembly_compile_gate.gd")
var failures := 0
var observed_command_vehicles: Array[StringName] = []
func _init() -> void:
	call_deferred("_run")
func _run() -> void:
	_test_linear_model_validation()
	await _test_production_runner()
	_finish()
func _test_linear_model_validation() -> void:
	var program := _build_cycle_program(&"arm_vehicle")
	var validator := ValidatorScript.new()
	_expect_true(validator.validate(program, Vector2i(16, 10)).is_empty(), "Valid linear program should pass validation.")
	_expect_equal(validator.required_capabilities(program).size(), 2, "MoveTo + GrabDrop should require exactly two assembly capabilities.")
	var invalid_repeat_count := program.duplicate_program()
	var repeat_index := invalid_repeat_count.get_statement_count() - 1
	invalid_repeat_count.set_repeat(repeat_index, 0, 0)
	var diagnostics := validator.validate(invalid_repeat_count, Vector2i(16, 10))
	_expect_true(_has_diagnostic(diagnostics, &"invalid_repeat_count"), "Repeat 0 should be rejected before runtime.")
	var invalid_repeat_target := program.duplicate_program()
	invalid_repeat_target.set_repeat(repeat_index, 5, repeat_index)
	diagnostics = validator.validate(invalid_repeat_target, Vector2i(16, 10))
	_expect_true(_has_diagnostic(diagnostics, &"invalid_repeat_target"), "Repeat should reject non-earlier targets.")
	var duplicate := program.duplicate_program()
	duplicate.set_statement_vehicle(0, &"transport_vehicle")
	_expect_equal(StringName(program.get_statement(0).get("vehicle_id", &"")), &"arm_vehicle", "Runtime duplicate must not mutate source program.")
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
	var selection = scene.get_node_or_null("SceneRoot/GridRoot/VehicleSelectionController")
	var move_controller = scene.get_node_or_null("SceneRoot/GridRoot/VehicleMoveController")
	_expect_true(runner != null and compile_gate != null and manager != null and object_manager != null and selection != null and move_controller != null, "Production scene should expose program dependencies.")
	if runner == null or compile_gate == null or manager == null or object_manager == null or selection == null or move_controller == null:
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
	pile.set_interaction_cells([Vector2i(3, 3)])
	box.set_interaction_cells([Vector2i(4, 3)])
	object_manager.refresh_ground_cell_policy()
	_expect_true(bool(scene.call("set_simulation_speed", 4.0)), "Program integration should use lifecycle speed.")
	var program := _build_cycle_program(&"arm_vehicle")
	_expect_true(runner.start_program(program), "Valid Arm program should pass preflight and start.")
	_expect_equal(runner.get_state(), ProgramRunnerScript.STATE_RUNNING, "Runner should enter RUNNING.")
	var active_statement := runner.get_current_statement_index()
	_expect_false(runner.start_program(program), "Second Start must not replace active snapshot.")
	_expect_equal(runner.get_current_statement_index(), active_statement, "Rejected reentry must preserve program counter.")
	var paused_statement := runner.get_current_statement_index()
	scene.call("pause_scene")
	for _frame in range(5):
		await process_frame
	_expect_equal(runner.get_current_statement_index(), paused_statement, "PAUSED lifecycle should freeze program counter.")
	scene.call("resume_scene")
	var frames := 0
	while runner.get_state() == ProgramRunnerScript.STATE_RUNNING and frames < 1200:
		await physics_frame
		frames += 1
	_expect_equal(runner.get_state(), ProgramRunnerScript.STATE_COMPLETED, "Repeat program should complete through shared commands.")
	_expect_equal(box.get_current_count(), 8, "Program should fill StandardBox to 8/8.")
	_expect_true(bool(scene.call("is_mission_completed")), "Program completion should flow through Mission owner.")
	_expect_true(compile_gate.get_compile_result(&"arm_vehicle") != null, "Completed program should retain compile publication.")
	_expect_true(bool(scene.call("reset_scene_state")), "Lifecycle Reset should remain single reset path.")
	await process_frame
	_expect_equal(runner.get_state(), ProgramRunnerScript.STATE_IDLE, "Reset should return runner to IDLE.")
	_expect_equal(box.get_current_count(), 3, "Reset should restore StandardBox.")
	_expect_true(compile_gate.get_compile_result(&"arm_vehicle") == null, "Reset should end compile publication lifetime.")
	var transport_program := ProgramScript.new()
	var transport_grab := transport_program.append_statement(ProgramScript.StatementType.GRAB_DROP)
	transport_program.set_statement_vehicle(transport_grab, &"transport_vehicle")
	_expect_false(runner.start_program(transport_program), "Transport GrabDrop should fail formal capability preflight.")
	_expect_equal(runner.get_last_error(), &"program_capability_rejected", "Capability rejection should come from compile gate.")
	_expect_true(bool(scene.call("reset_scene_state")), "Reset should recover from rejected start.")
	await process_frame
	var arm = manager.get_vehicle_by_id(&"arm_vehicle")
	var transport = manager.get_vehicle_by_id(&"transport_vehicle")
	_expect_true(selection.select_vehicle(transport), "Fixture should select Transport for Program Stop regression.")
	var stopped_program := ProgramScript.new()
	_append_move(stopped_program, &"transport_vehicle", Vector2i(8, 4))
	_expect_true(runner.start_program(stopped_program), "Transport Program Move should start before player Stop.")
	await process_frame
	_expect_equal(runner.get_state(), ProgramRunnerScript.STATE_RUNNING, "Program Move should be active before Stop.")
	_expect_true(move_controller.request_selected_vehicle_stop(), "Player Stop should cancel the selected Program-owned Move.")
	_expect_equal(runner.get_state(), ProgramRunnerScript.STATE_FAILED, "Player Stop must terminate Program instead of leaving it RUNNING.")
	_expect_equal(runner.get_last_error(), &"move_blocked", "Vehicle cancellation should surface through the existing move_blocked contract.")
	_expect_true(bool(scene.call("reset_scene_state")), "Reset should recover after player-stopped Program Move.")
	await process_frame
	_expect_equal(runner.get_state(), ProgramRunnerScript.STATE_IDLE, "Reset should clear stopped Program failure state.")
	_expect_true(selection.select_vehicle(arm), "Fixture should select Arm before multi-vehicle program.")
	observed_command_vehicles.clear()
	runner.command_started.connect(_on_command_started)
	var multi := ProgramScript.new()
	var arm_move := multi.append_statement(ProgramScript.StatementType.MOVE_TO)
	multi.set_statement_vehicle(arm_move, &"arm_vehicle")
	multi.set_move_target(arm_move, arm.runtime_state.anchor_cell)
	var transport_move := multi.append_statement(ProgramScript.StatementType.MOVE_TO)
	multi.set_statement_vehicle(transport_move, &"transport_vehicle")
	multi.set_move_target(transport_move, transport.runtime_state.anchor_cell)
	var multi_repeat := multi.append_statement(ProgramScript.StatementType.REPEAT)
	multi.set_repeat(multi_repeat, 2, arm_move)
	_expect_true(runner.start_program(multi), "One program should command Arm and Transport serially.")
	frames = 0
	while runner.get_state() == ProgramRunnerScript.STATE_RUNNING and frames < 30:
		await physics_frame
		frames += 1
	_expect_equal(runner.get_state(), ProgramRunnerScript.STATE_COMPLETED, "Multi-vehicle Repeat should complete.")
	_expect_equal(observed_command_vehicles, [&"arm_vehicle", &"transport_vehicle", &"arm_vehicle", &"transport_vehicle"], "Repeat should replay fixed vehicle statements.")
	_expect_equal(selection.get_selected_vehicle(), arm, "Program commands must not mutate player selection.")
	scene.queue_free()
	await process_frame
func _build_cycle_program(vehicle_id: StringName) -> Scene01Program:
	var program := ProgramScript.new()
	var first_move := _append_move(program, vehicle_id, Vector2i(3, 5))
	_append_move(program, vehicle_id, Vector2i(3, 4))
	_append_grab(program, vehicle_id)
	_append_move(program, vehicle_id, Vector2i(4, 5))
	_append_move(program, vehicle_id, Vector2i(4, 4))
	_append_grab(program, vehicle_id)
	var repeat_index := program.append_statement(ProgramScript.StatementType.REPEAT)
	program.set_repeat(repeat_index, 5, first_move)
	return program
func _append_move(program: Scene01Program, vehicle_id: StringName, target: Vector2i) -> int:
	var index := program.append_statement(ProgramScript.StatementType.MOVE_TO)
	program.set_statement_vehicle(index, vehicle_id)
	program.set_move_target(index, target)
	return index
func _append_grab(program: Scene01Program, vehicle_id: StringName) -> int:
	var index := program.append_statement(ProgramScript.StatementType.GRAB_DROP)
	program.set_statement_vehicle(index, vehicle_id)
	return index
func _on_command_started(_statement_index: int, _command_type: int, vehicle_id: StringName) -> void:
	observed_command_vehicles.append(vehicle_id)
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
	if actual != expected:
		failures += 1
		push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])
func _expect_true(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _expect_false(value: bool, message: String) -> void:
	_expect_true(not value, message)

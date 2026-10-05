extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const ValidatorScript := preload("res://scripts/scene_01/scene_01_program_validator.gd")
const ProgramRunnerScript := preload("res://scripts/scene_01/scene_01_program_runner.gd")
const CompileGateScript := preload("res://scripts/scene_01/scene_01_assembly_compile_gate.gd")

var failures := 0
var observed_command_vehicles: Array[StringName] = []
var observed_player_selections: Array[StringName] = []
var selection_probe


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

	var repeat_index := program.get_statement_count() - 1
	var invalid_repeat_count := program.duplicate_program()
	invalid_repeat_count.set_repeat(repeat_index, 0, 0)
	_expect_true(
		_has_diagnostic(validator.validate(invalid_repeat_count, Vector2i(16, 10)), &"invalid_repeat_count"),
		"Repeat 0 should be rejected before runtime."
	)

	var invalid_repeat_target := program.duplicate_program()
	invalid_repeat_target.set_repeat(repeat_index, 5, repeat_index)
	_expect_true(
		_has_diagnostic(validator.validate(invalid_repeat_target, Vector2i(16, 10)), &"invalid_repeat_target"),
		"Repeat should reject non-earlier targets."
	)

	var duplicate := program.duplicate_program()
	duplicate.set_statement_vehicle(0, &"transport_vehicle")
	_expect_equal(
		StringName(program.get_statement(0).get("vehicle_id", &"")),
		&"arm_vehicle",
		"Runtime duplicate must not mutate source program."
	)


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
	var selection = scene.get_node_or_null("SceneRoot/GridRoot/VehicleSelectionController")
	var move_controller = scene.get_node_or_null("SceneRoot/GridRoot/VehicleMoveController")
	selection_probe = selection
	_expect_true(
		runner != null and compile_gate != null and manager != null
		and selection != null and move_controller != null,
		"Production scene should expose Program runner boundaries."
	)
	if runner == null or compile_gate == null or manager == null or selection == null or move_controller == null:
		scene.queue_free()
		await process_frame
		return

	var arm = manager.get_vehicle_by_id(&"arm_vehicle")
	var transport = manager.get_vehicle_by_id(&"transport_vehicle")
	_expect_true(arm != null and transport != null, "Program runner contract requires both vehicles.")
	if arm == null or transport == null:
		scene.queue_free()
		await process_frame
		return

	_expect_true(bool(scene.call("set_simulation_speed", 4.0)), "Program contract should use lifecycle speed.")

	var active_program := ProgramScript.new()
	_append_move(active_program, &"arm_vehicle", arm.runtime_state.anchor_cell + Vector2i.RIGHT)
	_expect_true(runner.start_program(active_program), "A real Arm MoveTo Program should start.")
	var active_statement := runner.get_current_statement_index()
	_expect_false(runner.start_program(active_program), "Second Start must not replace an active snapshot.")
	_expect_equal(runner.get_current_statement_index(), active_statement, "Rejected reentry must preserve the program counter.")

	scene.call("pause_scene")
	for _frame in range(3):
		await process_frame
	_expect_equal(runner.get_current_statement_index(), active_statement, "PAUSED lifecycle should freeze the program counter.")
	scene.call("resume_scene")

	var frames := 0
	while runner.get_state() == ProgramRunnerScript.STATE_RUNNING and frames < 120:
		await physics_frame
		frames += 1
	_expect_equal(runner.get_state(), ProgramRunnerScript.STATE_COMPLETED, "Short Program MoveTo should complete.")
	_expect_true(compile_gate.get_compile_result(&"arm_vehicle") != null, "Completed Program should retain compile publication.")

	_expect_true(bool(scene.call("reset_scene_state")), "Lifecycle Reset should remain the single reset path.")
	await process_frame
	_expect_equal(runner.get_state(), ProgramRunnerScript.STATE_IDLE, "Reset should return runner to IDLE.")
	_expect_true(compile_gate.get_compile_result(&"arm_vehicle") == null, "Reset should end compile publication lifetime.")

	var arm_rotate := ProgramScript.new()
	var arm_rotate_index := arm_rotate.append_statement(ProgramScript.StatementType.ROTATE)
	arm_rotate.set_statement_vehicle(arm_rotate_index, &"arm_vehicle")
	arm_rotate.set_turn_direction(arm_rotate_index, -1)
	var arm_facing := arm.runtime_state.facing
	_expect_true(runner.start_program(arm_rotate), "Arm Rotate should start through the shared command path.")
	frames = 0
	while runner.get_state() == ProgramRunnerScript.STATE_RUNNING and frames < 120:
		await physics_frame
		frames += 1
	_expect_equal(runner.get_state(), ProgramRunnerScript.STATE_COMPLETED, "Arm Rotate should complete.")
	_expect_equal(arm.runtime_state.facing, posmod(arm_facing - 1, 4), "Arm Rotate should apply one relative turn.")

	var transport_rotate := ProgramScript.new()
	var transport_rotate_index := transport_rotate.append_statement(ProgramScript.StatementType.ROTATE)
	transport_rotate.set_statement_vehicle(transport_rotate_index, &"transport_vehicle")
	transport_rotate.set_turn_direction(transport_rotate_index, 1)
	var transport_facing := transport.runtime_state.facing
	_expect_true(runner.start_program(transport_rotate), "Transport Rotate should use its independent Rotate capability.")
	frames = 0
	while runner.get_state() == ProgramRunnerScript.STATE_RUNNING and frames < 120:
		await physics_frame
		frames += 1
	_expect_equal(runner.get_state(), ProgramRunnerScript.STATE_COMPLETED, "Transport Rotate should complete.")
	_expect_equal(transport.runtime_state.facing, posmod(transport_facing + 1, 4), "Transport Rotate should apply one relative turn.")

	var rejected := ProgramScript.new()
	var transport_grab := rejected.append_statement(ProgramScript.StatementType.GRAB_DROP)
	rejected.set_statement_vehicle(transport_grab, &"transport_vehicle")
	_expect_false(runner.start_program(rejected), "Transport GrabDrop should fail capability preflight.")
	_expect_equal(runner.get_last_error(), &"program_capability_rejected", "Capability rejection should come from compile preflight.")

	_expect_true(bool(scene.call("reset_scene_state")), "Reset should recover from rejected Program start.")
	await process_frame
	_expect_true(selection.select_vehicle(transport), "Fixture should select Transport before player Stop.")
	var stopped := ProgramScript.new()
	_append_move(stopped, &"transport_vehicle", transport.runtime_state.anchor_cell + Vector2i.LEFT)
	_expect_true(runner.start_program(stopped), "Transport Program Move should start before player Stop.")
	await process_frame
	_expect_true(move_controller.request_selected_vehicle_stop(), "Player Stop should cancel the Program-owned Move.")
	_expect_equal(runner.get_state(), ProgramRunnerScript.STATE_FAILED, "Player Stop should terminate the active Program.")
	_expect_equal(runner.get_last_error(), &"move_blocked", "Vehicle cancellation should surface through move_blocked.")

	_expect_true(bool(scene.call("reset_scene_state")), "Reset should prepare serial multi-vehicle coverage.")
	await process_frame
	_expect_true(selection.select_vehicle(arm), "Player selection should remain independent from Program command context.")
	observed_command_vehicles.clear()
	observed_player_selections.clear()
	runner.command_started.connect(_on_command_started)
	move_controller.move_accepted.connect(_on_move_accepted_probe)

	var multi := ProgramScript.new()
	var arm_move := _append_move(multi, &"arm_vehicle", arm.runtime_state.anchor_cell + Vector2i.RIGHT)
	_append_move(multi, &"transport_vehicle", transport.runtime_state.anchor_cell + Vector2i.LEFT)
	var repeat_index := multi.append_statement(ProgramScript.StatementType.REPEAT)
	multi.set_repeat(repeat_index, 2, arm_move)
	_expect_true(runner.start_program(multi), "One Program should command Arm and Transport serially.")
	frames = 0
	while runner.get_state() == ProgramRunnerScript.STATE_RUNNING and frames < 180:
		await physics_frame
		frames += 1
	_expect_equal(runner.get_state(), ProgramRunnerScript.STATE_COMPLETED, "Serial multi-vehicle Repeat should complete.")
	_expect_equal(
		observed_command_vehicles,
		[&"arm_vehicle", &"transport_vehicle", &"arm_vehicle", &"transport_vehicle"],
		"Repeat should replay fixed vehicle statements."
	)
	_expect_equal(
		observed_player_selections,
		[&"arm_vehicle", &"arm_vehicle", &"arm_vehicle", &"arm_vehicle"],
		"Command execution must not replace real player selection."
	)
	_expect_equal(selection.get_selected_vehicle(), arm, "Program commands must leave player selection unchanged.")

	scene.queue_free()
	await process_frame


func _build_cycle_program(vehicle_id: StringName) -> Scene01Program:
	var program := ProgramScript.new()
	var first_move := _append_move(program, vehicle_id, Vector2i(3, 5))
	_append_grab(program, vehicle_id)
	var repeat_index := program.append_statement(ProgramScript.StatementType.REPEAT)
	program.set_repeat(repeat_index, 2, first_move)
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


func _on_move_accepted_probe(_vehicle_id: StringName, _target_anchor: Vector2i) -> void:
	if selection_probe != null:
		observed_player_selections.append(selection_probe.get_selected_vehicle_id())


func _has_diagnostic(diagnostics: Array[Dictionary], code: StringName) -> bool:
	for diagnostic in diagnostics:
		if StringName(diagnostic.get("code", &"")) == code:
			return true
	return false


func _finish() -> void:
	if failures == 0:
		print("Scene 01 Program runner contract tests passed.")
		quit(0)
		return
	push_error("Scene 01 Program runner contract tests failed: %d failure(s)." % failures)
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

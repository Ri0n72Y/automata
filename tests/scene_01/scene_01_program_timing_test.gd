extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const RunnerScript := preload("res://scripts/scene_01/scene_01_program_runner.gd")

var failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for Program timing regression.")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	var runner := scene.get_node_or_null("SceneRoot/Scene01ProgramRunner") as RunnerScript
	var manager := scene.get_node_or_null("SceneRoot/RobotRoot/Scene01VehicleManager") as Scene01VehicleManager
	var compile_gate = scene.get_node_or_null("SceneRoot/Scene01AssemblyCompileGate")
	_expect_true(runner != null and manager != null and compile_gate != null, "Timing regression requires production Program wiring.")
	if runner != null and manager != null and compile_gate != null:
		var arm = manager.get_vehicle_by_id(&"arm_vehicle")
		_expect_true(arm != null and arm.runtime_state != null, "Timing regression requires Arm runtime state.")
		if arm != null and arm.runtime_state != null:
			for speed in [0.5, 1.0, 2.0, 4.0]:
				_probe_speed(scene, runner, compile_gate, arm, speed)
	scene.queue_free()
	await process_frame
	_finish()

func _probe_speed(scene: Node, runner: Scene01ProgramRunner, compile_gate: Node, arm: VehicleActor, speed: float) -> void:
	_expect_true(bool(scene.call("set_simulation_speed", speed)), "Lifecycle should accept supported speed %.1fx." % speed)
	var program := _build_synchronous_program(arm.runtime_state.anchor_cell)
	var before := float(scene.call("get_mission_elapsed_time"))
	_expect_true(runner.start_program(program), "READY Program should start at %.1fx." % speed)
	_expect_equal(runner.get_state(), RunnerScript.STATE_COMPLETED, "Synchronous Program should complete inside start_program at %.1fx." % speed)
	_expect_near(float(scene.call("get_mission_elapsed_time")) - before, 0.0, 0.0001, "Synchronous statements must not consume simulation time at %.1fx." % speed)
	_expect_true(compile_gate.call("get_compile_result", &"arm_vehicle") != null, "READY start should publish one valid compile result.")
	_expect_true(runner.start_program(program), "Program should restart while lifecycle is already RUNNING.")
	_expect_equal(runner.get_state(), RunnerScript.STATE_COMPLETED, "RUNNING lifecycle Program should also drain synchronously.")
	_expect_near(float(scene.call("get_mission_elapsed_time")) - before, 0.0, 0.0001, "RUNNING start must remain simulation-time neutral.")
	_expect_true(bool(scene.call("reset_scene_state")), "Timing probe should reset production lifecycle.")

func _build_synchronous_program(target: Vector2i) -> Scene01Program:
	var program := ProgramScript.new()
	var move_index := program.append_statement(ProgramScript.StatementType.MOVE_TO)
	program.set_statement_vehicle(move_index, &"arm_vehicle")
	program.set_move_target(move_index, target)
	var repeat_index := program.append_statement(ProgramScript.StatementType.REPEAT)
	program.set_repeat(repeat_index, 100, move_index)
	return program

func _finish() -> void:
	if failures == 0:
		print("Scene 01 Program timing tests passed.")
		quit(0)
		return
	push_error("Scene 01 Program timing tests failed: %d failure(s)." % failures)
	quit(1)

func _expect_true(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures += 1
		push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])

func _expect_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		failures += 1
		push_error("%s Expected %.6f ± %.6f, got %.6f." % [message, expected, tolerance, actual])

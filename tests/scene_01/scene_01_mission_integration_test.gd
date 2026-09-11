extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const ContractTestScript := preload("res://tests/support/contract_test.gd")
const LifecycleStateScript := preload("res://scripts/scene_01/scene_01_lifecycle_state.gd")
const MissionStateScript := preload("res://scripts/scene_01/scene_01_mission_state.gd")
const MissionControllerScript := preload("res://scripts/scene_01/scene_01_mission_controller.gd")
const ObjectManagerScript := preload("res://scripts/scene_01/scene_01_object_manager.gd")
const StandardBlockScript := preload("res://scripts/objects/standard_block.gd")

var test := ContractTestScript.new()
var mission_transitions: Array[Vector2i] = []
var completion_times: Array[float] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var baseline_root_child_count := root.get_child_count()
	var packed := load(SCENE_PATH) as PackedScene
	test.expect_true(packed != null, "Scene 01 should load for mission integration test.")
	if packed == null:
		test.finish(self, "Scene 01 mission integration tests")
		return

	var scene := packed.instantiate() as MissionControllerScript
	test.expect_true(scene != null, "Scene 01 root should use mission controller.")
	if scene == null:
		test.finish(self, "Scene 01 mission integration tests")
		return
	_bind_mission_events(scene)
	root.add_child(scene)
	await process_frame

	var object_manager := scene.get_node_or_null(
		"SceneRoot/ObjectRoot/Scene01ObjectManager"
	) as ObjectManagerScript
	test.expect_true(object_manager != null, "Mission integration requires Scene01ObjectManager.")
	if object_manager == null:
		await _cleanup(scene)
		test.finish(self, "Scene 01 mission integration tests")
		return
	var standard_box := object_manager.get_standard_box()
	test.expect_true(standard_box != null, "Mission integration requires StandardBox.")
	if standard_box == null:
		await _cleanup(scene)
		test.finish(self, "Scene 01 mission integration tests")
		return

	test.expect_true(scene.is_scene_initialized(), "Scene should initialize before mission gameplay.")
	test.expect_equal(scene.get_lifecycle_state(), LifecycleStateScript.State.READY, "Lifecycle should start READY.")
	test.expect_equal(scene.get_mission_state(), MissionStateScript.State.READY, "Mission should start READY.")
	test.expect_equal(standard_box.get_current_count(), 3, "StandardBox should start at 3/8.")
	test.expect_equal(scene.get_mission_target_count(), 8, "Mission target should use StandardBox capacity.")
	test.expect_float_approx(scene.get_mission_elapsed_time(), 0.0, "Mission elapsed time should start at zero.")

	scene.run_scene()
	test.expect_equal(scene.get_lifecycle_state(), LifecycleStateScript.State.RUNNING, "Run should start lifecycle.")
	test.expect_equal(scene.get_mission_state(), MissionStateScript.State.RUNNING, "Mission should project RUNNING.")
	scene._process(1.0)
	test.expect_float_approx(scene.get_mission_elapsed_time(), 1.0, "Mission time should use lifecycle simulation timer.")

	scene.pause_scene()
	test.expect_equal(scene.get_mission_state(), MissionStateScript.State.PAUSED, "Mission should project PAUSED.")
	var paused_elapsed := scene.get_mission_elapsed_time()
	scene._process(2.0)
	test.expect_float_approx(
		scene.get_mission_elapsed_time(),
		paused_elapsed,
		"Mission time should not advance while lifecycle is PAUSED."
	)

	scene.resume_scene()
	test.expect_equal(scene.get_mission_state(), MissionStateScript.State.RUNNING, "Mission should resume with lifecycle.")
	test.expect_true(scene.set_simulation_speed(2.0), "2x simulation speed should be accepted.")
	scene._process(0.5)
	test.expect_float_approx(
		scene.get_mission_elapsed_time(),
		2.0,
		"Mission time should follow the lifecycle simulation delta at 2x."
	)

	for index in range(5):
		var result := standard_box.put_item(StandardBlockScript.create())
		test.expect_true(result.is_success(), "StandardBox should accept mission block %d." % index)
	test.expect_equal(standard_box.get_current_count(), 8, "Five blocks should fill StandardBox to 8/8.")
	test.expect_true(scene.is_mission_completed(), "Mission should latch completion at 8/8.")
	test.expect_equal(scene.get_mission_state(), MissionStateScript.State.COMPLETED, "Mission should enter COMPLETED.")
	test.expect_equal(completion_times.size(), 1, "Mission completion should emit exactly once.")
	test.expect_float_approx(completion_times[0], 2.0, "Completion should capture current mission time.")

	var frozen_elapsed := scene.get_mission_elapsed_time()
	scene._process(3.0)
	test.expect_true(scene.timer > frozen_elapsed, "Lifecycle timer may continue after mission completion.")
	test.expect_float_approx(
		scene.get_mission_elapsed_time(),
		frozen_elapsed,
		"Mission elapsed time should freeze after completion."
	)
	var removed := standard_box.take_item()
	test.expect_true(removed.is_success(), "Post-completion box mutation should remain a domain operation.")
	test.expect_equal(standard_box.get_current_count(), 7, "Box may fall below target after completion.")
	test.expect_true(scene.is_mission_completed(), "Completion latch should not reopen when count falls below target.")
	test.expect_equal(completion_times.size(), 1, "Completion must not repeat after later box changes.")

	test.expect_true(scene.reset_scene(), "Reset should restore Scene 01 mission state.")
	test.expect_equal(scene.get_lifecycle_state(), LifecycleStateScript.State.READY, "Reset should restore lifecycle READY.")
	test.expect_equal(scene.get_mission_state(), MissionStateScript.State.READY, "Reset should restore mission READY.")
	test.expect_false(scene.is_mission_completed(), "Reset should clear mission completion latch.")
	test.expect_equal(standard_box.get_current_count(), 3, "Reset should restore StandardBox to 3/8.")
	test.expect_float_approx(scene.get_mission_elapsed_time(), 0.0, "Reset should clear mission elapsed time.")

	var scene_instance_id := scene.get_instance_id()
	scene.queue_free()
	await process_frame
	test.expect_false(is_instance_id_valid(scene_instance_id), "Freed mission scene should not remain alive.")
	test.expect_equal(root.get_child_count(), baseline_root_child_count, "Scene teardown should restore root child count.")

	var reentered_scene := packed.instantiate() as MissionControllerScript
	root.add_child(reentered_scene)
	await process_frame
	test.expect_equal(reentered_scene.get_mission_state(), MissionStateScript.State.READY, "Re-entered scene should start mission READY.")
	test.expect_false(reentered_scene.is_mission_completed(), "Re-entered scene should not retain completion latch.")
	test.expect_float_approx(reentered_scene.get_mission_elapsed_time(), 0.0, "Re-entered scene should start with zero mission time.")
	await _cleanup(reentered_scene)

	test.expect_equal(
		mission_transitions,
		[
			Vector2i(MissionStateScript.State.READY, MissionStateScript.State.RUNNING),
			Vector2i(MissionStateScript.State.RUNNING, MissionStateScript.State.PAUSED),
			Vector2i(MissionStateScript.State.PAUSED, MissionStateScript.State.RUNNING),
			Vector2i(MissionStateScript.State.RUNNING, MissionStateScript.State.COMPLETED),
			Vector2i(MissionStateScript.State.COMPLETED, MissionStateScript.State.READY),
		],
		"Mission integration should publish the expected state transitions."
	)
	test.finish(self, "Scene 01 mission integration tests")


func _bind_mission_events(scene: MissionControllerScript) -> void:
	scene.mission_state_changed.connect(_on_mission_state_changed)
	scene.mission_completed.connect(_on_mission_completed)


func _on_mission_state_changed(previous_state: int, current_state: int) -> void:
	mission_transitions.append(Vector2i(previous_state, current_state))


func _on_mission_completed(elapsed_time: float) -> void:
	completion_times.append(elapsed_time)


func _cleanup(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
		await process_frame

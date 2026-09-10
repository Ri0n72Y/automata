extends SceneTree

const ContractTestScript := preload("res://tests/support/contract_test.gd")
const LifecycleStateScript := preload("res://scripts/scene_01/scene_01_lifecycle_state.gd")
const MissionStateScript := preload("res://scripts/scene_01/scene_01_mission_state.gd")

var test := ContractTestScript.new()
var state_transitions: Array[Vector2i] = []
var completion_times: Array[float] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var lifecycle := LifecycleStateScript.new()
	var mission := MissionStateScript.new()
	mission.state_changed.connect(_on_state_changed)
	mission.completed.connect(_on_completed)

	test.expect_equal(
		mission.get_state(lifecycle.get_state()),
		MissionStateScript.State.READY,
		"Mission should project lifecycle READY."
	)
	test.expect_false(
		mission.try_complete(8, 8, 0.0, lifecycle.get_state()),
		"Mission must not complete while lifecycle is READY."
	)

	var previous_lifecycle := lifecycle.get_state()
	test.expect_true(lifecycle.start(), "Lifecycle should enter RUNNING for mission contract test.")
	mission.handle_lifecycle_state_changed(previous_lifecycle, lifecycle.get_state())
	test.expect_equal(
		mission.get_state(lifecycle.get_state()),
		MissionStateScript.State.RUNNING,
		"Mission should project lifecycle RUNNING."
	)

	previous_lifecycle = lifecycle.get_state()
	test.expect_true(lifecycle.pause(), "Lifecycle should pause.")
	mission.handle_lifecycle_state_changed(previous_lifecycle, lifecycle.get_state())
	test.expect_equal(
		mission.get_state(lifecycle.get_state()),
		MissionStateScript.State.PAUSED,
		"Mission should project lifecycle PAUSED."
	)

	previous_lifecycle = lifecycle.get_state()
	test.expect_true(lifecycle.resume(), "Lifecycle should resume.")
	mission.handle_lifecycle_state_changed(previous_lifecycle, lifecycle.get_state())
	test.expect_false(
		mission.try_complete(7, 8, 2.0, lifecycle.get_state()),
		"Mission should stay incomplete below target."
	)
	test.expect_true(
		mission.try_complete(8, 8, 2.5, lifecycle.get_state()),
		"Mission should complete when target is first reached while RUNNING."
	)
	test.expect_true(mission.is_completed(), "Completion latch should be set.")
	test.expect_equal(
		mission.get_state(lifecycle.get_state()),
		MissionStateScript.State.COMPLETED,
		"Completed mission should override lifecycle projection."
	)
	test.expect_float_approx(
		mission.get_elapsed_time(99.0),
		2.5,
		"Completed mission should freeze elapsed time at completion."
	)
	test.expect_false(
		mission.try_complete(9, 8, 4.0, lifecycle.get_state()),
		"Completion should latch exactly once."
	)
	test.expect_equal(completion_times.size(), 1, "Completion signal should emit exactly once.")

	previous_lifecycle = lifecycle.get_state()
	test.expect_true(lifecycle.pause(), "Lifecycle may still pause after mission completion.")
	mission.handle_lifecycle_state_changed(previous_lifecycle, lifecycle.get_state())
	test.expect_equal(
		mission.get_state(lifecycle.get_state()),
		MissionStateScript.State.COMPLETED,
		"Lifecycle changes after completion must not clear mission completion."
	)

	previous_lifecycle = lifecycle.get_state()
	lifecycle.reset()
	mission.handle_lifecycle_state_changed(previous_lifecycle, lifecycle.get_state())
	mission.reset(lifecycle.get_state())
	test.expect_false(mission.is_completed(), "Reset should clear completion latch.")
	test.expect_equal(
		mission.get_state(lifecycle.get_state()),
		MissionStateScript.State.READY,
		"Reset mission should project lifecycle READY."
	)
	test.expect_float_approx(mission.get_elapsed_time(0.0), 0.0, "Reset should clear completion time.")

	test.expect_equal(
		state_transitions,
		[
			Vector2i(MissionStateScript.State.READY, MissionStateScript.State.RUNNING),
			Vector2i(MissionStateScript.State.RUNNING, MissionStateScript.State.PAUSED),
			Vector2i(MissionStateScript.State.PAUSED, MissionStateScript.State.RUNNING),
			Vector2i(MissionStateScript.State.RUNNING, MissionStateScript.State.COMPLETED),
			Vector2i(MissionStateScript.State.COMPLETED, MissionStateScript.State.READY),
		],
		"Mission should publish only projected lifecycle transitions plus completion/reset."
	)
	test.finish(self, "Scene 01 mission state contract tests")


func _on_state_changed(previous_state: int, current_state: int) -> void:
	state_transitions.append(Vector2i(previous_state, current_state))


func _on_completed(elapsed_time: float) -> void:
	completion_times.append(elapsed_time)

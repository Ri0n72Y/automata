extends SceneTree

const ContractTestScript := preload("res://tests/support/contract_test.gd")
const MissionStateScript := preload("res://scripts/scene_01/scene_01_mission_state.gd")

var test := ContractTestScript.new()
var completion_times: Array[float] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var mission := MissionStateScript.new()
	mission.completed.connect(_on_completed)

	test.expect_false(mission.is_completed(), "Mission should start incomplete.")
	test.expect_false(
		mission.try_complete(7, 8, 2.0),
		"Mission should stay incomplete below target."
	)
	test.expect_true(
		mission.try_complete(8, 8, 2.5),
		"Mission should complete when target is first reached."
	)
	test.expect_true(mission.is_completed(), "Completion latch should be set.")
	test.expect_float_approx(
		mission.get_elapsed_time(99.0),
		2.5,
		"Completed mission should freeze elapsed time at completion."
	)
	test.expect_false(
		mission.try_complete(9, 8, 4.0),
		"Completion should latch exactly once."
	)
	test.expect_equal(completion_times.size(), 1, "Completion signal should emit exactly once.")

	mission.reset()
	test.expect_false(mission.is_completed(), "Reset should clear completion latch.")
	test.expect_float_approx(mission.get_elapsed_time(0.0), 0.0, "Reset should clear completion time.")
	test.finish(self, "Scene 01 mission state contract tests")


func _on_completed(elapsed_time: float) -> void:
	completion_times.append(elapsed_time)

extends SceneTree

const ScoreTrackerScript := preload("res://scripts/scene_01/scene_01_score_tracker.gd")
const MissionControllerScript := preload("res://scripts/scene_01/scene_01_mission_controller.gd")

var failures := 0


func _init() -> void:
	_test_runtime_accounting()
	_finish()


func _test_runtime_accounting() -> void:
	var scene := MissionControllerScript.new()
	var score := ScoreTrackerScript.new()
	score.set("_scene_controller", scene)

	scene.timer = 1.0
	score.call("_start_manual", 1.0)
	scene.timer = 3.0
	_expect_near(score.get_manual_runtime(), 2.0, 0.0001, "Active manual segment should use Mission time.")

	score.call("_stop_manual", 3.0)
	scene.timer = 5.0
	_expect_near(score.get_manual_runtime(), 2.0, 0.0001, "Stopped manual segment should remain frozen.")

	score.call("_start_automated", 5.0)
	scene.timer = 8.0
	_expect_near(score.get_automated_runtime(), 3.0, 0.0001, "Active automated segment should use Mission time.")
	_expect_near(score.get_automation_rate(), 0.6, 0.0001, "Automation rate should use manual + automated runtime.")

	score.call("_on_mission_completed", 8.0)
	scene.timer = 10.0
	_expect_near(score.get_manual_runtime(), 2.0, 0.0001, "Mission completion should freeze manual runtime.")
	_expect_near(score.get_automated_runtime(), 3.0, 0.0001, "Mission completion should freeze automated runtime.")
	_expect_near(score.get_automation_rate(), 0.6, 0.0001, "Mission completion should freeze automation ratio.")

	score.set("_component_count", 7)
	score.set("_components_captured", true)
	score.call("_on_lifecycle_reset_completed")
	_expect_false(score.has_component_count(), "Reset should clear component snapshot.")
	_expect_equal(score.get_component_count(), 0, "Reset should clear component count.")
	_expect_near(score.get_manual_runtime(), 0.0, 0.0001, "Reset should clear manual runtime.")
	_expect_near(score.get_automated_runtime(), 0.0, 0.0001, "Reset should clear automated runtime.")
	_expect_near(score.get_automation_rate(), 0.0, 0.0001, "Reset should clear automation ratio.")

	score.free()
	scene.free()


func _finish() -> void:
	if failures == 0:
		print("Scene 01 scoring owner contract tests passed.")
		quit(0)
		return
	push_error("Scene 01 scoring owner contract tests failed: %d failure(s)." % failures)
	quit(1)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures += 1
		push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])


func _expect_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		failures += 1
		push_error("%s Expected %.4f ± %.4f, got %.4f." % [message, expected, tolerance, actual])


func _expect_false(value: bool, message: String) -> void:
	if value:
		failures += 1
		push_error(message)

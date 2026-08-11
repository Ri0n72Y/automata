extends SceneTree

const LifecycleStateScript := preload("res://scripts/scene_01/scene_01_lifecycle_state.gd")

var failures: int = 0
var state_transitions: Array[Vector2i] = []
var speed_transitions: Array[Vector2] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var lifecycle := LifecycleStateScript.new()
	lifecycle.state_changed.connect(_on_state_changed)
	lifecycle.simulation_speed_changed.connect(_on_speed_changed)

	_expect_equal(lifecycle.get_state(), LifecycleStateScript.State.READY, "Lifecycle should start READY.")
	_expect_equal(lifecycle.get_simulation_speed(), 1.0, "Lifecycle should start at 1x.")
	_expect_true(lifecycle.start(), "READY should start.")
	_expect_true(lifecycle.is_running(), "Start should enter RUNNING.")
	_expect_false(lifecycle.start(), "RUNNING should reject duplicate start.")
	_expect_true(lifecycle.pause(), "RUNNING should pause.")
	_expect_true(lifecycle.is_paused(), "Pause should enter PAUSED.")
	_expect_false(lifecycle.pause(), "PAUSED should reject duplicate pause.")
	_expect_true(lifecycle.resume(), "PAUSED should resume.")
	_expect_true(lifecycle.is_running(), "Resume should return to RUNNING.")

	_expect_equal(lifecycle.cycle_simulation_speed(), 2.0, "1x should cycle to 2x.")
	_expect_equal(lifecycle.cycle_simulation_speed(), 4.0, "2x should cycle to 4x.")
	_expect_equal(lifecycle.cycle_simulation_speed(), 0.5, "4x should cycle to 0.5x.")
	_expect_equal(lifecycle.cycle_simulation_speed(), 1.0, "0.5x should cycle to 1x.")
	_expect_false(lifecycle.set_simulation_speed(3.0), "Unsupported speed should be rejected.")
	_expect_equal(lifecycle.get_simulation_speed(), 1.0, "Rejected speed should not mutate state.")

	lifecycle.set_simulation_speed(4.0)
	lifecycle.pause()
	lifecycle.reset()
	_expect_equal(lifecycle.get_state(), LifecycleStateScript.State.READY, "Reset should return READY.")
	_expect_equal(lifecycle.get_simulation_speed(), 1.0, "Reset should restore 1x.")
	lifecycle.reset()
	_expect_equal(lifecycle.get_state(), LifecycleStateScript.State.READY, "Repeated reset should remain READY.")
	_expect_equal(lifecycle.get_simulation_speed(), 1.0, "Repeated reset should remain 1x.")

	_expect_true(state_transitions.size() >= 4, "Lifecycle should publish real state transitions.")
	_expect_true(speed_transitions.size() >= 5, "Lifecycle should publish real speed transitions.")
	_finish()


func _on_state_changed(previous_state: int, current_state: int) -> void:
	state_transitions.append(Vector2i(previous_state, current_state))


func _on_speed_changed(previous_speed: float, current_speed: float) -> void:
	speed_transitions.append(Vector2(previous_speed, current_speed))


func _finish() -> void:
	if failures == 0:
		print("Scene 01 lifecycle state smoke tests passed.")
		quit(0)
		return
	push_error("Scene 01 lifecycle state smoke tests failed: %d failure(s)." % failures)
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
	if not value:
		return
	failures += 1
	push_error(message)

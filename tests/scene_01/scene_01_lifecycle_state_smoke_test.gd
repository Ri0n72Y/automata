extends SceneTree

const LifecycleStateScript := preload("res://scripts/scene_01/scene_01_lifecycle_state.gd")

var failures: int = 0
var state_transitions: Array[Vector2i] = []
var speed_transitions: Array[Vector2] = []
var event_sequence: Array[Dictionary] = []


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

	_expect_true(lifecycle.set_simulation_speed(4.0), "4x should be accepted before reset ordering test.")
	_expect_true(lifecycle.pause(), "RUNNING should pause before reset ordering test.")
	event_sequence.clear()
	lifecycle.reset()
	_expect_equal(lifecycle.get_state(), LifecycleStateScript.State.READY, "Reset should return READY.")
	_expect_equal(lifecycle.get_simulation_speed(), 1.0, "Reset should restore 1x.")
	_expect_equal(
		event_sequence,
		[
			{"kind": "speed", "previous": 4.0, "current": 1.0},
			{
				"kind": "state",
				"previous": LifecycleStateScript.State.PAUSED,
				"current": LifecycleStateScript.State.READY,
			},
		],
		"Reset should publish speed restoration before READY state transition."
	)
	lifecycle.reset()
	_expect_equal(lifecycle.get_state(), LifecycleStateScript.State.READY, "Repeated reset should remain READY.")
	_expect_equal(lifecycle.get_simulation_speed(), 1.0, "Repeated reset should remain 1x.")
	_expect_equal(
		event_sequence.size(),
		2,
		"Repeated reset in READY + 1x should not publish duplicate state or speed transitions."
	)

	var expected_state_transitions: Array[Vector2i] = [
		Vector2i(LifecycleStateScript.State.READY, LifecycleStateScript.State.RUNNING),
		Vector2i(LifecycleStateScript.State.RUNNING, LifecycleStateScript.State.PAUSED),
		Vector2i(LifecycleStateScript.State.PAUSED, LifecycleStateScript.State.RUNNING),
		Vector2i(LifecycleStateScript.State.RUNNING, LifecycleStateScript.State.PAUSED),
		Vector2i(LifecycleStateScript.State.PAUSED, LifecycleStateScript.State.READY),
	]
	var expected_speed_transitions: Array[Vector2] = [
		Vector2(1.0, 2.0),
		Vector2(2.0, 4.0),
		Vector2(4.0, 0.5),
		Vector2(0.5, 1.0),
		Vector2(1.0, 4.0),
		Vector2(4.0, 1.0),
	]
	_expect_equal(
		state_transitions,
		expected_state_transitions,
		"Lifecycle state transition payloads and order should remain stable."
	)
	_expect_equal(
		speed_transitions,
		expected_speed_transitions,
		"Simulation speed transition payloads and order should remain stable."
	)
	_finish()


func _on_state_changed(previous_state: int, current_state: int) -> void:
	state_transitions.append(Vector2i(previous_state, current_state))
	event_sequence.append(
		{"kind": "state", "previous": previous_state, "current": current_state}
	)


func _on_speed_changed(previous_speed: float, current_speed: float) -> void:
	speed_transitions.append(Vector2(previous_speed, current_speed))
	event_sequence.append(
		{"kind": "speed", "previous": previous_speed, "current": current_speed}
	)


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

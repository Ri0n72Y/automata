extends SceneTree

const MOVE_COMMAND_SCRIPT := preload("res://scripts/vehicles/move_command.gd")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var command := MOVE_COMMAND_SCRIPT.new()
	command.configure(Vector2i(3, 0), [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)])

	_expect_equal(command.state, MOVE_COMMAND_SCRIPT.State.MOVING, "A valid path starts moving.")
	_expect_equal(command.get_current_anchor(), Vector2i(0, 0), "Command starts at first anchor.")

	command.advance()
	command.advance()
	_expect_equal(command.get_current_anchor(), Vector2i(2, 0), "Advance consumes path nodes.")

	command.advance()
	_expect_equal(command.state, MOVE_COMMAND_SCRIPT.State.WAITING, "Last node completes command.")
	_expect_true(command.is_finished(), "Finished command should report waiting state.")

	var blocked := MOVE_COMMAND_SCRIPT.new()
	blocked.configure(Vector2i(1, 1), [])
	_expect_equal(blocked.state, MOVE_COMMAND_SCRIPT.State.BLOCKED, "Empty path blocks command.")

	_finish()


func _finish() -> void:
	if failures == 0:
		print("MoveCommand smoke tests passed.")
		quit(0)
		return
	push_error("MoveCommand smoke tests failed: %d failure(s)." % failures)
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

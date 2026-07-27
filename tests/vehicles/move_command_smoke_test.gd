extends SceneTree

const MOVE_COMMAND_SCRIPT := preload("res://scripts/vehicles/move_command.gd")

var failures: int = 0


func _init() -> void:
	var command := MOVE_COMMAND_SCRIPT.new()
	_expect_true(
		command.configure(
			Vector2i(2, 0),
			[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]
		),
		"A valid path should configure."
	)
	_expect_equal(command.state, MOVE_COMMAND_SCRIPT.State.MOVING, "A multi-step path starts Moving.")
	_expect_equal(command.get_current_anchor(), Vector2i(0, 0), "Command starts at the first anchor.")
	_expect_equal(command.get_next_anchor(), Vector2i(1, 0), "Command exposes the next anchor.")

	_expect_true(not command.advance(), "Reaching an intermediate node should not finish the command.")
	_expect_equal(command.path_index, 1, "One advance should consume exactly one node.")
	_expect_equal(command.state, MOVE_COMMAND_SCRIPT.State.MOVING, "Intermediate nodes keep Moving state.")
	_expect_equal(command.get_current_anchor(), Vector2i(1, 0), "Current anchor should advance to the intermediate node.")

	_expect_true(command.advance(), "Reaching the final node should finish the command.")
	_expect_equal(command.path_index, 2, "Final advance should select the target node.")
	_expect_equal(command.state, MOVE_COMMAND_SCRIPT.State.WAITING, "Final node enters Waiting.")
	_expect_true(command.is_finished(), "Finished command should report true.")

	var same_anchor := MOVE_COMMAND_SCRIPT.new()
	_expect_true(
		same_anchor.configure(Vector2i(3, 3), [Vector2i(3, 3)]),
		"A one-anchor path should configure as an already-complete move."
	)
	_expect_equal(same_anchor.state, MOVE_COMMAND_SCRIPT.State.WAITING, "One-anchor path is Waiting.")

	var empty_path := MOVE_COMMAND_SCRIPT.new()
	_expect_true(not empty_path.configure(Vector2i(1, 1), []), "An empty path should be rejected.")
	_expect_true(empty_path.is_blocked(), "An empty path should enter Blocked.")

	var mismatched_target := MOVE_COMMAND_SCRIPT.new()
	_expect_true(
		not mismatched_target.configure(
			Vector2i(4, 4),
			[Vector2i(1, 1), Vector2i(2, 1)]
		),
		"A path that does not end at the target should be rejected."
	)
	_expect_true(mismatched_target.is_blocked(), "Mismatched target should enter Blocked.")

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

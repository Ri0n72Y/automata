extends SceneTree

const MOVE_COMMAND_SCRIPT := preload("res://scripts/vehicles/move_command.gd")
const CONTRACT_TEST_SCRIPT := preload("res://tests/support/contract_test.gd")

var test := CONTRACT_TEST_SCRIPT.new()


func _init() -> void:
	var cases: Array[Dictionary] = [
		{
			"name": "empty path is blocked",
			"target": Vector2i(1, 1),
			"path": [],
			"configured": false,
			"initial_state": MOVE_COMMAND_SCRIPT.State.BLOCKED,
			"transitions": [],
		},
		{
			"name": "path endpoint must match target",
			"target": Vector2i(4, 4),
			"path": [Vector2i(1, 1), Vector2i(2, 1)],
			"configured": false,
			"initial_state": MOVE_COMMAND_SCRIPT.State.BLOCKED,
			"transitions": [],
		},
		{
			"name": "duplicate adjacent anchor is blocked",
			"target": Vector2i(1, 1),
			"path": [Vector2i(1, 1), Vector2i(1, 1)],
			"configured": false,
			"initial_state": MOVE_COMMAND_SCRIPT.State.BLOCKED,
			"transitions": [],
		},
		{
			"name": "diagonal step is blocked",
			"target": Vector2i(2, 2),
			"path": [Vector2i(1, 1), Vector2i(2, 2)],
			"configured": false,
			"initial_state": MOVE_COMMAND_SCRIPT.State.BLOCKED,
			"transitions": [],
		},
		{
			"name": "multi-cell jump is blocked",
			"target": Vector2i(4, 1),
			"path": [Vector2i(1, 1), Vector2i(4, 1)],
			"configured": false,
			"initial_state": MOVE_COMMAND_SCRIPT.State.BLOCKED,
			"transitions": [],
		},
		{
			"name": "single-anchor path is already complete",
			"target": Vector2i(3, 3),
			"path": [Vector2i(3, 3)],
			"configured": true,
			"initial_state": MOVE_COMMAND_SCRIPT.State.WAITING,
			"transitions": [
				{"finished": false, "index": 0, "state": MOVE_COMMAND_SCRIPT.State.WAITING, "current": Vector2i(3, 3), "next": Vector2i(3, 3)},
			],
		},
		{
			"name": "one segment completes on first advance",
			"target": Vector2i(2, 1),
			"path": [Vector2i(1, 1), Vector2i(2, 1)],
			"configured": true,
			"initial_state": MOVE_COMMAND_SCRIPT.State.MOVING,
			"transitions": [
				{"finished": true, "index": 1, "state": MOVE_COMMAND_SCRIPT.State.WAITING, "current": Vector2i(2, 1), "next": Vector2i(2, 1)},
			],
		},
		{
			"name": "multi-segment path remains moving at intermediate anchors",
			"target": Vector2i(2, 0),
			"path": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
			"configured": true,
			"initial_state": MOVE_COMMAND_SCRIPT.State.MOVING,
			"transitions": [
				{"finished": false, "index": 1, "state": MOVE_COMMAND_SCRIPT.State.MOVING, "current": Vector2i(1, 0), "next": Vector2i(2, 0)},
				{"finished": true, "index": 2, "state": MOVE_COMMAND_SCRIPT.State.WAITING, "current": Vector2i(2, 0), "next": Vector2i(2, 0)},
			],
		},
	]
	for case in cases:
		_run_case(case)
	_test_explicit_block_transition()
	test.finish(self, "MoveCommand state machine tests")


func _run_case(case: Dictionary) -> void:
	var target: Vector2i = case["target"]
	var planned_path: Array[Vector2i] = []
	planned_path.assign(case["path"])
	var expected_configured: bool = case["configured"]
	var expected_initial_state: int = case["initial_state"]
	var context: String = case["name"]
	var command := MOVE_COMMAND_SCRIPT.new()
	var configured: bool = command.configure(target, planned_path)
	test.expect_equal(configured, expected_configured, "%s configuration result." % context)
	test.expect_equal(command.state, expected_initial_state, "%s initial state." % context)
	test.expect_equal(command.target_anchor, target, "%s target anchor." % context)
	test.expect_equal(command.path, planned_path, "%s stores a path copy." % context)
	if command.path.is_empty():
		test.expect_equal(command.get_current_anchor(), Vector2i.ZERO, "%s empty current anchor." % context)
		test.expect_equal(command.get_next_anchor(), Vector2i.ZERO, "%s empty next anchor." % context)
	else:
		test.expect_equal(command.get_current_anchor(), command.path.front(), "%s starts at path index zero." % context)

	var transitions: Array[Dictionary] = []
	transitions.assign(case["transitions"])
	for transition in transitions:
		var finished: bool = command.advance()
		test.expect_equal(finished, bool(transition["finished"]), "%s advance result." % context)
		test.expect_equal(command.path_index, int(transition["index"]), "%s path index." % context)
		test.expect_equal(command.state, int(transition["state"]), "%s state after advance." % context)
		test.expect_equal(command.get_current_anchor(), transition["current"], "%s current anchor after advance." % context)
		test.expect_equal(command.get_next_anchor(), transition["next"], "%s next anchor after advance." % context)

	test.expect_equal(command.is_finished(), command.state == MOVE_COMMAND_SCRIPT.State.WAITING, "%s finished predicate." % context)
	test.expect_equal(command.is_blocked(), command.state == MOVE_COMMAND_SCRIPT.State.BLOCKED, "%s blocked predicate." % context)


func _test_explicit_block_transition() -> void:
	var command := MOVE_COMMAND_SCRIPT.new()
	test.expect_true(
		command.configure(Vector2i(2, 1), [Vector2i(1, 1), Vector2i(2, 1)]),
		"A valid command should configure before explicit blocking."
	)
	command.block()
	test.expect_equal(command.state, MOVE_COMMAND_SCRIPT.State.BLOCKED, "Explicit block should enter Blocked.")
	test.expect_false(command.advance(), "Blocked commands should not advance.")
	test.expect_equal(command.path_index, 0, "Blocked commands should preserve their last reached index.")

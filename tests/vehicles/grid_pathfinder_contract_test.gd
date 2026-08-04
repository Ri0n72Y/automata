extends SceneTree

const GRID_PATHFINDER_SCRIPT := preload("res://scripts/vehicles/grid_pathfinder.gd")
const CONTRACT_TEST_SCRIPT := preload("res://tests/support/contract_test.gd")

var test := CONTRACT_TEST_SCRIPT.new()


func _init() -> void:
	var one_cell_door := _vertical_wall_with_opening(Vector2i(7, 5), 3, 2)
	var cases: Array[Dictionary] = [
		{
			"name": "same start and goal",
			"start": Vector2i(1, 1),
			"goal": Vector2i(1, 1),
			"footprint": Vector2i(2, 2),
			"grid_size": Vector2i(8, 6),
			"blocked": [],
			"reachable": true,
			"expected_size": 1,
		},
		{
			"name": "adjacent 1x1 goal",
			"start": Vector2i(1, 1),
			"goal": Vector2i(2, 1),
			"footprint": Vector2i.ONE,
			"grid_size": Vector2i(8, 6),
			"blocked": [],
			"reachable": true,
			"expected_size": 2,
		},
		{
			"name": "straight 2x2 shortest path",
			"start": Vector2i(1, 1),
			"goal": Vector2i(4, 1),
			"footprint": Vector2i(2, 2),
			"grid_size": Vector2i(8, 6),
			"blocked": [],
			"reachable": true,
			"expected_size": 4,
		},
		{
			"name": "2x2 detour around a partial wall",
			"start": Vector2i(0, 0),
			"goal": Vector2i(5, 0),
			"footprint": Vector2i(2, 2),
			"grid_size": Vector2i(8, 6),
			"blocked": [Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3)],
			"reachable": true,
			"expected_size": 14,
		},
		{
			"name": "complete wall is unreachable",
			"start": Vector2i(0, 0),
			"goal": Vector2i(5, 0),
			"footprint": Vector2i(2, 2),
			"grid_size": Vector2i(8, 6),
			"blocked": [Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 4), Vector2i(3, 5)],
			"reachable": false,
		},
		{
			"name": "one blocked target footprint cell rejects the goal",
			"start": Vector2i(0, 0),
			"goal": Vector2i(4, 0),
			"footprint": Vector2i(2, 2),
			"grid_size": Vector2i(8, 6),
			"blocked": [Vector2i(5, 1)],
			"reachable": false,
		},
		{
			"name": "blocked start footprint is rejected",
			"start": Vector2i(1, 1),
			"goal": Vector2i(4, 1),
			"footprint": Vector2i(2, 2),
			"grid_size": Vector2i(8, 6),
			"blocked": [Vector2i(1, 1)],
			"reachable": false,
		},
		{
			"name": "goal anchor whose footprint exceeds bounds is rejected",
			"start": Vector2i.ZERO,
			"goal": Vector2i(7, 5),
			"footprint": Vector2i(2, 2),
			"grid_size": Vector2i(8, 6),
			"blocked": [],
			"reachable": false,
		},
		{
			"name": "negative start anchor is rejected",
			"start": Vector2i(-1, 0),
			"goal": Vector2i(2, 0),
			"footprint": Vector2i.ONE,
			"grid_size": Vector2i(8, 6),
			"blocked": [],
			"reachable": false,
		},
		{
			"name": "zero grid size is rejected",
			"start": Vector2i.ZERO,
			"goal": Vector2i.ZERO,
			"footprint": Vector2i.ONE,
			"grid_size": Vector2i.ZERO,
			"blocked": [],
			"reachable": false,
		},
		{
			"name": "footprint larger than grid is rejected",
			"start": Vector2i.ZERO,
			"goal": Vector2i.ZERO,
			"footprint": Vector2i(9, 1),
			"grid_size": Vector2i(8, 6),
			"blocked": [],
			"reachable": false,
		},
		{
			"name": "1x1 vehicle passes a one-cell doorway between valid rooms",
			"start": Vector2i(1, 2),
			"goal": Vector2i(5, 2),
			"footprint": Vector2i.ONE,
			"grid_size": Vector2i(7, 5),
			"blocked": one_cell_door,
			"reachable": true,
			"expected_size": 5,
		},
		{
			"name": "2x2 vehicle cannot pass a one-cell doorway despite valid endpoints",
			"start": Vector2i(0, 1),
			"goal": Vector2i(5, 1),
			"footprint": Vector2i(2, 2),
			"grid_size": Vector2i(7, 5),
			"blocked": one_cell_door,
			"reachable": false,
		},
	]
	for case in cases:
		_run_case(case)
	test.finish(self, "Grid pathfinder contract tests")


func _run_case(case: Dictionary) -> void:
	var blocked_lookup: Dictionary = {}
	for cell in case["blocked"]:
		blocked_lookup[cell] = true
	var walkable := func(anchor: Vector2i, footprint: Vector2i) -> bool:
		for offset_y in range(footprint.y):
			for offset_x in range(footprint.x):
				if blocked_lookup.has(anchor + Vector2i(offset_x, offset_y)):
					return false
		return true

	var pathfinder := GRID_PATHFINDER_SCRIPT.new()
	var path: Array[Vector2i] = pathfinder.find_path(
		case["start"],
		case["goal"],
		case["footprint"],
		case["grid_size"],
		walkable
	)
	var context: String = case["name"]
	if not case["reachable"]:
		test.expect_true(path.is_empty(), "%s should return an empty path." % context)
		return

	test.expect_false(path.is_empty(), "%s should return a path." % context)
	if path.is_empty():
		return
	test.expect_equal(path.front(), case["start"], "%s should include the start anchor." % context)
	test.expect_equal(path.back(), case["goal"], "%s should include the goal anchor." % context)
	if case.has("expected_size"):
		test.expect_equal(path.size(), case["expected_size"], "%s should use the shortest path length." % context)
	_expect_path_invariants(path, case["footprint"], case["grid_size"], walkable, context)


func _expect_path_invariants(
	path: Array[Vector2i],
	footprint: Vector2i,
	grid_size: Vector2i,
	walkable: Callable,
	context: String
) -> void:
	for index in range(path.size()):
		var anchor := path[index]
		test.expect_true(
			_anchor_fits_grid(anchor, footprint, grid_size),
			"%s should keep every footprint inside the grid." % context
		)
		test.expect_true(
			walkable.call(anchor, footprint),
			"%s should keep every footprint on walkable cells." % context
		)
		if index == 0:
			continue
		var delta := path[index] - path[index - 1]
		test.expect_equal(
			absi(delta.x) + absi(delta.y),
			1,
			"%s should use cardinal adjacent steps." % context
		)


func _anchor_fits_grid(anchor: Vector2i, footprint: Vector2i, grid_size: Vector2i) -> bool:
	return (
		anchor.x >= 0
		and anchor.y >= 0
		and footprint.x > 0
		and footprint.y > 0
		and anchor.x + footprint.x <= grid_size.x
		and anchor.y + footprint.y <= grid_size.y
	)


func _vertical_wall_with_opening(
	grid_size: Vector2i,
	wall_x: int,
	opening_y: int
) -> Array[Vector2i]:
	var blocked: Array[Vector2i] = []
	for y in range(grid_size.y):
		if y == opening_y:
			continue
		blocked.append(Vector2i(wall_x, y))
	return blocked

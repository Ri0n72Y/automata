extends SceneTree

const GRID_PATHFINDER_SCRIPT := preload("res://scripts/vehicles/grid_pathfinder.gd")
const GRID_SIZE := Vector2i(8, 6)
const VEHICLE_FOOTPRINT := Vector2i(2, 2)

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var pathfinder := GRID_PATHFINDER_SCRIPT.new()
	var blocked_cells: Dictionary = {}
	var is_walkable := func(anchor: Vector2i, footprint: Vector2i) -> bool:
		for offset_y in range(footprint.y):
			for offset_x in range(footprint.x):
				var cell := anchor + Vector2i(offset_x, offset_y)
				if blocked_cells.has(cell):
					return false
		return true

	var direct_path: Array[Vector2i] = pathfinder.find_path(
		Vector2i(1, 1), Vector2i(4, 1), VEHICLE_FOOTPRINT, GRID_SIZE, is_walkable
	)
	_expect_true(not direct_path.is_empty(), "Straight movement should produce a path.")
	if not direct_path.is_empty():
		_expect_equal(direct_path.front(), Vector2i(1, 1), "Path should include its start anchor.")
		_expect_equal(direct_path.back(), Vector2i(4, 1), "Path should include its target anchor.")
		_expect_equal(direct_path.size(), 4, "Straight movement should use the shortest cardinal path.")
		_expect_cardinal_steps(direct_path)

	for y in range(0, 4):
		blocked_cells[Vector2i(3, y)] = true
	var detour_path: Array[Vector2i] = pathfinder.find_path(
		Vector2i(0, 0), Vector2i(5, 0), VEHICLE_FOOTPRINT, GRID_SIZE, is_walkable
	)
	_expect_true(not detour_path.is_empty(), "A 2x2 vehicle should route around a partial wall.")
	if not detour_path.is_empty():
		_expect_equal(detour_path.front(), Vector2i(0, 0), "Detour should preserve its start anchor.")
		_expect_equal(detour_path.back(), Vector2i(5, 0), "Detour should reach its target anchor.")
		_expect_cardinal_steps(detour_path)
		for anchor in detour_path:
			_expect_true(is_walkable.call(anchor, VEHICLE_FOOTPRINT), "Every path anchor must fit the full footprint.")

	blocked_cells.clear()
	blocked_cells[Vector2i(5, 1)] = true
	var blocked_target: Array[Vector2i] = pathfinder.find_path(
		Vector2i(0, 0), Vector2i(4, 0), VEHICLE_FOOTPRINT, GRID_SIZE, is_walkable
	)
	_expect_true(blocked_target.is_empty(), "A target intersecting one blocked footprint cell must fail.")

	var always_walkable := func(_anchor: Vector2i, _footprint: Vector2i) -> bool:
		return true
	var out_of_bounds: Array[Vector2i] = pathfinder.find_path(
		Vector2i(0, 0), Vector2i(7, 5), VEHICLE_FOOTPRINT, GRID_SIZE, always_walkable
	)
	_expect_true(
		out_of_bounds.is_empty(),
		"Pathfinder must reject an out-of-bounds target even when the callback always returns true."
	)
	var negative_target: Array[Vector2i] = pathfinder.find_path(
		Vector2i(0, 0), Vector2i(-1, 0), VEHICLE_FOOTPRINT, GRID_SIZE, always_walkable
	)
	_expect_true(negative_target.is_empty(), "Negative anchors must be rejected by pathfinder bounds.")

	blocked_cells.clear()
	for y in range(GRID_SIZE.y):
		blocked_cells[Vector2i(3, y)] = true
	var unreachable: Array[Vector2i] = pathfinder.find_path(
		Vector2i(0, 0), Vector2i(5, 0), VEHICLE_FOOTPRINT, GRID_SIZE, is_walkable
	)
	_expect_true(unreachable.is_empty(), "A complete wall should make the target unreachable.")

	blocked_cells.clear()
	var same_cell: Array[Vector2i] = pathfinder.find_path(
		Vector2i(1, 1), Vector2i(1, 1), VEHICLE_FOOTPRINT, GRID_SIZE, is_walkable
	)
	_expect_equal(same_cell, [Vector2i(1, 1)], "Start equal to target should return a one-anchor path.")

	var invalid_grid: Array[Vector2i] = pathfinder.find_path(
		Vector2i.ZERO, Vector2i.ZERO, Vector2i.ONE, Vector2i.ZERO, always_walkable
	)
	_expect_true(invalid_grid.is_empty(), "Invalid grid sizes must return an empty path.")
	var oversized_footprint: Array[Vector2i] = pathfinder.find_path(
		Vector2i.ZERO, Vector2i.ZERO, Vector2i(9, 1), GRID_SIZE, always_walkable
	)
	_expect_true(oversized_footprint.is_empty(), "A footprint larger than the grid must fail.")

	_finish()


func _expect_cardinal_steps(path: Array[Vector2i]) -> void:
	for index in range(1, path.size()):
		var delta := path[index] - path[index - 1]
		_expect_equal(abs(delta.x) + abs(delta.y), 1, "Path steps must be cardinal and adjacent.")


func _finish() -> void:
	if failures == 0:
		print("Grid pathfinder smoke tests passed.")
		quit(0)
		return
	push_error("Grid pathfinder smoke tests failed: %d failure(s)." % failures)
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

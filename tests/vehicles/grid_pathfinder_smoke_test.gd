extends SceneTree

const GRID_PATHFINDER_SCRIPT := preload("res://scripts/vehicles/grid_pathfinder.gd")
const GRID_SIZE := Vector2i(8, 6)
const VEHICLE_FOOTPRINT := Vector2i(2, 2)

var failures: int = 0


func _init() -> void:
	var pathfinder := GRID_PATHFINDER_SCRIPT.new()
	var blocked_cells: Dictionary = {}
	var is_walkable := func(anchor: Vector2i, footprint: Vector2i) -> bool:
		for offset_y in range(footprint.y):
			for offset_x in range(footprint.x):
				if blocked_cells.has(anchor + Vector2i(offset_x, offset_y)):
					return false
		return true

	var direct_path: Array[Vector2i] = pathfinder.find_path(
		Vector2i(1, 1), Vector2i(4, 1), VEHICLE_FOOTPRINT, GRID_SIZE, is_walkable
	)
	_expect_true(not direct_path.is_empty(), "Straight movement should produce a path.")
	if not direct_path.is_empty():
		_expect_equal(direct_path.front(), Vector2i(1, 1), "Path should include its start anchor.")
		_expect_equal(direct_path.back(), Vector2i(4, 1), "Path should include its target anchor.")
		_expect_equal(direct_path.size(), 4, "Straight movement should use the shortest path.")
		_expect_cardinal_steps(direct_path)

	for y in range(0, 4):
		blocked_cells[Vector2i(3, y)] = true
	var detour_path: Array[Vector2i] = pathfinder.find_path(
		Vector2i(0, 0), Vector2i(5, 0), VEHICLE_FOOTPRINT, GRID_SIZE, is_walkable
	)
	_expect_true(not detour_path.is_empty(), "A 2x2 vehicle should route around a partial wall.")
	if not detour_path.is_empty():
		_expect_equal(detour_path.back(), Vector2i(5, 0), "Detour should reach its target.")
		_expect_cardinal_steps(detour_path)
		for anchor in detour_path:
			_expect_true(is_walkable.call(anchor, VEHICLE_FOOTPRINT), "Every anchor must fit the footprint.")

	blocked_cells.clear()
	blocked_cells[Vector2i(5, 1)] = true
	var blocked_target: Array[Vector2i] = pathfinder.find_path(
		Vector2i(0, 0), Vector2i(4, 0), VEHICLE_FOOTPRINT, GRID_SIZE, is_walkable
	)
	_expect_true(blocked_target.is_empty(), "One blocked footprint cell must reject the target.")

	var always_walkable := func(_anchor: Vector2i, _footprint: Vector2i) -> bool:
		return true
	_expect_true(
		pathfinder.find_path(
			Vector2i.ZERO,
			Vector2i(7, 5),
			VEHICLE_FOOTPRINT,
			GRID_SIZE,
			always_walkable
		).is_empty(),
		"Bounds must be enforced even when the callback always returns true."
	)
	_expect_true(
		pathfinder.find_path(
			Vector2i.ZERO,
			Vector2i(-1, 0),
			VEHICLE_FOOTPRINT,
			GRID_SIZE,
			always_walkable
		).is_empty(),
		"Negative anchors must be rejected."
	)

	blocked_cells.clear()
	for y in range(GRID_SIZE.y):
		blocked_cells[Vector2i(3, y)] = true
	_expect_true(
		pathfinder.find_path(
			Vector2i.ZERO,
			Vector2i(5, 0),
			VEHICLE_FOOTPRINT,
			GRID_SIZE,
			is_walkable
		).is_empty(),
		"A complete wall should make the target unreachable."
	)

	blocked_cells.clear()
	_expect_equal(
		pathfinder.find_path(
			Vector2i(1, 1),
			Vector2i(1, 1),
			VEHICLE_FOOTPRINT,
			GRID_SIZE,
			is_walkable
		),
		[Vector2i(1, 1)],
		"Start equal to target should return one anchor."
	)
	_expect_true(
		pathfinder.find_path(Vector2i.ZERO, Vector2i.ZERO, Vector2i.ONE, Vector2i.ZERO, always_walkable).is_empty(),
		"Invalid grid sizes must return an empty path."
	)
	_expect_true(
		pathfinder.find_path(Vector2i.ZERO, Vector2i.ZERO, Vector2i(9, 1), GRID_SIZE, always_walkable).is_empty(),
		"A footprint larger than the grid must fail."
	)

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

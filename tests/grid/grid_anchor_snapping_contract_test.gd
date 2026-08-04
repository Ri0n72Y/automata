extends SceneTree

const GRID_MODEL_SCRIPT := preload("res://scripts/grid/grid_model.gd")
const CONTRACT_TEST_SCRIPT := preload("res://tests/support/contract_test.gd")

var test := CONTRACT_TEST_SCRIPT.new()


func _init() -> void:
	_test_default_grid_boundaries()
	_test_offset_and_scaled_grid()
	test.finish(self, "Grid anchor snapping contract tests")


func _test_default_grid_boundaries() -> void:
	var grid = GRID_MODEL_SCRIPT.new()
	test.expect_true(
		grid.configure(12, 8, 1.0, Vector3.ZERO),
		"Default grid configuration should succeed."
	)
	var cases: Array[Dictionary] = [
		{
			"name": "1x1 just before a horizontal center tie",
			"position": Vector3(2.99, 0.0, 3.5),
			"footprint": Vector2i.ONE,
			"expected": Vector2i(2, 3),
		},
		{
			"name": "1x1 just after a horizontal center tie",
			"position": Vector3(3.01, 0.0, 3.5),
			"footprint": Vector2i.ONE,
			"expected": Vector2i(3, 3),
		},
		{
			"name": "1x1 exact tie resolves toward positive cells",
			"position": Vector3(3.0, 0.0, 4.0),
			"footprint": Vector2i.ONE,
			"expected": Vector2i(3, 4),
		},
		{
			"name": "2x2 near a grid-line intersection",
			"position": Vector3(5.02, 0.0, 3.98),
			"footprint": Vector2i(2, 2),
			"expected": Vector2i(4, 3),
		},
		{
			"name": "2x2 chooses the nearest center across a containing-cell boundary",
			"position": Vector3(3.49, 0.0, 4.0),
			"footprint": Vector2i(2, 2),
			"expected": Vector2i(2, 3),
		},
		{
			"name": "2x1 uses independent footprint offsets on each axis",
			"position": Vector3(4.49, 0.0, 2.51),
			"footprint": Vector2i(2, 1),
			"expected": Vector2i(3, 2),
		},
		{
			"name": "outside positions remain outside instead of clamping",
			"position": Vector3(-0.1, 0.0, 0.5),
			"footprint": Vector2i.ONE,
			"expected": Vector2i(-1, 0),
		},
	]
	for case in cases:
		_expect_case(grid, case)

	var invalid_position := Vector3(3.2, 0.0, 4.2)
	test.expect_equal(
		grid.position_to_nearest_anchor(invalid_position, Vector2i.ZERO),
		grid.position_to_cell(invalid_position),
		"A non-positive footprint should fall back to containing-cell conversion."
	)


func _test_offset_and_scaled_grid() -> void:
	var grid = GRID_MODEL_SCRIPT.new()
	test.expect_true(
		grid.configure(6, 5, 2.0, Vector3(10.0, 3.0, -4.0)),
		"Offset grid configuration should succeed."
	)
	var cases: Array[Dictionary] = [
		{
			"name": "2x2 center respects origin and non-unit cell size",
			"position": Vector3(12.05, 3.0, -1.95),
			"footprint": Vector2i(2, 2),
			"expected": Vector2i.ZERO,
		},
		{
			"name": "1x1 tie respects origin and resolves positively",
			"position": Vector3(12.0, 3.0, -2.0),
			"footprint": Vector2i.ONE,
			"expected": Vector2i(1, 1),
		},
	]
	for case in cases:
		_expect_case(grid, case)


func _expect_case(grid, case: Dictionary) -> void:
	var position: Vector3 = case["position"]
	var footprint: Vector2i = case["footprint"]
	var expected: Vector2i = case["expected"]
	var context: String = case["name"]
	var actual: Vector2i = grid.position_to_nearest_anchor(position, footprint)
	test.expect_equal(actual, expected, context)
	_expect_nearest_center_invariant(grid, position, footprint, actual, context)


func _expect_nearest_center_invariant(
	grid,
	position: Vector3,
	footprint: Vector2i,
	actual: Vector2i,
	context: String
) -> void:
	var actual_distance := position.distance_squared_to(
		_footprint_center(grid, actual, footprint)
	)
	for offset_y in range(-1, 2):
		for offset_x in range(-1, 2):
			var candidate := actual + Vector2i(offset_x, offset_y)
			var candidate_distance := position.distance_squared_to(
				_footprint_center(grid, candidate, footprint)
			)
			test.expect_true(
				actual_distance <= candidate_distance + 0.000001,
				"%s should return a nearest footprint center." % context
			)


func _footprint_center(grid, anchor: Vector2i, footprint: Vector2i) -> Vector3:
	return grid.cell_to_position(anchor) + Vector3(
		float(footprint.x - 1) * grid.cell_size * 0.5,
		0.0,
		float(footprint.y - 1) * grid.cell_size * 0.5
	)

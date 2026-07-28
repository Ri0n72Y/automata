extends SceneTree

const GRID_MODEL := preload("res://scripts/grid/grid_model.gd")
const CONTRACT := preload("res://tests/support/contract_test.gd")

var test := CONTRACT.new()


func _init() -> void:
	_test_coordinate_contract()
	_test_bounds_matrix()
	_test_default_cell_contract()
	_test_configuration_lifecycle()
	test.finish(self, "GridModel contract tests")


func _test_coordinate_contract() -> void:
	var cases: Array[Dictionary] = [
		{
			"name": "unit grid at origin",
			"width": 12,
			"height": 8,
			"cell_size": 1.0,
			"origin": Vector3.ZERO,
			"cell": Vector2i(3, 5),
			"center": Vector3(3.5, 0.0, 5.5),
			"sample": Vector3(3.99, 0.0, 5.01),
		},
		{
			"name": "scaled grid with offset origin",
			"width": 4,
			"height": 5,
			"cell_size": 2.0,
			"origin": Vector3(10.0, 3.0, -4.0),
			"cell": Vector2i(1, 1),
			"center": Vector3(13.0, 3.0, -1.0),
			"sample": Vector3(13.9, 3.0, -0.1),
		},
	]
	for case in cases:
		var grid := GRID_MODEL.new()
		test.expect_true(
			grid.configure(case["width"], case["height"], case["cell_size"], case["origin"]),
			"%s should configure." % case["name"]
		)
		var cell: Vector2i = case["cell"]
		test.expect_equal(grid.cell_to_position(cell), case["center"], "%s cell center." % case["name"])
		test.expect_equal(grid.position_to_cell(case["sample"]), cell, "%s containing-cell conversion." % case["name"])
		test.expect_equal(grid.position_to_cell(grid.cell_to_position(cell)), cell, "%s coordinate round trip." % case["name"])


func _test_bounds_matrix() -> void:
	var grid := GRID_MODEL.new()
	test.expect_true(grid.configure(12, 8, 1.0), "Bounds grid should configure.")
	var cases: Array[Dictionary] = [
		{"cell": Vector2i(0, 0), "valid": true, "name": "first cell"},
		{"cell": Vector2i(11, 7), "valid": true, "name": "last cell"},
		{"cell": Vector2i(-1, 0), "valid": false, "name": "negative X"},
		{"cell": Vector2i(0, -1), "valid": false, "name": "negative Y"},
		{"cell": Vector2i(12, 0), "valid": false, "name": "X at width"},
		{"cell": Vector2i(0, 8), "valid": false, "name": "Y at height"},
	]
	for case in cases:
		test.expect_equal(grid.is_cell_valid(case["cell"]), case["valid"], "%s validity." % case["name"])
	test.expect_equal(
		grid.position_to_cell(Vector3(-0.01, 0.0, 0.5)),
		Vector2i(-1, 0),
		"Coordinates before the local origin should remain outside."
	)


func _test_default_cell_contract() -> void:
	var grid := GRID_MODEL.new()
	test.expect_true(grid.configure(12, 8, 1.0), "Cell-type grid should configure.")
	var cases: Array[Dictionary] = [
		{"cell": Vector2i(0, 0), "type": GRID_MODEL.CellType.BOUNDARY, "walkable": false, "name": "lower boundary"},
		{"cell": Vector2i(11, 7), "type": GRID_MODEL.CellType.BOUNDARY, "walkable": false, "name": "upper boundary"},
		{"cell": Vector2i(1, 1), "type": GRID_MODEL.CellType.WHITE_POWER_TILE, "walkable": true, "name": "interior power tile"},
		{"cell": Vector2i(-1, 0), "type": GRID_MODEL.CellType.BOUNDARY, "walkable": false, "name": "out-of-range cell"},
	]
	for case in cases:
		test.expect_equal(grid.get_cell_type(case["cell"]), case["type"], "%s type." % case["name"])
		test.expect_equal(grid.is_cell_walkable(case["cell"]), case["walkable"], "%s walkability." % case["name"])


func _test_configuration_lifecycle() -> void:
	var grid := GRID_MODEL.new()
	test.expect_true(grid.configure(2, 3, 1.0), "Initial configuration should succeed.")
	test.expect_true(grid.configure(4, 5, 2.0, Vector3(1.0, 0.0, -1.0)), "Replacement configuration should succeed.")
	test.expect_equal(Vector3i(grid.width, grid.height, int(grid.cell_size)), Vector3i(4, 5, 2), "Replacement configuration dimensions.")
	test.expect_equal(grid.cell_to_position(Vector2i.ZERO), Vector3(2.0, 0.0, 0.0), "Replacement configuration origin.")
	test.expect_equal(grid.get_cell_type(Vector2i.ZERO), GRID_MODEL.CellType.BOUNDARY, "Replacement configuration rebuilds defaults.")

	var snapshot := {"width": grid.width, "height": grid.height, "cell_size": grid.cell_size, "origin": grid.local_origin}
	var invalid_cases: Array[Array] = [
		[0, 5, 2.0],
		[4, -1, 2.0],
		[4, 5, 0.0],
	]
	for arguments in invalid_cases:
		var accepted := bool(_call_with_expected_errors_suppressed(
			Callable(grid, "configure").bind(arguments[0], arguments[1], arguments[2])
		))
		test.expect_false(accepted, "Invalid configuration %s should be rejected." % str(arguments))
		test.expect_equal(grid.width, snapshot["width"], "Rejected configuration preserves width.")
		test.expect_equal(grid.height, snapshot["height"], "Rejected configuration preserves height.")
		test.expect_equal(grid.cell_size, snapshot["cell_size"], "Rejected configuration preserves cell size.")
		test.expect_equal(grid.local_origin, snapshot["origin"], "Rejected configuration preserves origin.")


func _call_with_expected_errors_suppressed(callback: Callable) -> Variant:
	var previous := Engine.print_error_messages
	Engine.print_error_messages = false
	var result: Variant = callback.call()
	Engine.print_error_messages = previous
	return result

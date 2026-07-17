extends SceneTree

const GridModelScript := preload("res://scripts/grid/grid_model.gd")

var failures: int = 0


func _init() -> void:
	_test_default_grid_conversion()
	_test_grid_bounds()
	_test_default_cell_types_and_walkability()
	_test_offset_origin_and_cell_size()
	_test_repeated_configuration()
	_test_invalid_configuration_is_rejected()

	if failures == 0:
		print("GridModel smoke tests passed.")
		quit(0)
		return

	push_error("GridModel smoke tests failed: %d failure(s)." % failures)
	quit(1)


func _test_default_grid_conversion() -> void:
	var grid = GridModelScript.new()
	_expect_true(
		grid.configure(12, 8, 1.0, Vector3.ZERO),
		"Default grid configuration should succeed."
	)

	_expect_equal(
		grid.cell_to_position(Vector2i(0, 0)),
		Vector3(0.5, 0.0, 0.5),
		"Cell (0, 0) should map to its GridRoot-local center position."
	)
	_expect_equal(
		grid.cell_to_position(Vector2i(3, 5)),
		Vector3(3.5, 0.0, 5.5),
		"Cell (3, 5) should map to its GridRoot-local center position."
	)
	_expect_equal(
		grid.position_to_cell(Vector3(3.99, 0.0, 5.01)),
		Vector2i(3, 5),
		"A non-integer GridRoot-local position should map to its containing cell."
	)
	_expect_equal(
		grid.position_to_cell(grid.cell_to_position(Vector2i(11, 7))),
		Vector2i(11, 7),
		"Cell-to-position and position-to-cell should round trip."
	)


func _test_grid_bounds() -> void:
	var grid = GridModelScript.new()
	_expect_true(
		grid.configure(12, 8, 1.0, Vector3.ZERO),
		"Bounds test grid configuration should succeed."
	)

	_expect_true(grid.is_cell_valid(Vector2i(0, 0)), "The first cell should be valid.")
	_expect_true(grid.is_cell_valid(Vector2i(11, 7)), "The final cell should be valid.")
	_expect_false(grid.is_cell_valid(Vector2i(-1, 0)), "Negative X should be invalid.")
	_expect_false(grid.is_cell_valid(Vector2i(0, -1)), "Negative Y should be invalid.")
	_expect_false(grid.is_cell_valid(Vector2i(12, 0)), "X equal to width should be invalid.")
	_expect_false(grid.is_cell_valid(Vector2i(0, 8)), "Y equal to height should be invalid.")
	_expect_equal(
		grid.position_to_cell(Vector3(-0.01, 0.0, 0.5)),
		Vector2i(-1, 0),
		"Negative GridRoot-local coordinates should remain outside the grid."
	)


func _test_default_cell_types_and_walkability() -> void:
	var grid = GridModelScript.new()
	_expect_true(
		grid.configure(12, 8, 1.0, Vector3.ZERO),
		"Cell-type test grid configuration should succeed."
	)

	var boundary_type: int = GridModelScript.CellType.BOUNDARY
	var power_type: int = GridModelScript.CellType.WHITE_POWER_TILE
	_expect_equal(
		grid.get_cell_type(Vector2i(0, 0)),
		boundary_type,
		"The first cell should be a boundary."
	)
	_expect_equal(
		grid.get_cell_type(Vector2i(11, 7)),
		boundary_type,
		"The final cell should be a boundary."
	)
	_expect_equal(
		grid.get_cell_type(Vector2i(1, 1)),
		power_type,
		"Interior cells should default to white power tiles."
	)
	_expect_equal(
		grid.get_cell_type(Vector2i(-1, 0)),
		boundary_type,
		"Out-of-range cells should behave as boundaries."
	)
	_expect_false(grid.is_cell_walkable(Vector2i(0, 4)), "Boundary cells should not be walkable.")
	_expect_true(grid.is_cell_walkable(Vector2i(1, 1)), "Power tiles should be walkable.")
	_expect_false(grid.is_cell_walkable(Vector2i(12, 2)), "Out-of-range cells should not be walkable.")


func _test_offset_origin_and_cell_size() -> void:
	var grid = GridModelScript.new()
	_expect_true(
		grid.configure(2, 2, 2.0, Vector3(10.0, 3.0, -4.0)),
		"Offset grid configuration should succeed."
	)

	_expect_equal(
		grid.cell_to_position(Vector2i(1, 1)),
		Vector3(13.0, 3.0, -1.0),
		"Cell centers should respect origin and non-unit cell size."
	)
	_expect_equal(
		grid.position_to_cell(Vector3(13.9, 3.0, -0.1)),
		Vector2i(1, 1),
		"Position conversion should respect origin and non-unit cell size."
	)


func _test_repeated_configuration() -> void:
	var grid = GridModelScript.new()
	_expect_true(
		grid.configure(2, 3, 1.0, Vector3.ZERO),
		"Initial grid configuration should succeed."
	)
	_expect_true(
		grid.configure(4, 5, 2.0, Vector3(1.0, 0.0, -1.0)),
		"A valid repeated configuration should succeed."
	)
	_expect_equal(grid.width, 4, "Repeated configuration should replace width.")
	_expect_equal(grid.height, 5, "Repeated configuration should replace height.")
	_expect_equal(grid.cell_size, 2.0, "Repeated configuration should replace cell size.")
	_expect_equal(
		grid.cell_to_position(Vector2i(0, 0)),
		Vector3(2.0, 0.0, 0.0),
		"Repeated configuration should replace the local origin."
	)
	_expect_equal(
		grid.get_cell_type(Vector2i(0, 0)),
		GridModelScript.CellType.BOUNDARY,
		"Repeated configuration should rebuild the default boundary layout."
	)


func _test_invalid_configuration_is_rejected() -> void:
	var grid = GridModelScript.new()
	_expect_true(
		grid.configure(2, 3, 1.0, Vector3.ZERO),
		"Initial valid configuration should succeed."
	)

	_expect_false(grid.configure(0, 3, 1.0), "Zero width should be rejected.")
	_expect_false(grid.configure(2, -1, 1.0), "Negative height should be rejected.")
	_expect_false(grid.configure(2, 3, 0.0), "Zero cell size should be rejected.")
	_expect_equal(grid.width, 2, "Rejected configuration should keep the previous width.")
	_expect_equal(grid.height, 3, "Rejected configuration should keep the previous height.")
	_expect_equal(grid.cell_size, 1.0, "Rejected configuration should keep the previous cell size.")


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

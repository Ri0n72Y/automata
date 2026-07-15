extends SceneTree

const GridModelScript := preload("res://scripts/grid/grid_model.gd")

var failures: int = 0


func _init() -> void:
	_test_default_grid_conversion()
	_test_grid_bounds()
	_test_offset_origin_and_cell_size()
	_test_invalid_configuration_is_rejected()

	if failures == 0:
		print("GridModel smoke tests passed.")
		quit(0)
		return

	push_error("GridModel smoke tests failed: %d failure(s)." % failures)
	quit(1)


func _test_default_grid_conversion() -> void:
	var grid = GridModelScript.new(12, 8, 1.0, Vector3.ZERO)

	_expect_equal(
		grid.cell_to_local(Vector2i(0, 0)),
		Vector3(0.5, 0.0, 0.5),
		"Cell (0, 0) should map to its local-space center."
	)
	_expect_equal(
		grid.cell_to_local(Vector2i(3, 5)),
		Vector3(3.5, 0.0, 5.5),
		"Cell (3, 5) should map to its local-space center."
	)
	_expect_equal(
		grid.local_to_cell(Vector3(3.99, 0.0, 5.01)),
		Vector2i(3, 5),
		"A non-integer local position should map to its containing cell."
	)
	_expect_equal(
		grid.local_to_cell(grid.cell_to_local(Vector2i(11, 7))),
		Vector2i(11, 7),
		"Cell-to-local and local-to-cell should round trip."
	)


func _test_grid_bounds() -> void:
	var grid = GridModelScript.new(12, 8, 1.0, Vector3.ZERO)

	_expect_true(grid.is_cell_valid(Vector2i(0, 0)), "The first cell should be valid.")
	_expect_true(grid.is_cell_valid(Vector2i(11, 7)), "The final cell should be valid.")
	_expect_false(grid.is_cell_valid(Vector2i(-1, 0)), "Negative X should be invalid.")
	_expect_false(grid.is_cell_valid(Vector2i(0, -1)), "Negative Y should be invalid.")
	_expect_false(grid.is_cell_valid(Vector2i(12, 0)), "X equal to width should be invalid.")
	_expect_false(grid.is_cell_valid(Vector2i(0, 8)), "Y equal to height should be invalid.")
	_expect_equal(
		grid.local_to_cell(Vector3(-0.01, 0.0, 0.5)),
		Vector2i(-1, 0),
		"Negative local coordinates should remain outside the grid."
	)


func _test_offset_origin_and_cell_size() -> void:
	var grid = GridModelScript.new(2, 2, 2.0, Vector3(10.0, 3.0, -4.0))

	_expect_equal(
		grid.cell_to_local(Vector2i(1, 1)),
		Vector3(13.0, 3.0, -1.0),
		"Cell centers should respect origin and cell size."
	)
	_expect_equal(
		grid.local_to_cell(Vector3(13.9, 3.0, -0.1)),
		Vector2i(1, 1),
		"Local conversion should respect origin and cell size."
	)


func _test_invalid_configuration_is_rejected() -> void:
	var grid = GridModelScript.new(2, 3, 1.0, Vector3.ZERO)

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

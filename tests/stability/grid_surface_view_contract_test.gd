extends SceneTree

const GRID_MODEL_SCRIPT := preload("res://scripts/grid/grid_model.gd")
const FIELD_SCENE := preload("res://scenes/scene_01/components/scene_01_field_surface.tscn")
const SCENE_CONTROLLER_SCRIPT := preload("res://scripts/scene_01/scene_01_controller.gd")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var view = FIELD_SCENE.instantiate()
	root.add_child(view)

	var model = GRID_MODEL_SCRIPT.new()
	_expect_true(model.configure(16, 10, 1.0), "Grid fixture should configure.")
	_expect_true(view.draw(model), "Configured grid geometry should project to the field surface.")
	_expect_true(view.is_surface_active(), "Configured grid geometry should show the field surface.")
	_expect_surface_geometry(view, Vector2(16, 10), 1.0, Vector2(16, 10))
	_expect_ground_enabled(view, Vector3(16, 0.08, 10))

	_expect_equal(
		model.get_cell_type(Vector2i(0, 0)),
		GRID_MODEL_SCRIPT.CellType.BOUNDARY,
		"Outer grid topology should remain the model-owned boundary."
	)
	_expect_false(model.is_cell_walkable(Vector2i(0, 0)), "Boundary cells should remain non-walkable.")
	_expect_true(model.is_cell_walkable(Vector2i(1, 1)), "Interior cells should remain walkable.")
	_expect_false(model.has_method("_set_cell_type"), "Grid topology mutation API should be removed.")
	var controller = SCENE_CONTROLLER_SCRIPT.new()
	_expect_false(
		controller.has_method("set_grid_cell_type"),
		"Scene controller should not expose runtime topology mutation."
	)
	controller.free()

	var alternate_geometry = GRID_MODEL_SCRIPT.new()
	_expect_true(
		alternate_geometry.configure(15, 9, 0.5, Vector3(2, 0, 3)),
		"Alternate geometry fixture should configure."
	)
	_expect_true(
		view.draw(alternate_geometry),
		"Field surface should resize from model geometry instead of requiring a fixed 16x10 asset."
	)
	_expect_true(view.is_surface_active(), "Alternate valid geometry should keep the surface active.")
	_expect_surface_geometry(view, Vector2(7.5, 4.5), 0.5, Vector2(15, 9))
	_expect_ground_enabled(view, Vector3(7.5, 0.08, 4.5))
	var tiles := view.get_node_or_null("Tiles") as Node3D
	_expect_true(tiles != null, "Field should own a Tiles root.")
	if tiles != null:
		_expect_true(
			tiles.position.is_equal_approx(Vector3(2, 0, 3)),
			"Surface and interaction ground should follow model local origin."
		)

	_expect_false(view.draw(null), "Missing model should fail field projection explicitly.")
	_expect_false(view.is_surface_active(), "Failed projection should hide the surface.")
	_expect_ground_disabled(view)

	view.free()
	_finish()


func _expect_surface_geometry(
	view: Node,
	expected_size: Vector2,
	cell_size: float,
	expected_repeat: Vector2
) -> void:
	var floor := view.get_node_or_null("Tiles/SurfaceVisuals/PlayableFloor") as MeshInstance3D
	var north := view.get_node_or_null(
		"Tiles/SurfaceVisuals/WarningBoundary/NorthBoundaryCells"
	) as MeshInstance3D
	var south := view.get_node_or_null(
		"Tiles/SurfaceVisuals/WarningBoundary/SouthBoundaryCells"
	) as MeshInstance3D
	var west := view.get_node_or_null(
		"Tiles/SurfaceVisuals/WarningBoundary/WestBoundaryCells"
	) as MeshInstance3D
	var east := view.get_node_or_null(
		"Tiles/SurfaceVisuals/WarningBoundary/EastBoundaryCells"
	) as MeshInstance3D
	for node in [floor, north, south, west, east]:
		_expect_true(node != null, "Field surface should own all required visual nodes.")
	if floor == null or north == null or south == null or west == null or east == null:
		return

	var floor_mesh := floor.mesh as PlaneMesh
	var north_mesh := north.mesh as PlaneMesh
	var side_mesh := west.mesh as PlaneMesh
	_expect_true(floor_mesh != null and north_mesh != null and side_mesh != null, "Field visuals should use PlaneMesh resources.")
	if floor_mesh == null or north_mesh == null or side_mesh == null:
		return

	_expect_true(floor_mesh.size.is_equal_approx(expected_size), "Playable floor mesh should match model world size.")
	_expect_true(
		north_mesh.size.is_equal_approx(Vector2(expected_size.x, cell_size)),
		"Horizontal warning edge should be exactly one cell thick."
	)
	var expected_side_height := maxf(expected_size.y - cell_size * 2.0, 0.0)
	if expected_side_height > 0.0:
		_expect_true(
			side_mesh.size.is_equal_approx(Vector2(cell_size, expected_side_height)),
			"Vertical warning edge should cover only non-corner boundary cells."
		)

	_expect_true(
		floor.position.is_equal_approx(Vector3(expected_size.x * 0.5, 0.002, expected_size.y * 0.5)),
		"Playable floor should stay centered on projected grid geometry."
	)
	_expect_true(
		north.position.is_equal_approx(Vector3(expected_size.x * 0.5, 0.01, cell_size * 0.5)),
		"North warning edge should align to the first boundary row."
	)
	_expect_true(
		south.position.is_equal_approx(
			Vector3(expected_size.x * 0.5, 0.01, expected_size.y - cell_size * 0.5)
		),
		"South warning edge should align to the last boundary row."
	)
	_expect_true(
		west.position.is_equal_approx(Vector3(cell_size * 0.5, 0.01, expected_size.y * 0.5)),
		"West warning edge should align to the first boundary column."
	)
	_expect_true(
		east.position.is_equal_approx(
			Vector3(expected_size.x - cell_size * 0.5, 0.01, expected_size.y * 0.5)
		),
		"East warning edge should align to the last boundary column."
	)

	_expect_true(
		Vector2(floor.get_instance_shader_parameter(&"tile_repeat")).is_equal_approx(expected_repeat),
		"Playable texture repeat should derive from logical grid dimensions."
	)
	_expect_true(
		Vector2(north.get_instance_shader_parameter(&"tile_repeat")).is_equal_approx(
			Vector2(expected_repeat.x, 1)
		),
		"Horizontal warning repeat should derive from boundary cell count."
	)
	_expect_true(
		Vector2(west.get_instance_shader_parameter(&"tile_repeat")).is_equal_approx(
			Vector2(1, maxf(expected_repeat.y - 2.0, 1.0))
		),
		"Vertical warning repeat should derive from non-corner boundary cell count."
	)

	_expect_true(
		Vector2(north.get_instance_shader_parameter(&"tile_origin")).is_equal_approx(Vector2.ZERO),
		"North warning edge should start at the field origin for stripe phase."
	)
	_expect_true(
		Vector2(south.get_instance_shader_parameter(&"tile_origin")).is_equal_approx(
			Vector2(0, expected_repeat.y - 1.0)
		),
		"South warning edge should preserve field-space stripe phase."
	)
	_expect_true(
		Vector2(west.get_instance_shader_parameter(&"tile_origin")).is_equal_approx(Vector2(0, 1)),
		"West warning edge should preserve field-space stripe phase."
	)
	_expect_true(
		Vector2(east.get_instance_shader_parameter(&"tile_origin")).is_equal_approx(
			Vector2(expected_repeat.x - 1.0, 1)
		),
		"East warning edge should preserve field-space stripe phase."
	)


func _expect_ground_enabled(view: Node, expected_size: Vector3) -> void:
	var ground_body := view.get_ground_body() as StaticBody3D
	_expect_true(ground_body != null, "Field should own an interaction ground body.")
	if ground_body == null:
		return
	_expect_equal(ground_body.collision_layer, 1, "Interaction ground collision layer should be enabled.")
	var ground_shape := ground_body.get_node_or_null("GroundShape") as CollisionShape3D
	_expect_true(ground_shape != null, "Interaction ground should own GroundShape.")
	if ground_shape == null:
		return
	_expect_false(ground_shape.disabled, "Interaction GroundShape should be enabled.")
	var box_shape := ground_shape.shape as BoxShape3D
	_expect_true(box_shape != null, "Interaction GroundShape should use BoxShape3D.")
	if box_shape != null:
		_expect_true(
			box_shape.size.is_equal_approx(expected_size),
			"Interaction ground should track model geometry."
		)


func _expect_ground_disabled(view: Node) -> void:
	var ground_body := view.get_ground_body() as StaticBody3D
	_expect_true(ground_body != null, "Failed projection should retain the authored GroundBody node.")
	if ground_body == null:
		return
	_expect_equal(ground_body.collision_layer, 0, "Failed projection should disable ground collision.")
	var ground_shape := ground_body.get_node_or_null("GroundShape") as CollisionShape3D
	_expect_true(ground_shape != null, "Failed projection should retain GroundShape.")
	if ground_shape != null:
		_expect_true(ground_shape.disabled, "Failed projection should disable GroundShape.")


func _finish() -> void:
	if failures == 0:
		print("Grid surface view contract tests passed.")
		quit(0)
		return
	push_error("Grid surface view contract tests failed: %d failure(s)." % failures)
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


func _expect_false(value: bool, message: String) -> void:
	if not value:
		return
	failures += 1
	push_error(message)

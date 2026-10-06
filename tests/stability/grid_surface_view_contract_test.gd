extends SceneTree

const GRID_MODEL_SCRIPT := preload("res://scripts/grid/grid_model.gd")
const FIELD_SCENE := preload("res://scenes/scene_01/components/scene_01_field_16x10.tscn")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var view = FIELD_SCENE.instantiate()
	root.add_child(view)

	var model = GRID_MODEL_SCRIPT.new()
	_expect_true(model.configure(16, 10, 1.0), "Grid fixture should configure.")
	view.rebuild(model)

	_expect_true(view.is_surface_active(), "Matching geometry should show the scene-owned surface.")
	_expect_ground_enabled(view, Vector3(16, 0.08, 10))

	_expect_true(
		model._set_cell_type(Vector2i(1, 1), GRID_MODEL_SCRIPT.CellType.NORMAL_TILE),
		"Fixture should be able to change a walkable cell type."
	)
	_expect_true(
		model._set_cell_type(Vector2i(0, 0), GRID_MODEL_SCRIPT.CellType.WHITE_POWER_TILE),
		"Fixture should be able to change a boundary cell type."
	)
	view.rebuild(model)

	_expect_true(
		view.is_surface_active(),
		"Presentation must not duplicate or validate gameplay cell-type topology."
	)
	_expect_ground_enabled(view, Vector3(16, 0.08, 10))

	var alternate_geometry = GRID_MODEL_SCRIPT.new()
	_expect_true(
		alternate_geometry.configure(15, 9, 1.0, Vector3(2, 0, 3)),
		"Alternate geometry fixture should configure."
	)
	view.rebuild(alternate_geometry)

	_expect_false(
		view.is_surface_active(),
		"Fixed surface should hide when its authored geometry no longer matches."
	)
	_expect_ground_enabled(view, Vector3(15, 0.08, 9))
	var tiles := view.get_node_or_null("Tiles") as Node3D
	_expect_true(tiles != null, "Field should own a Tiles root.")
	if tiles != null:
		_expect_true(
			tiles.position.is_equal_approx(Vector3(2, 0, 3)),
			"Interaction ground should continue following model local origin."
		)

	_expect_false(view.has_method("get_tile_count"), "Per-tile count compatibility API should be removed.")
	_expect_false(view.has_method("get_tile_node"), "Per-tile node compatibility API should be removed.")
	_expect_false(view.has_method("is_using_static_scene"), "Legacy static-render mode API should be removed.")
	_expect_false(view.has_method("is_using_dynamic_scene"), "Legacy dynamic-render mode API should be removed.")

	view.free()
	_finish()


func _expect_ground_enabled(view: Node, expected_size: Vector3) -> void:
	var ground_body := view.get_ground_body() as StaticBody3D
	_expect_true(ground_body != null, "Interaction ground must remain available independently of surface presentation.")
	if ground_body == null:
		return
	_expect_equal(ground_body.collision_layer, 1, "Interaction ground collision layer should remain enabled.")
	var ground_shape := ground_body.get_node_or_null("GroundShape") as CollisionShape3D
	_expect_true(ground_shape != null, "Interaction ground should own GroundShape.")
	if ground_shape == null:
		return
	_expect_false(ground_shape.disabled, "Interaction GroundShape should remain enabled.")
	var box_shape := ground_shape.shape as BoxShape3D
	_expect_true(box_shape != null, "Interaction GroundShape should use BoxShape3D.")
	if box_shape != null:
		_expect_true(
			box_shape.size.is_equal_approx(expected_size),
			"Interaction ground should track model geometry independently of the visual surface."
		)


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

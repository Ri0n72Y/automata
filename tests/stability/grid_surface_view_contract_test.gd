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

	_expect_authored_16x10_field(view)
	_expect_ground_enabled(view)

	var model = GRID_MODEL_SCRIPT.new()
	_expect_true(model.configure(16, 10, 1.0), "Grid fixture should configure.")
	_expect_true(view.draw(model), "Authored 16x10 field should validate against GridModel.")
	_expect_true(view.is_surface_active(), "Matching authored field should become runtime-active.")
	_expect_authored_16x10_field(view)
	_expect_ground_enabled(view)

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

	_expect_runtime_compatibility_ownership(model)

	var mismatched_model = GRID_MODEL_SCRIPT.new()
	_expect_true(
		mismatched_model.configure(15, 9, 0.5, Vector3(2, 0, 3)),
		"Mismatched geometry fixture should configure."
	)
	_expect_false(
		view.draw(mismatched_model),
		"Authored Scene 01 field must fail closed instead of resizing to a mismatched GridModel."
	)
	_expect_false(view.is_surface_active(), "Mismatched serialized field should not remain runtime-active.")
	_expect_authored_16x10_field(view)
	_expect_ground_disabled(view)

	_expect_true(
		view.draw(model),
		"Matching GridModel should revalidate the untouched serialized field after a mismatch."
	)
	_expect_true(view.is_surface_active(), "Revalidated authored field should become active again.")
	_expect_authored_16x10_field(view)
	_expect_ground_enabled(view)

	view.free()
	_finish()


func _expect_runtime_compatibility_ownership(model) -> void:
	var presentation_variant = FIELD_SCENE.instantiate()
	root.add_child(presentation_variant)
	var north := presentation_variant.get_node_or_null(
		"Tiles/SurfaceVisuals/WarningBoundary/NorthBoundaryCells"
	) as MeshInstance3D
	var ground_shape := presentation_variant.get_node_or_null(
		"Tiles/GroundBody/GroundShape"
	) as CollisionShape3D
	_expect_true(north != null, "Runtime ownership fixture should include a warning edge.")
	_expect_true(ground_shape != null, "Runtime ownership fixture should include GroundShape.")
	if north != null:
		north.position += Vector3(0.25, 0, 0)
		north.set_instance_shader_parameter(&"tile_origin", Vector2(7, 3))
	if ground_shape != null:
		ground_shape.position += Vector3(0.25, 0, 0)
		var box_shape := ground_shape.shape as BoxShape3D
		if box_shape != null:
			box_shape.size = Vector3(15, 0.08, 10)
	_expect_true(
		presentation_variant.draw(model),
		"Runtime compatibility should not re-own warning phase or exact GroundShape layout."
	)
	presentation_variant.free()

	var same_bounds_different_grid = GRID_MODEL_SCRIPT.new()
	_expect_true(
		same_bounds_different_grid.configure(8, 5, 2.0),
		"Same-bounds logical-grid fixture should configure."
	)
	var logical_contract_view = FIELD_SCENE.instantiate()
	root.add_child(logical_contract_view)
	_expect_false(
		logical_contract_view.draw(same_bounds_different_grid),
		"PlayableFloor logical grid should reject a model with different cell topology even at the same physical bounds."
	)
	logical_contract_view.free()

	var shifted_model = GRID_MODEL_SCRIPT.new()
	_expect_true(
		shifted_model.configure(16, 10, 1.0, Vector3(1, 0, 0)),
		"Shifted-origin fixture should configure."
	)
	var origin_contract_view = FIELD_SCENE.instantiate()
	root.add_child(origin_contract_view)
	_expect_false(
		origin_contract_view.draw(shifted_model),
		"PlayableFloor bounds should reject a GridModel with a different authored origin."
	)
	origin_contract_view.free()


func _expect_authored_16x10_field(view: Node) -> void:
	var tiles := view.get_node_or_null("Tiles") as Node3D
	var visuals := view.get_node_or_null("Tiles/SurfaceVisuals") as Node3D
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
	var ground_body := view.get_node_or_null("Tiles/GroundBody") as StaticBody3D
	var ground_shape := view.get_node_or_null("Tiles/GroundBody/GroundShape") as CollisionShape3D

	for node in [tiles, visuals, floor, north, south, west, east, ground_body, ground_shape]:
		_expect_true(node != null, "Authored field should own all required serialized nodes.")
	if (
		tiles == null
		or visuals == null
		or floor == null
		or north == null
		or south == null
		or west == null
		or east == null
		or ground_body == null
		or ground_shape == null
	):
		return

	_expect_true(visuals.visible, "Serialized field visuals should be visible before runtime validation.")
	_expect_true(tiles.position.is_equal_approx(Vector3.ZERO), "Authored field origin should be serialized.")
	_expect_true(tiles.scale.is_equal_approx(Vector3.ONE), "Authored field scale should remain identity.")

	_expect_plane_size(floor, Vector2(16, 10), "PlayableFloor")
	_expect_plane_size(north, Vector2(16, 1), "North warning")
	_expect_plane_size(south, Vector2(16, 1), "South warning")
	_expect_plane_size(west, Vector2(1, 8), "West warning")
	_expect_plane_size(east, Vector2(1, 8), "East warning")

	_expect_true(
		floor.position.is_equal_approx(Vector3(8, 0.002, 5)),
		"PlayableFloor final position should be serialized."
	)
	_expect_true(
		north.position.is_equal_approx(Vector3(8, 0.01, 0.5)),
		"North warning final position should be serialized."
	)
	_expect_true(
		south.position.is_equal_approx(Vector3(8, 0.01, 9.5)),
		"South warning final position should be serialized."
	)
	_expect_true(
		west.position.is_equal_approx(Vector3(0.5, 0.01, 5)),
		"West warning final position should be serialized."
	)
	_expect_true(
		east.position.is_equal_approx(Vector3(15.5, 0.01, 5)),
		"East warning final position should be serialized."
	)

	_expect_shader_vector2(floor, &"tile_repeat", Vector2(16, 10), "PlayableFloor repeat")
	_expect_shader_vector2(north, &"tile_repeat", Vector2(16, 1), "North warning repeat")
	_expect_shader_vector2(south, &"tile_repeat", Vector2(16, 1), "South warning repeat")
	_expect_shader_vector2(west, &"tile_repeat", Vector2(1, 8), "West warning repeat")
	_expect_shader_vector2(east, &"tile_repeat", Vector2(1, 8), "East warning repeat")

	_expect_shader_vector2(north, &"tile_origin", Vector2(0, 0), "North warning phase")
	_expect_shader_vector2(south, &"tile_origin", Vector2(0, 9), "South warning phase")
	_expect_shader_vector2(west, &"tile_origin", Vector2(0, 1), "West warning phase")
	_expect_shader_vector2(east, &"tile_origin", Vector2(15, 1), "East warning phase")

	_expect_equal(ground_body.collision_mask, 0, "Authored GroundBody collision mask should stay zero.")
	_expect_true(
		ground_shape.position.is_equal_approx(Vector3(8, -0.04, 5)),
		"GroundShape final position should be serialized."
	)
	var box_shape := ground_shape.shape as BoxShape3D
	_expect_true(box_shape != null, "Authored GroundShape should use BoxShape3D.")
	if box_shape != null:
		_expect_true(
			box_shape.size.is_equal_approx(Vector3(16, 0.08, 10)),
			"GroundShape final 16x10 geometry should be serialized."
		)


func _expect_plane_size(node: MeshInstance3D, expected: Vector2, label: String) -> void:
	var plane := node.mesh as PlaneMesh
	_expect_true(plane != null, "%s should use PlaneMesh." % label)
	if plane != null:
		_expect_true(plane.size.is_equal_approx(expected), "%s final size should be serialized." % label)


func _expect_shader_vector2(
	node: MeshInstance3D,
	parameter: StringName,
	expected: Vector2,
	label: String
) -> void:
	var actual := Vector2(node.get_instance_shader_parameter(parameter))
	_expect_true(actual.is_equal_approx(expected), "%s should be serialized." % label)


func _expect_ground_enabled(view: Node) -> void:
	var ground_body := view.get_ground_body() as StaticBody3D
	_expect_true(ground_body != null, "Field should own an authored interaction GroundBody.")
	if ground_body == null:
		return
	_expect_equal(ground_body.collision_layer, 1, "Authored GroundBody collision layer should be enabled.")
	_expect_equal(ground_body.collision_mask, 0, "Authored GroundBody collision mask should stay zero.")

	var ground_shape := ground_body.get_node_or_null("GroundShape") as CollisionShape3D
	_expect_true(ground_shape != null, "Field should own an authored GroundShape.")
	if ground_shape != null:
		_expect_false(ground_shape.disabled, "Authored GroundShape should be enabled.")


func _expect_ground_disabled(view: Node) -> void:
	var ground_body := view.get_ground_body() as StaticBody3D
	_expect_true(ground_body != null, "Fail-closed field should retain its authored GroundBody.")
	if ground_body == null:
		return
	_expect_equal(ground_body.collision_layer, 0, "Mismatch should disable ground interaction.")
	var ground_shape := ground_body.get_node_or_null("GroundShape") as CollisionShape3D
	_expect_true(ground_shape != null, "Fail-closed field should retain its authored GroundShape.")
	if ground_shape != null:
		_expect_true(ground_shape.disabled, "Mismatch should disable GroundShape without resizing it.")


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

extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const GRID_MODEL_SCRIPT := preload("res://scripts/grid/grid_model.gd")
const GRID_TILE_VIEW_SCRIPT := preload("res://scripts/grid/grid_tile_view.gd")
const CAMERA_RIG_SCRIPT := preload("res://scripts/camera/scene_01_camera_rig.gd")
const GRID_SELECTION_SCRIPT := preload("res://scripts/input/grid_selection_controller.gd")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	_expect_true(packed_scene != null, "Scene 01 should load for field interaction tests.")
	if packed_scene == null:
		_finish()
		return

	var scene := packed_scene.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame

	var grid_root := scene.get_node_or_null("SceneRoot/GridRoot") as Node3D
	var tile_view := scene.get_node_or_null(
		"SceneRoot/GridRoot/GridTileView"
	) as GRID_TILE_VIEW_SCRIPT
	var selection := scene.get_node_or_null(
		"SceneRoot/GridRoot/GridSelectionController"
	) as GRID_SELECTION_SCRIPT
	var camera_rig := scene.get_node_or_null(
		"SceneRoot/CameraRoot/Scene01CameraRig"
	) as CAMERA_RIG_SCRIPT
	var grid_model := scene.get("grid_model") as GRID_MODEL_SCRIPT

	_expect_true(grid_root != null, "Scene 01 should contain GridRoot.")
	_expect_true(tile_view != null, "Scene 01 should contain GridTileView.")
	_expect_true(selection != null, "Scene 01 should contain GridSelectionController.")
	_expect_true(camera_rig != null, "Scene 01 should contain Scene01CameraRig.")
	_expect_true(grid_model != null, "Scene 01 should initialize GridModel.")

	if tile_view != null and grid_model != null:
		_test_tile_view(tile_view, grid_model)
		await _test_cell_type_visual_sync(scene, tile_view, grid_model)

	var camera: Camera3D
	if camera_rig != null and grid_root != null and grid_model != null:
		camera = camera_rig.get_camera()
		await _test_camera(grid_root, grid_model, camera_rig, camera)

	if selection != null and grid_root != null and grid_model != null:
		_test_selection(scene, grid_root, selection, camera)

	scene.queue_free()
	await process_frame
	_finish()


func _test_tile_view(tile_view: GRID_TILE_VIEW_SCRIPT, grid_model: GRID_MODEL_SCRIPT) -> void:
	_expect_equal(
		tile_view.get_tile_count(),
		grid_model.width * grid_model.height,
		"Tile view should render one tile for every grid cell."
	)
	_expect_true(tile_view.get_ground_body() != null, "Tile view should expose one ground body.")

	var ground_body := tile_view.get_ground_body()
	if ground_body != null:
		_expect_equal(
			ground_body.get_child_count(),
			1,
			"Ground body should use one collision shape for the whole grid."
		)
		var ground_shape := ground_body.get_node_or_null("GroundShape") as CollisionShape3D
		_expect_true(ground_shape != null, "Ground body should contain GroundShape.")
		if ground_shape != null:
			var box_shape := ground_shape.shape as BoxShape3D
			_expect_true(box_shape != null, "GroundShape should use BoxShape3D.")
			if box_shape != null:
				_expect_float_approx(
					box_shape.size.x,
					float(grid_model.width) * grid_model.cell_size,
					"Ground collision width should match the grid."
				)
				_expect_float_approx(
					box_shape.size.z,
					float(grid_model.height) * grid_model.cell_size,
					"Ground collision height should match the grid."
				)

	var boundary_tile := tile_view.get_tile_node(Vector2i(0, 0))
	var power_tile := tile_view.get_tile_node(Vector2i(1, 1))
	_expect_true(boundary_tile != null, "Boundary tile mesh should exist.")
	_expect_true(power_tile != null, "Power tile mesh should exist.")
	if boundary_tile != null and power_tile != null:
		var boundary_material := boundary_tile.material_override as StandardMaterial3D
		var power_material := power_tile.material_override as StandardMaterial3D
		_expect_true(boundary_material != null, "Boundary tile should have a material.")
		_expect_true(power_material != null, "Power tile should have a material.")
		if boundary_material != null and power_material != null:
			_expect_true(
				boundary_material.albedo_color != power_material.albedo_color,
				"Boundary and power tiles should be visually distinct."
			)


func _test_cell_type_visual_sync(
	scene: Node,
	tile_view: GRID_TILE_VIEW_SCRIPT,
	grid_model: GRID_MODEL_SCRIPT
) -> void:
	var cell := Vector2i(2, 2)
	var original_tile := tile_view.get_tile_node(cell)
	var original_color := Color.TRANSPARENT
	if original_tile != null:
		var original_material := original_tile.material_override as StandardMaterial3D
		if original_material != null:
			original_color = original_material.albedo_color

	_expect_true(
		bool(scene.call("set_grid_cell_type", cell, GRID_MODEL_SCRIPT.CellType.BOUNDARY)),
		"Controller should accept valid cell type updates."
	)
	await process_frame
	_expect_equal(
		grid_model.get_cell_type(cell),
		GRID_MODEL_SCRIPT.CellType.BOUNDARY,
		"Controller updates should change the grid model."
	)
	_expect_false(grid_model.is_cell_walkable(cell), "Updated boundary cells should be blocked.")
	_expect_equal(
		tile_view.get_child_count(),
		1,
		"Tile view rebuild should release the previous tile batch."
	)
	var updated_tile := tile_view.get_tile_node(cell)
	_expect_true(updated_tile != null, "Updated cell should still have a tile mesh.")
	if updated_tile != null:
		var updated_material := updated_tile.material_override as StandardMaterial3D
		_expect_true(updated_material != null, "Updated tile should have a material.")
		if updated_material != null:
			_expect_true(
				updated_material.albedo_color != original_color,
				"Cell type updates should refresh the tile material."
			)

	_expect_true(
		bool(scene.call("set_grid_cell_type", cell, GRID_MODEL_SCRIPT.CellType.WHITE_POWER_TILE)),
		"Controller should restore a power tile."
	)
	await process_frame
	_expect_true(grid_model.is_cell_walkable(cell), "Restored power tiles should be walkable.")


func _test_camera(
	grid_root: Node3D,
	grid_model: GRID_MODEL_SCRIPT,
	camera_rig: CAMERA_RIG_SCRIPT,
	camera: Camera3D
) -> void:
	_expect_true(camera != null, "Camera rig should expose SceneCamera.")
	if camera == null:
		return
	_expect_equal(
		camera.projection,
		Camera3D.PROJECTION_ORTHOGONAL,
		"Scene camera should use orthographic projection."
	)
	_expect_true(camera.current, "Scene camera should be current.")
	_assert_grid_corners_visible(grid_root, grid_model, camera, "Default viewport")

	var original_window_size := root.size
	root.size = Vector2i(480, 900)
	await process_frame
	_configure_camera_for_grid(grid_root, grid_model, camera_rig)
	await process_frame
	_assert_grid_corners_visible(grid_root, grid_model, camera, "Narrow viewport")

	root.size = original_window_size
	await process_frame
	_configure_camera_for_grid(grid_root, grid_model, camera_rig)
	await process_frame


func _configure_camera_for_grid(
	grid_root: Node3D,
	grid_model: GRID_MODEL_SCRIPT,
	camera_rig: CAMERA_RIG_SCRIPT
) -> void:
	var local_center := grid_model.local_origin + Vector3(
		float(grid_model.width) * grid_model.cell_size * 0.5,
		0.0,
		float(grid_model.height) * grid_model.cell_size * 0.5
	)
	var world_center := grid_root.to_global(local_center)
	var world_scale := grid_root.global_basis.get_scale().abs()
	camera_rig.configure_for_grid(
		world_center,
		float(grid_model.width) * grid_model.cell_size * world_scale.x,
		float(grid_model.height) * grid_model.cell_size * world_scale.z
	)


func _assert_grid_corners_visible(
	grid_root: Node3D,
	grid_model: GRID_MODEL_SCRIPT,
	camera: Camera3D,
	context: String
) -> void:
	var viewport_size := camera.get_viewport().get_visible_rect().size
	var local_min := grid_model.local_origin
	var local_max := grid_model.local_origin + Vector3(
		float(grid_model.width) * grid_model.cell_size,
		0.0,
		float(grid_model.height) * grid_model.cell_size
	)
	var corners := [
		grid_root.to_global(Vector3(local_min.x, local_min.y, local_min.z)),
		grid_root.to_global(Vector3(local_max.x, local_min.y, local_min.z)),
		grid_root.to_global(Vector3(local_min.x, local_min.y, local_max.z)),
		grid_root.to_global(Vector3(local_max.x, local_min.y, local_max.z)),
	]
	for corner in corners:
		var screen_position := camera.unproject_position(corner)
		_expect_true(
			screen_position.x >= 0.0
			and screen_position.y >= 0.0
			and screen_position.x <= viewport_size.x
			and screen_position.y <= viewport_size.y,
			"%s should keep grid corner %s inside viewport %s; projected to %s."
			% [context, str(corner), str(viewport_size), str(screen_position)]
		)


func _test_selection(
	scene: Node,
	grid_root: Node3D,
	selection: GRID_SELECTION_SCRIPT,
	camera: Camera3D
) -> void:
	var interior_cell := Vector2i(2, 2)
	var interior_world: Vector3 = scene.call("grid_cell_to_world", interior_cell)

	_expect_true(
		selection.update_hover_from_world_position(interior_world),
		"World positions over the field should update hover."
	)
	_expect_equal(selection.hovered_cell, interior_cell, "Hover cell should match grid data.")
	_expect_true(selection.has_hovered_cell(), "Selection controller should report active hover.")

	_expect_true(
		selection.select_from_world_position(interior_world),
		"World positions over the field should update selection."
	)
	_expect_equal(selection.selected_cell, interior_cell, "Selected cell should match grid data.")
	_expect_true(selection.is_selected_cell_walkable(), "Interior power tiles should be selectable targets.")
	_expect_true(selection.confirm_selection(), "Walkable selected cells should be confirmable.")

	var boundary_cell := Vector2i(0, 2)
	var boundary_world: Vector3 = scene.call("grid_cell_to_world", boundary_cell)
	_expect_true(
		selection.select_from_world_position(boundary_world),
		"Boundary cells should still expose selection feedback."
	)
	_expect_equal(selection.selected_cell, boundary_cell, "Boundary selection should keep its grid cell.")
	_expect_false(selection.is_selected_cell_walkable(), "Boundary cells should not be walkable.")
	_expect_false(selection.confirm_selection(), "Boundary cells should not be confirmable targets.")

	selection.cancel_selection()
	_expect_false(selection.has_selected_cell(), "Cancel should clear the selected cell.")

	var outside_world := grid_root.to_global(Vector3(-0.1, 0.0, 0.5))
	_expect_false(
		selection.update_hover_from_world_position(outside_world),
		"Positions outside the field should clear hover."
	)
	_expect_false(selection.has_hovered_cell(), "Outside hover should leave no active cell.")
	_expect_false(
		selection.select_from_world_position(outside_world),
		"Positions outside the field should not create selection."
	)
	_expect_false(selection.has_selected_cell(), "Outside selection should leave no active target.")

	if camera != null:
		var screen_position := camera.unproject_position(interior_world)
		_expect_true(
			selection.update_hover_from_screen_position(screen_position),
			"Camera raycasts should resolve the grid cell under the mouse."
		)
		_expect_equal(
			selection.hovered_cell,
			interior_cell,
			"Raycast hover should match world-to-grid conversion."
		)

	grid_root.position = Vector3(7.0, 0.0, -3.0)
	grid_root.rotation.y = PI / 2.0
	grid_root.scale = Vector3(1.5, 1.0, 2.0)
	var transformed_cell := Vector2i(3, 3)
	var transformed_world: Vector3 = scene.call("grid_cell_to_world", transformed_cell)
	_expect_true(
		selection.select_from_world_position(transformed_world),
		"Selection should remain valid after GridRoot transforms."
	)
	_expect_equal(
		selection.selected_cell,
		transformed_cell,
		"Transformed GridRoot selection should preserve grid coordinates."
	)


func _finish() -> void:
	if failures == 0:
		print("Scene 01 field interaction smoke tests passed.")
		quit(0)
		return
	push_error("Scene 01 field interaction smoke tests failed: %d failure(s)." % failures)
	quit(1)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	failures += 1
	push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])


func _expect_float_approx(actual: float, expected: float, message: String) -> void:
	if is_equal_approx(actual, expected):
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

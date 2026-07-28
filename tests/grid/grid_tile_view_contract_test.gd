extends SceneTree

const MAIN_SCENE := preload("res://scenes/scene_01/scene_01_basic_packing.tscn")
const FIELD_SCENE := preload("res://scenes/scene_01/components/scene_01_field_12x8.tscn")
const GRID_MODEL := preload("res://scripts/grid/grid_model.gd")
const GRID_TILE_VIEW := preload("res://scripts/grid/grid_tile_view.gd")
const CONTRACT := preload("res://tests/support/contract_test.gd")

var test := CONTRACT.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_static_resource_shape()
	_test_static_dynamic_mode_boundaries()
	await _test_scene_cell_type_sync()
	test.finish(self, "Grid tile view contract tests")


func _test_static_resource_shape() -> void:
	var field := FIELD_SCENE.instantiate()
	var tile_count := 0
	for y in range(8):
		for x in range(12):
			if field.get_node_or_null("Tiles/Row_%d/Tile_%d" % [y, x]) != null:
				tile_count += 1
	test.expect_equal(tile_count, 96, "Static field resource should expose all editor-visible tiles.")
	test.expect_true(field.get_node_or_null("Tiles/GroundBody/GroundShape") != null, "Static field should include ground collision.")
	field.free()


func _test_static_dynamic_mode_boundaries() -> void:
	var field := FIELD_SCENE.instantiate()
	var cases: Array[Dictionary] = [
		{"size": Vector2i(12, 8), "mode": "static", "tiles": 96, "probe": Vector2i(11, 7)},
		{"size": Vector2i(13, 8), "mode": "dynamic", "tiles": 104, "probe": Vector2i(12, 7)},
		{"size": Vector2i(12, 8), "mode": "static", "tiles": 96, "probe": Vector2i(11, 7)},
	]
	var static_tiles := field.get_node_or_null("Tiles") as Node3D
	var static_ground := field.get_node_or_null("Tiles/GroundBody") as StaticBody3D
	for case in cases:
		var model := GRID_MODEL.new()
		test.expect_true(model.configure(case["size"].x, case["size"].y, 1.0), "%s model should configure." % case["mode"])
		field.call("draw", model)
		var static_mode: bool = case["mode"] == "static"
		test.expect_equal(bool(field.call("is_using_static_scene")), static_mode, "%s mode flag." % case["mode"])
		test.expect_equal(bool(field.call("is_using_dynamic_scene")), not static_mode, "%s inverse mode flag." % case["mode"])
		test.expect_equal(int(field.call("get_tile_count")), case["tiles"], "%s tile count." % case["mode"])
		test.expect_true(field.call("get_tile_node", case["probe"]) != null, "%s probe cell should resolve." % case["mode"])
		var active_ground := field.call("get_ground_body") as StaticBody3D
		test.expect_true(active_ground != null, "%s mode should expose active ground." % case["mode"])
		if static_mode:
			test.expect_true(static_tiles != null and static_tiles.visible, "Static tiles should be visible.")
			test.expect_true(active_ground == static_ground, "Static mode should expose static ground.")
			test.expect_equal(static_ground.collision_layer, 1, "Static ground should own collision layer 1.")
		else:
			test.expect_true(static_tiles != null and not static_tiles.visible, "Dynamic mode should hide static tiles.")
			test.expect_equal(static_ground.collision_layer, 0, "Dynamic mode should disable static ground collision.")
			test.expect_true(active_ground != static_ground, "Dynamic mode should expose a separate ground body.")
			test.expect_equal(active_ground.collision_layer, 1, "Dynamic ground should own collision layer 1.")
	field.free()


func _test_scene_cell_type_sync() -> void:
	var scene := MAIN_SCENE.instantiate()
	root.add_child(scene)
	await process_frame
	var tile_view := scene.get_node_or_null("SceneRoot/GridRoot/GridTileView") as GRID_TILE_VIEW
	var model := scene.get("grid_model") as GRID_MODEL
	test.expect_true(tile_view != null and model != null, "Scene tile-view dependencies should exist.")
	if tile_view == null or model == null:
		scene.queue_free()
		await process_frame
		return

	test.expect_equal(tile_view.get_tile_count(), model.width * model.height, "Tile view should render one tile per cell.")
	var ground := tile_view.get_ground_body()
	test.expect_true(ground != null, "Tile view should expose one active ground body.")
	if ground != null:
		var shape_node := ground.get_node_or_null("GroundShape") as CollisionShape3D
		test.expect_true(shape_node != null and shape_node.shape is BoxShape3D, "Ground should use one BoxShape3D.")
		if shape_node != null and shape_node.shape is BoxShape3D:
			var box := shape_node.shape as BoxShape3D
			test.expect_float_approx(box.size.x, float(model.width) * model.cell_size, "Ground collision width.")
			test.expect_float_approx(box.size.z, float(model.height) * model.cell_size, "Ground collision height.")

	var boundary := tile_view.get_tile_node(Vector2i(0, 0))
	var power := tile_view.get_tile_node(Vector2i(1, 1))
	_expect_material_difference(boundary, power, "Boundary and power tiles should differ.")

	var cell := Vector2i(2, 2)
	var original := tile_view.get_tile_node(cell) as MeshInstance3D
	var original_color := _material_color(original)
	test.expect_true(bool(scene.call("set_grid_cell_type", cell, GRID_MODEL.CellType.BOUNDARY)), "Valid type mutation should succeed.")
	await process_frame
	test.expect_equal(model.get_cell_type(cell), GRID_MODEL.CellType.BOUNDARY, "Mutation should update the model.")
	test.expect_false(model.is_cell_walkable(cell), "Boundary mutation should block the cell.")
	test.expect_equal(tile_view.get_child_count(), 1, "Redraw should retain one active tile batch.")
	test.expect_true(_material_color(tile_view.get_tile_node(cell)) != original_color, "Mutation should refresh the tile material.")
	test.expect_true(bool(scene.call("set_grid_cell_type", cell, GRID_MODEL.CellType.WHITE_POWER_TILE)), "Power-tile restore should succeed.")
	await process_frame
	test.expect_true(model.is_cell_walkable(cell), "Restored power tile should be walkable.")

	scene.queue_free()
	await process_frame


func _material_color(mesh_node) -> Color:
	if not (mesh_node is MeshInstance3D):
		return Color.TRANSPARENT
	var material := mesh_node.material_override as StandardMaterial3D
	return material.albedo_color if material != null else Color.TRANSPARENT


func _expect_material_difference(first, second, message: String) -> void:
	test.expect_true(first is MeshInstance3D and second is MeshInstance3D, message + " Meshes should exist.")
	if first is MeshInstance3D and second is MeshInstance3D:
		test.expect_true(_material_color(first) != _material_color(second), message)

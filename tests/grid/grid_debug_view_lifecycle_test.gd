extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const GRID_MODEL := preload("res://scripts/grid/grid_model.gd")
const GRID_DEBUG_VIEW := preload("res://scripts/grid/grid_debug_view.gd")
const CONTRACT := preload("res://tests/support/contract_test.gd")

var test := CONTRACT.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene_resource := load(SCENE_PATH) as PackedScene
	test.expect_true(scene_resource != null, "Scene 01 should load for debug-view tests.")
	if scene_resource == null:
		test.finish(self, "Grid debug view lifecycle tests")
		return
	var scene := scene_resource.instantiate()
	root.add_child(scene)
	await process_frame
	var debug_view := scene.get_node_or_null("SceneRoot/GridRoot/GridDebugView") as GRID_DEBUG_VIEW
	var grid_model := scene.get("grid_model") as GRID_MODEL
	test.expect_true(debug_view != null and grid_model != null, "Debug-view dependencies should exist.")
	if debug_view != null and grid_model != null:
		await _test_draw_lifecycle(debug_view, grid_model)
	scene.queue_free()
	await process_frame
	test.finish(self, "Grid debug view lifecycle tests")


func _test_draw_lifecycle(debug_view, grid_model) -> void:
	_expect_active_batch(debug_view, 96, "initial draw")

	debug_view.show_coordinates = false
	debug_view.draw(grid_model)
	await process_frame
	test.expect_equal(debug_view.get_child_count(), 0, "Disabled view should release its label container.")
	test.expect_equal(debug_view.get_debug_label_count(), 0, "Disabled view should expose no labels.")

	debug_view.show_coordinates = true
	for pass_index in range(2):
		debug_view.draw(grid_model)
		await process_frame
		_expect_active_batch(debug_view, 96, "enabled draw %d" % pass_index)
	if debug_view.get_child_count() == 1:
		test.expect_true(
			debug_view.get_child(0).get_node_or_null("Cell_0_0") != null,
			"Replacement batches should preserve readable cell label names."
		)

	var large_grid := GRID_MODEL.new()
	test.expect_true(large_grid.configure(1000, 1000, 1.0), "Large grid should configure.")
	debug_view.draw(large_grid)
	await process_frame
	test.expect_equal(debug_view.get_child_count(), 1, "Large-grid draw should retain one active batch.")
	test.expect_true(
		debug_view.get_debug_label_count() <= maxi(debug_view.max_debug_labels, 1),
		"Large-grid sampling should remain within the label budget."
	)


func _expect_active_batch(debug_view, expected_labels: int, context: String) -> void:
	test.expect_equal(debug_view.get_child_count(), 1, "%s should have one active container." % context)
	test.expect_equal(debug_view.get_debug_label_count(), expected_labels, "%s label count." % context)

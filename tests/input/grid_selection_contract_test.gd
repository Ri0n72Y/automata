extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const GRID_SELECTION := preload("res://scripts/input/grid_selection_controller.gd")
const CONTRACT := preload("res://tests/support/contract_test.gd")

var test := CONTRACT.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var resource := load(SCENE_PATH) as PackedScene
	test.expect_true(resource != null, "Scene 01 should load for grid selection tests.")
	if resource == null:
		test.finish(self, "Grid selection contract tests")
		return
	var scene := resource.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	var grid_root := scene.get_node_or_null("SceneRoot/GridRoot") as Node3D
	var selection := scene.get_node_or_null("SceneRoot/GridRoot/GridSelectionController") as GRID_SELECTION
	test.expect_true(grid_root != null and selection != null, "Selection dependencies should exist.")
	if grid_root != null and selection != null:
		_test_world_position_matrix(scene, grid_root, selection)
		_test_cancel_and_signal_contract(scene, selection)
		_test_transformed_grid(scene, grid_root, selection)
	scene.queue_free()
	await process_frame
	test.finish(self, "Grid selection contract tests")


func _test_world_position_matrix(scene: Node, grid_root: Node3D, selection) -> void:
	var cases: Array[Dictionary] = [
		{"name": "walkable interior", "cell": Vector2i(2, 2), "hover": true, "select": true, "walkable": true, "confirm": true},
		{"name": "boundary feedback", "cell": Vector2i(0, 2), "hover": true, "select": true, "walkable": false, "confirm": false},
	]
	for case in cases:
		var world_position: Vector3 = scene.call("grid_cell_to_world", case["cell"])
		test.expect_equal(selection.update_hover_from_world_position(world_position), case["hover"], "%s hover result." % case["name"])
		test.expect_equal(selection.hovered_cell, case["cell"], "%s hovered cell." % case["name"])
		test.expect_equal(selection.select_from_world_position(world_position), case["select"], "%s selection result." % case["name"])
		test.expect_equal(selection.selected_cell, case["cell"], "%s selected cell." % case["name"])
		test.expect_equal(selection.is_selected_cell_walkable(), case["walkable"], "%s walkability." % case["name"])
		test.expect_equal(selection.confirm_selection(), case["confirm"], "%s confirmation." % case["name"])

	var outside_positions := [
		grid_root.to_global(Vector3(-0.1, 0.0, 0.5)),
		grid_root.to_global(Vector3(12.1, 0.0, 0.5)),
		grid_root.to_global(Vector3(0.5, 0.0, 8.1)),
	]
	for position in outside_positions:
		test.expect_false(selection.update_hover_from_world_position(position), "Outside positions should reject hover.")
		test.expect_false(selection.has_hovered_cell(), "Outside hover should clear active hover.")
		test.expect_false(selection.select_from_world_position(position), "Outside positions should reject selection.")
		test.expect_false(selection.has_selected_cell(), "Outside selection should clear active target.")


func _test_cancel_and_signal_contract(scene: Node, selection) -> void:
	var selection_events: Array[Dictionary] = []
	var confirmation_events: Array[Vector2i] = []
	selection.selection_changed.connect(
		func(cell: Vector2i, active: bool) -> void:
			selection_events.append({"cell": cell, "active": active})
	)
	selection.selection_confirmed.connect(func(cell: Vector2i) -> void: confirmation_events.append(cell))
	var cell := Vector2i(3, 3)
	var world_position: Vector3 = scene.call("grid_cell_to_world", cell)
	test.expect_true(selection.select_from_world_position(world_position), "Signal test selection should succeed.")
	test.expect_true(selection.confirm_selection(), "Signal test confirmation should succeed.")
	test.expect_equal(confirmation_events, [cell], "Confirmation should emit the selected cell once.")
	selection.cancel_selection()
	test.expect_false(selection.has_selected_cell(), "Cancel should clear selection.")
	test.expect_true(selection_events.size() >= 2, "Select and cancel should emit lifecycle events.")
	if selection_events.size() >= 2:
		test.expect_equal(selection_events[-1], {"cell": GRID_SELECTION.INVALID_CELL, "active": false}, "Cancel event payload.")


func _test_transformed_grid(scene: Node, grid_root: Node3D, selection) -> void:
	grid_root.transform = Transform3D(
		Basis(Vector3.UP, PI * 0.5).scaled(Vector3(1.5, 1.0, 2.0)),
		Vector3(7.0, 0.0, -3.0)
	)
	var cell := Vector2i(3, 3)
	var world_position: Vector3 = scene.call("grid_cell_to_world", cell)
	test.expect_true(selection.select_from_world_position(world_position), "Transformed-grid selection should succeed.")
	test.expect_equal(selection.selected_cell, cell, "Transformed-grid selection should preserve logical coordinates.")

extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const READY_PROBE_SCRIPT := preload("res://tests/scene_01/grid_ready_probe.gd")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	_expect_true(packed_scene != null, "Scene 01 should load as a PackedScene.")
	if packed_scene == null:
		_finish()
		return

	var scene := packed_scene.instantiate()
	var pre_ready_grid_root := scene.get_node_or_null("SceneRoot/GridRoot") as Node3D
	var ready_probe := READY_PROBE_SCRIPT.new()
	ready_probe.controller = scene
	_expect_true(
		pre_ready_grid_root != null,
		"Scene 01 should expose GridRoot before entering the SceneTree."
	)
	if pre_ready_grid_root != null:
		pre_ready_grid_root.add_child(ready_probe)

	root.add_child(scene)
	# SceneTree.process_frame is the Godot 4.x signal used to wait for _ready().
	await process_frame

	var grid_root := scene.get_node_or_null("SceneRoot/GridRoot") as Node3D
	var debug_view := scene.get_node_or_null(
		"SceneRoot/GridRoot/GridDebugView"
	) as GridDebugView
	var grid_model := scene.get("grid_model") as GridModel

	_expect_true(grid_root != null, "Scene 01 should contain GridRoot.")
	_expect_true(debug_view != null, "Scene 01 should contain GridDebugView.")
	_expect_true(grid_model != null, "Scene 01 should initialize GridModel.")
	_expect_true(
		ready_probe.grid_model_was_ready,
		"GridModel should be initialized before child nodes enter _ready()."
	)
	_expect_true(
		ready_probe.conversion_succeeded,
		"Child nodes should be able to use grid coordinate APIs during _ready()."
	)

	if debug_view != null:
		_expect_equal(
			debug_view.get_child_count(),
			1,
			"The debug view should contain one active label container."
		)
		_expect_equal(
			debug_view.get_debug_label_count(),
			96,
			"Default 12 x 8 grid should create 96 debug labels."
		)

	if grid_root != null and grid_model != null:
		grid_root.position = Vector3(10.0, 0.0, -4.0)
		grid_root.rotation.y = PI / 2.0
		grid_root.scale = Vector3(2.0, 1.0, 3.0)
		var world_center: Vector3 = scene.call(
			"grid_cell_to_world",
			Vector2i(0, 0)
		)
		_expect_vector3_approx(
			world_center,
			grid_root.to_global(Vector3(0.5, 0.0, 0.5)),
			"GridRoot translation, rotation, and scale should be applied by the controller."
		)
		_expect_equal(
			scene.call("world_to_grid_cell", world_center),
			Vector2i(0, 0),
			"World and grid conversion should round trip through a transformed GridRoot."
		)

	if debug_view != null and grid_model != null:
		debug_view.show_coordinates = false
		debug_view.draw(grid_model)
		await process_frame
		_expect_equal(
			debug_view.get_child_count(),
			0,
			"A disabled debug view should release its label container."
		)
		_expect_equal(
			debug_view.get_debug_label_count(),
			0,
			"A disabled debug view should not expose coordinate labels."
		)

		debug_view.show_coordinates = true
		debug_view.draw(grid_model)
		await process_frame
		_expect_equal(
			debug_view.get_child_count(),
			1,
			"An enabled debug view should create one active label container."
		)
		_expect_equal(
			debug_view.get_debug_label_count(),
			96,
			"Re-enabled drawing should restore the coordinate labels."
		)

		debug_view.draw(grid_model)
		await process_frame
		_expect_equal(
			debug_view.get_child_count(),
			1,
			"Repeated drawing should release the previous label container."
		)
		_expect_equal(
			debug_view.get_debug_label_count(),
			96,
			"Repeated drawing should replace the active debug labels."
		)
		if debug_view.get_child_count() == 1:
			var label_container := debug_view.get_child(0)
			_expect_true(
				label_container.get_node_or_null("Cell_0_0") != null,
				"Repeated drawing should preserve readable cell label names."
			)

		var large_grid := GridModel.new()
		_expect_true(
			large_grid.configure(1000, 1000, 1.0, Vector3.ZERO),
			"Large-grid configuration should succeed."
		)
		debug_view.draw(large_grid)
		await process_frame
		_expect_equal(
			debug_view.get_child_count(),
			1,
			"Large-grid drawing should keep one active label container."
		)
		_expect_true(
			debug_view.get_debug_label_count() <= maxi(debug_view.max_debug_labels, 1),
			"Large-grid debug sampling should stay within the configured label limit."
		)

	scene.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	if failures == 0:
		print("Scene 01 grid smoke tests passed.")
		quit(0)
		return

	push_error("Scene 01 grid smoke tests failed: %d failure(s)." % failures)
	quit(1)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	failures += 1
	push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])


func _expect_vector3_approx(actual: Vector3, expected: Vector3, message: String) -> void:
	if actual.is_equal_approx(expected):
		return
	failures += 1
	push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])


func _expect_true(value: bool, message: String) -> void:
	if value:
		return
	failures += 1
	push_error(message)

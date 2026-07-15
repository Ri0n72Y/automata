extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"

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
	root.add_child(scene)
	await process_frame

	var grid_root := scene.get_node_or_null("SceneRoot/GridRoot") as Node3D
	var debug_view := scene.get_node_or_null(
		"SceneRoot/GridRoot/GridDebugView"
	) as GridDebugView
	var grid_model := scene.get("grid_model") as GridModel

	_expect_true(grid_root != null, "Scene 01 should contain GridRoot.")
	_expect_true(debug_view != null, "Scene 01 should contain GridDebugView.")
	_expect_true(grid_model != null, "Scene 01 should initialize GridModel.")

	if debug_view != null:
		_expect_equal(
			debug_view.get_debug_label_count(),
			96,
			"Default 12 x 8 grid should create 96 debug labels."
		)

	if grid_root != null and grid_model != null:
		grid_root.position = Vector3(10.0, 0.0, -4.0)
		var world_center: Vector3 = scene.call(
			"grid_cell_to_world",
			Vector2i(0, 0)
		)
		_expect_equal(
			world_center,
			Vector3(10.5, 0.0, -3.5),
			"GridRoot transforms should be applied by the controller world wrapper."
		)
		_expect_equal(
			scene.call("world_to_grid_cell", world_center),
			Vector2i(0, 0),
			"World and grid conversion should round trip through GridRoot."
		)

	if debug_view != null:
		var large_grid := GridModel.new(256, 256, 1.0, Vector3.ZERO)
		debug_view.configure(large_grid)
		_expect_true(
			debug_view.get_debug_label_count() <= maxi(debug_view.max_debug_labels, 1),
			"Large-grid debug output should stay within the configured label limit."
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


func _expect_true(value: bool, message: String) -> void:
	if value:
		return
	failures += 1
	push_error(message)

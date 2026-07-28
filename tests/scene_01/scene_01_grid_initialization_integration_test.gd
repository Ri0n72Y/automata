extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const GRID_MODEL := preload("res://scripts/grid/grid_model.gd")
const READY_PROBE := preload("res://tests/scene_01/grid_ready_probe.gd")
const CONTRACT := preload("res://tests/support/contract_test.gd")

var test := CONTRACT.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var resource := load(SCENE_PATH) as PackedScene
	test.expect_true(resource != null, "Scene 01 should load as PackedScene.")
	if resource == null:
		test.finish(self, "Scene 01 grid initialization integration tests")
		return
	var scene := resource.instantiate()
	var pre_ready_grid_root := scene.get_node_or_null("SceneRoot/GridRoot") as Node3D
	test.expect_true(pre_ready_grid_root != null, "GridRoot should exist before entering the SceneTree.")
	var probe := READY_PROBE.new()
	probe.controller = scene
	if pre_ready_grid_root != null:
		pre_ready_grid_root.add_child(probe)
	root.add_child(scene)
	await process_frame

	var grid_root := scene.get_node_or_null("SceneRoot/GridRoot") as Node3D
	var grid_model := scene.get("grid_model") as GRID_MODEL
	test.expect_true(grid_root != null and grid_model != null, "Scene should initialize GridRoot and GridModel.")
	test.expect_true(probe.grid_model_was_ready, "GridModel should be available before child _ready().")
	test.expect_true(probe.conversion_succeeded, "Child _ready() should be able to call coordinate APIs.")

	if grid_root != null and grid_model != null:
		var transforms: Array[Transform3D] = [
			Transform3D.IDENTITY,
			Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(10.0, 0.0, -4.0)),
			Transform3D(Basis(Vector3.UP, -PI * 0.5).scaled(Vector3(2.0, 1.0, 3.0)), Vector3(-2.0, 0.0, 5.0)),
		]
		var cells := [Vector2i.ZERO, Vector2i(5, 3), Vector2i(11, 7)]
		for transform_value in transforms:
			grid_root.transform = transform_value
			for cell in cells:
				var world_position: Vector3 = scene.call("grid_cell_to_world", cell)
				test.expect_vector3_approx(
					world_position,
					grid_root.to_global(grid_model.cell_to_position(cell)),
					"Controller should apply the current GridRoot transform."
				)
				test.expect_equal(
					scene.call("world_to_grid_cell", world_position),
					cell,
					"World/grid conversion should round trip under GridRoot transforms."
				)

	scene.queue_free()
	await process_frame
	test.finish(self, "Scene 01 grid initialization integration tests")

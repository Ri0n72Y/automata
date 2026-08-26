extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const GRID_MODEL_SCRIPT := preload("res://scripts/grid/grid_model.gd")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for manual-test layout checks.")
	if packed == null:
		_finish()
		return

	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame

	var model := scene.get("grid_model") as GRID_MODEL_SCRIPT
	var pile := scene.get_node_or_null("SceneRoot/ObjectRoot/Scene01ObjectManager/InfiniteBlockPile") as Node3D
	var box := scene.get_node_or_null("SceneRoot/ObjectRoot/Scene01ObjectManager/StandardBox") as Node3D
	var guide_root := scene.get_node_or_null("UIRoot/RootControl") as Control

	_expect_true(model != null, "Manual-test layout requires GridModel.")
	_expect_true(pile != null, "Manual-test layout requires the pile visual.")
	_expect_true(box != null, "Manual-test layout requires the box visual.")
	_expect_true(guide_root != null, "Manual-test layout requires the player guide root.")
	if guide_root != null:
		var guide_theme: Theme = guide_root.theme
		_expect_true(guide_theme != null, "Player guide should provide an explicit UI theme.")
		if guide_theme != null:
			var guide_font: Font = guide_theme.default_font
			_expect_true(
				guide_font != null and guide_font.get_class() == "SystemFont",
				"Player guide should use a SystemFont so Chinese glyphs can resolve from the host OS."
			)
	if model != null:
		_expect_equal(Vector2i(model.width, model.height), Vector2i(16, 10), "Manual-test field should be 16 x 10.")
	if pile != null:
		var pile_cell: Vector2i = scene.call("world_to_grid_cell", pile.global_position)
		_expect_true(bool(scene.call("is_grid_cell_valid", pile_cell)), "Pile visual center must be inside the field.")
	if box != null:
		var box_cell: Vector2i = scene.call("world_to_grid_cell", box.global_position)
		_expect_true(bool(scene.call("is_grid_cell_valid", box_cell)), "Box visual center must be inside the field.")

	_expect_true(
		bool(scene.call("is_grid_footprint_walkable", Vector2i(1, 3), Vector2i(2, 2))),
		"Arm should have a legal 2 x 2 staging anchor beside the pile."
	)
	_expect_true(
		bool(scene.call("is_grid_footprint_walkable", Vector2i(9, 3), Vector2i(2, 2))),
		"Arm should have a legal 2 x 2 staging anchor beside the box."
	)
	_expect_true(
		bool(scene.call("is_grid_footprint_walkable", Vector2i(12, 6), Vector2i(2, 2))),
		"Expanded field should retain an extra 2 x 2 staging area for manual tests."
	)

	scene.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	if failures == 0:
		print("Scene 01 manual-test layout smoke tests passed.")
		quit(0)
		return
	push_error("Scene 01 manual-test layout smoke tests failed: %d failure(s)." % failures)
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

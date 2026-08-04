extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load.")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame

	var object_root := scene.get_node_or_null("SceneRoot/ObjectRoot")
	var manager := scene.get_node_or_null("SceneRoot/ObjectRoot/Scene01ObjectManager") as Scene01ObjectManager
	var pile_node := scene.get_node_or_null("SceneRoot/ObjectRoot/Scene01ObjectManager/InfiniteBlockPile")
	var box_node := scene.get_node_or_null("SceneRoot/ObjectRoot/Scene01ObjectManager/StandardBox")
	_expect_true(object_root != null, "Scene 01 should retain ObjectRoot.")
	_expect_true(manager != null, "Scene 01 should expose a stable object manager node.")
	_expect_true(pile_node != null, "Scene 01 should expose a stable infinite pile node.")
	_expect_true(box_node != null, "Scene 01 should expose a stable standard box node.")

	if manager != null:
		var pile := manager.get_block_pile()
		var box := manager.get_standard_box()
		_expect_equal(box.get_current_count(), 3, "Integrated box should start at three of eight.")
		var produced := pile.take_item()
		_expect_true(produced.is_success(), "Integrated pile should produce a standard block.")
		_expect_true(box.put_item(produced.item).is_success(), "Integrated box should accept pile output.")
		_expect_equal(box.get_current_count(), 4, "Integrated transfer should change box count.")
		manager.reset_objects()
		_expect_equal(box.get_current_count(), 3, "Object manager reset should restore box count.")
		_expect_equal(pile.produced_count, 0, "Object manager reset should restore pile observation state.")

	scene.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	if failures == 0:
		print("Scene 01 object domain smoke tests passed.")
		quit(0)
		return
	push_error("Scene 01 object domain smoke tests failed: %d failure(s)." % failures)
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

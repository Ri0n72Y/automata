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
	var manager := scene.get_node_or_null(
		"SceneRoot/ObjectRoot/Scene01ObjectManager"
	) as Scene01ObjectManager
	var pile_node := scene.get_node_or_null(
		"SceneRoot/ObjectRoot/Scene01ObjectManager/InfiniteBlockPile"
	) as Scene01ItemSourceNode
	var box_node := scene.get_node_or_null(
		"SceneRoot/ObjectRoot/Scene01ObjectManager/StandardBox"
	) as Scene01ItemReceiverNode
	_expect_true(object_root != null, "Scene 01 should retain ObjectRoot.")
	_expect_true(manager != null, "Scene 01 should expose a stable object manager node.")
	_expect_true(pile_node != null, "Scene 01 should expose a source interface node.")
	_expect_true(box_node != null, "Scene 01 should expose a receiver interface node.")

	if manager != null and pile_node != null and box_node != null:
		var pile := manager.get_block_pile()
		var box := manager.get_standard_box()
		var source := pile_node.get_source_interface()
		var receiver := box_node.get_receiver_interface()
		_expect_true(source != null, "Pile node should expose its source interface.")
		_expect_true(receiver != null, "Box node should expose its receiver interface.")
		_expect_true(source == manager.get_block_pile_source(), "Manager and node should share source.")
		_expect_true(
			receiver == manager.get_standard_box_receiver(),
			"Manager and node should share receiver."
		)
		_expect_equal(
			pile_node.get_output_item_type(),
			StandardBlock.TYPE_ID,
			"Scene source node should advertise standard blocks."
		)
		_expect_true(pile_node.is_available(), "Scene pile source should be available.")
		_expect_true(pile_node.is_infinite(), "Scene pile source should remain infinite.")
		_expect_true(
			box_node.accepts_item_type(StandardBlock.TYPE_ID),
			"Scene receiver node should accept standard blocks."
		)
		_expect_true(
			box_node.get_accepted_item_types().has(StandardBlock.TYPE_ID),
			"Scene receiver node should advertise accepted standard blocks."
		)
		_expect_equal(box_node.get_capacity(), 8, "Integrated box capacity should be eight.")
		_expect_equal(box_node.get_current_count(), 3, "Integrated box should start at three.")

		var produced := pile_node.take_item()
		_expect_true(produced.is_success(), "Integrated source should produce a standard block.")
		_expect_true(box_node.put_item(produced.item).is_success(), "Receiver should accept source output.")
		_expect_equal(box_node.get_current_count(), 4, "Integrated transfer should change box count.")
		_expect_equal(scene.get("box_count"), 4, "Scene legacy box count should follow domain events.")
		_expect_equal(pile.get_produced_count(), 1, "Integrated pile should track production.")

		scene.call("reset_scene")
		_expect_equal(box_node.get_current_count(), 3, "Scene reset should restore box count.")
		_expect_equal(pile.get_produced_count(), 0, "Scene reset should restore pile state.")
		_expect_equal(scene.get("box_count"), 3, "Scene reset should synchronize legacy box count.")
		_expect_true(
			pile_node.get_source_interface() == source,
			"Scene reset should preserve the stable source interface instance."
		)
		_expect_true(
			box_node.get_receiver_interface() == receiver,
			"Scene reset should preserve the stable receiver interface instance."
		)
		_expect_true(box == manager.get_standard_box(), "Scene reset should preserve domain objects.")

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

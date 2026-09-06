extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const MANAGER_PATH := "SceneRoot/ObjectRoot/Scene01ObjectManager"
const PILE_PATH := MANAGER_PATH + "/InfiniteBlockPile"
const BOX_PATH := MANAGER_PATH + "/StandardBox"

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load.")
	if packed == null:
		_finish()
		return

	var first_scene: Node = packed.instantiate()
	var second_scene: Node = packed.instantiate()
	root.add_child(first_scene)
	root.add_child(second_scene)
	await process_frame

	var first_manager := first_scene.get_node_or_null(MANAGER_PATH) as Scene01ObjectManager
	var first_pile_node := first_scene.get_node_or_null(PILE_PATH) as Scene01ItemSourceNode
	var first_box_node := first_scene.get_node_or_null(BOX_PATH) as Scene01ItemReceiverNode
	var second_manager := second_scene.get_node_or_null(MANAGER_PATH) as Scene01ObjectManager
	var second_pile_node := second_scene.get_node_or_null(PILE_PATH) as Scene01ItemSourceNode
	var second_box_node := second_scene.get_node_or_null(BOX_PATH) as Scene01ItemReceiverNode
	_expect_true(
		first_manager != null and first_pile_node != null and first_box_node != null
		and second_manager != null and second_pile_node != null and second_box_node != null,
		"Both Scene 01 instances expose their static object composition."
	)

	if (
		first_manager != null
		and first_pile_node != null
		and first_box_node != null
		and second_manager != null
		and second_pile_node != null
		and second_box_node != null
	):
		var first_source: ItemSourceInterface = first_pile_node.get_source_interface()
		var first_receiver: ItemReceiverInterface = first_box_node.get_receiver_interface()
		var second_source: ItemSourceInterface = second_pile_node.get_source_interface()
		var second_receiver: ItemReceiverInterface = second_box_node.get_receiver_interface()
		_expect_true(first_source != null and first_receiver != null, "First scene exposes object interfaces.")
		_expect_true(second_source != null and second_receiver != null, "Second scene exposes object interfaces.")
		_expect_true(first_source == first_manager.get_block_pile_source(), "Manager exposes the static pile resource.")
		_expect_true(first_receiver == first_manager.get_standard_box_receiver(), "Manager exposes the static box resource.")
		_expect_true(first_source.resource_local_to_scene and first_receiver.resource_local_to_scene, "Object resources are local to scene.")
		_expect_true(first_source != second_source and first_receiver != second_receiver, "Scene instances do not share object state.")
		_expect_equal(first_box_node.get_current_count(), 3, "First box starts at 3/8.")
		_expect_equal(second_box_node.get_current_count(), 3, "Second box starts independently at 3/8.")

		var produced := first_pile_node.take_item()
		_expect_true(produced.is_success(), "Integrated pile produces a standard block.")
		_expect_true(first_box_node.put_item(produced.item).is_success(), "Integrated box accepts pile output.")
		_expect_equal(first_box_node.get_current_count(), 4, "First scene transfer changes only its box.")
		_expect_equal(second_box_node.get_current_count(), 3, "Second scene remains unchanged.")

		first_scene.call("reset_scene")
		_expect_equal(first_box_node.get_current_count(), 3, "Scene Reset restores first box.")
		_expect_true(first_pile_node.get_source_interface() == first_source, "Reset preserves static source resource identity.")
		_expect_true(first_box_node.get_receiver_interface() == first_receiver, "Reset preserves static receiver resource identity.")

	first_scene.queue_free()
	second_scene.queue_free()
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

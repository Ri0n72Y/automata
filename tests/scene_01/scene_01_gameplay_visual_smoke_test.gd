extends SceneTree

const GridTransformFollowerScript := preload("res://scripts/scene_01/grid_transform_follower.gd")
const VehicleStateVisualScript := preload("res://scripts/vehicles/vehicle_state_visual.gd")

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const BLOCK_SCENE_PATH := "res://scenes/scene_01/objects/standard_block_placeholder.tscn"
const GRID_ROOT_PATH := "SceneRoot/GridRoot"
const OBJECT_ROOT_PATH := "SceneRoot/ObjectRoot"
const OBJECT_MANAGER_PATH := OBJECT_ROOT_PATH + "/Scene01ObjectManager"
const PILE_PATH := OBJECT_MANAGER_PATH + "/InfiniteBlockPile"
const BOX_PATH := OBJECT_MANAGER_PATH + "/StandardBox"
const VEHICLE_MANAGER_PATH := "SceneRoot/RobotRoot/Scene01VehicleManager"

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_standard_block_scene()

	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for visual verification.")
	if packed == null:
		_finish()
		return

	var scene: Node = packed.instantiate()
	root.add_child(scene)
	await process_frame

	var grid_root: Node3D = scene.get_node_or_null(GRID_ROOT_PATH) as Node3D
	var object_root: GridTransformFollowerScript = scene.get_node_or_null(
		OBJECT_ROOT_PATH
	) as GridTransformFollowerScript
	var pile_node: Scene01ItemSourceNode = scene.get_node_or_null(PILE_PATH) as Scene01ItemSourceNode
	var box_node: Scene01ItemReceiverNode = scene.get_node_or_null(BOX_PATH) as Scene01ItemReceiverNode
	var vehicle_manager: Scene01VehicleManager = scene.get_node_or_null(
		VEHICLE_MANAGER_PATH
	) as Scene01VehicleManager
	_expect_true(grid_root != null, "Scene should contain GridRoot.")
	_expect_true(object_root != null, "ObjectRoot should use the grid transform follower.")
	_expect_true(pile_node != null, "Scene should contain the pile visual scene.")
	_expect_true(box_node != null, "Scene should contain the box visual scene.")
	_expect_true(vehicle_manager != null, "Scene should contain the vehicle manager.")

	if pile_node != null:
		_expect_true(
			pile_node.get_node_or_null("VisualRoot/Base") is MeshInstance3D,
			"Pile should contain a static base mesh."
		)
		var source_label: Label3D = pile_node.get_node_or_null("VisualRoot/SourceLabel") as Label3D
		_expect_true(source_label != null, "Pile should expose a source label.")
		if source_label != null:
			_expect_true(source_label.text.contains("∞"), "Pile label should communicate infinite output.")

	if box_node != null:
		var capacity_slots: Node3D = box_node.get_node_or_null("VisualRoot/CapacitySlots") as Node3D
		_expect_true(capacity_slots != null, "Box should expose a capacity slot root.")
		if capacity_slots != null:
			_expect_equal(capacity_slots.get_child_count(), 8, "Box should contain eight visual slots.")
		_expect_equal(box_node.get_visible_slot_count(), 3, "Box should initially show three blocks.")
		_expect_equal(box_node.get_capacity_label_text(), "3/8  IN", "Box label should show 3/8.")

	if pile_node != null and box_node != null:
		var produced: ItemTransferResult = pile_node.take_item()
		_expect_true(produced.is_success(), "Pile should produce a block for visual update.")
		_expect_true(box_node.put_item(produced.item).is_success(), "Box should accept the produced block.")
		_expect_equal(box_node.get_visible_slot_count(), 4, "Box should show four blocks after put.")
		_expect_equal(box_node.get_capacity_label_text(), "4/8  IN", "Box label should show 4/8.")

	if vehicle_manager != null:
		_test_vehicle_state_visuals(vehicle_manager)

	if grid_root != null and object_root != null:
		scene.call("preview_rotate_grid", 1)
		await process_frame
		_expect_equal(
			object_root.global_transform,
			grid_root.global_transform,
			"ObjectRoot should follow the complete GridRoot transform."
		)

	scene.call("reset_scene")
	await process_frame
	if box_node != null:
		_expect_equal(box_node.get_visible_slot_count(), 3, "Reset should restore three box slots.")
		_expect_equal(box_node.get_capacity_label_text(), "3/8  IN", "Reset should restore box label.")
	if vehicle_manager != null:
		_assert_reset_vehicle_visuals(vehicle_manager)
	if grid_root != null and object_root != null:
		_expect_equal(
			object_root.global_transform,
			grid_root.global_transform,
			"Reset should keep object and grid transforms aligned."
		)

	scene.queue_free()
	await process_frame
	_finish()


func _test_standard_block_scene() -> void:
	var packed: PackedScene = load(BLOCK_SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Standard block visual scene should load.")
	if packed == null:
		return
	var block: Node = packed.instantiate()
	_expect_true(block.get_node_or_null("BlockBody") is MeshInstance3D, "Block should contain a body mesh.")
	_expect_true(block.get_node_or_null("TopBand") is MeshInstance3D, "Block should contain a distinct top band.")
	block.free()


func _test_vehicle_state_visuals(vehicle_manager: Scene01VehicleManager) -> void:
	var arm_actor: VehicleActor = vehicle_manager.get_vehicle_by_id(&"arm_vehicle")
	var transport_actor: VehicleActor = vehicle_manager.get_vehicle_by_id(&"transport_vehicle")
	_expect_true(arm_actor != null, "Arm vehicle should exist for state visual testing.")
	_expect_true(transport_actor != null, "Transport vehicle should exist for state visual testing.")
	if arm_actor == null or transport_actor == null:
		return

	var arm_visual: VehicleStateVisualScript = arm_actor.get_node_or_null("VisualRoot") as VehicleStateVisualScript
	var transport_visual: VehicleStateVisualScript = transport_actor.get_node_or_null("VisualRoot") as VehicleStateVisualScript
	_expect_true(arm_visual != null, "Arm VisualRoot should use the state presenter.")
	_expect_true(transport_visual != null, "Transport VisualRoot should use the state presenter.")
	if arm_visual == null or transport_visual == null:
		return
	if arm_actor.runtime_state == null or transport_actor.runtime_state == null:
		_expect_true(false, "Vehicle runtime states should be configured before visual testing.")
		return

	arm_visual.refresh_visual(true)
	transport_visual.refresh_visual(true)
	_expect_true(not arm_visual.is_carry_warning_visible(), "Carry warning should start hidden.")
	_expect_equal(transport_visual.get_visible_tray_slot_count(), 0, "Tray should start empty.")
	_expect_equal(transport_visual.get_tray_count_label_text(), "0/8", "Tray should start at 0/8.")

	_expect_true(arm_actor.runtime_state.set_arm_has_item(true), "Arm state should accept carrying preview.")
	_expect_true(transport_actor.runtime_state.set_tray_count(5), "Transport state should accept tray preview.")
	arm_visual.refresh_visual(true)
	transport_visual.refresh_visual(true)
	_expect_true(arm_visual.is_carry_warning_visible(), "Carrying state should show yellow warning.")
	_expect_equal(transport_visual.get_visible_tray_slot_count(), 5, "Tray should show five loaded slots.")
	_expect_equal(transport_visual.get_tray_count_label_text(), "5/8", "Tray label should show 5/8.")


func _assert_reset_vehicle_visuals(vehicle_manager: Scene01VehicleManager) -> void:
	var arm_actor: VehicleActor = vehicle_manager.get_vehicle_by_id(&"arm_vehicle")
	var transport_actor: VehicleActor = vehicle_manager.get_vehicle_by_id(&"transport_vehicle")
	if arm_actor == null or transport_actor == null:
		_expect_true(false, "Reset visual checks require both vehicles.")
		return
	var arm_visual: VehicleStateVisualScript = arm_actor.get_node_or_null("VisualRoot") as VehicleStateVisualScript
	var transport_visual: VehicleStateVisualScript = transport_actor.get_node_or_null("VisualRoot") as VehicleStateVisualScript
	if arm_visual == null or transport_visual == null:
		_expect_true(false, "Reset visual checks require both state presenters.")
		return
	arm_visual.refresh_visual(true)
	transport_visual.refresh_visual(true)
	_expect_true(not arm_visual.is_carry_warning_visible(), "Reset should hide carry warning.")
	_expect_equal(transport_visual.get_visible_tray_slot_count(), 0, "Reset should clear tray slots.")
	_expect_equal(transport_visual.get_tray_count_label_text(), "0/8", "Reset should clear tray label.")


func _finish() -> void:
	if failures == 0:
		print("Scene 01 gameplay visual smoke tests passed.")
		quit(0)
		return
	push_error("Scene 01 gameplay visual smoke tests failed: %d failure(s)." % failures)
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
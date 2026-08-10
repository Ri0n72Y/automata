extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const VEHICLE_MANAGER_SCRIPT := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const VEHICLE_RUNTIME_STATE_SCRIPT := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const MOVE_COMMAND_SCRIPT := preload("res://scripts/vehicles/move_command.gd")
const STANDARD_BLOCK_SCRIPT := preload("res://scripts/objects/standard_block.gd")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for GrabDrop isolation tests.")
	if packed == null:
		_finish()
		return

	var first_scene := packed.instantiate()
	var second_scene := packed.instantiate()
	root.add_child(first_scene)
	root.add_child(second_scene)
	await process_frame
	await physics_frame

	var first_manager = first_scene.get_node_or_null("SceneRoot/ObjectRoot/Scene01ObjectManager")
	var second_manager = second_scene.get_node_or_null("SceneRoot/ObjectRoot/Scene01ObjectManager")
	var first_grab_drop = first_scene.get_node_or_null("SceneRoot/GridRoot/VehicleGrabDropController")
	var second_grab_drop = second_scene.get_node_or_null("SceneRoot/GridRoot/VehicleGrabDropController")
	var first_vehicle_manager = first_scene.get_node_or_null(
		"SceneRoot/RobotRoot/Scene01VehicleManager"
	) as VEHICLE_MANAGER_SCRIPT
	var first_selection = first_scene.get_node_or_null("SceneRoot/GridRoot/VehicleSelectionController")
	var first_status = first_scene.get_node_or_null(
		"UIRoot/RootControl/Panel/Margin/VBox/StatusLabel"
	) as Label
	var second_status = second_scene.get_node_or_null(
		"UIRoot/RootControl/Panel/Margin/VBox/StatusLabel"
	) as Label

	_expect_true(first_manager != null and second_manager != null, "Both Scene01 instances need object managers.")
	_expect_true(first_grab_drop != null and second_grab_drop != null, "Both Scene01 instances need GrabDrop controllers.")
	_expect_true(first_vehicle_manager != null and first_selection != null, "First Scene01 needs vehicle interaction nodes.")
	_expect_true(first_status != null and second_status != null, "Both Scene01 instances need status labels.")
	if (
		first_manager == null
		or second_manager == null
		or first_grab_drop == null
		or second_grab_drop == null
		or first_vehicle_manager == null
		or first_selection == null
	):
		await _finish_scenes(first_scene, second_scene)
		return

	_test_static_scene_resources(first_manager, second_manager, first_grab_drop, second_grab_drop)
	_test_ground_policy_and_instance_isolation(first_scene, second_scene, first_manager, second_manager)
	_test_moving_tray_is_not_interactable(first_grab_drop, first_selection, first_vehicle_manager)
	_test_feedback_is_instance_local(first_grab_drop, first_selection, first_vehicle_manager, first_status, second_status)

	await _finish_scenes(first_scene, second_scene)


func _test_static_scene_resources(first_manager, second_manager, first_grab_drop, second_grab_drop) -> void:
	var first_field = first_manager.get_ground_block_field()
	var second_field = second_manager.get_ground_block_field()
	_expect_true(first_field != null and second_field != null, "GroundBlockField resources should be statically assigned.")
	if first_field != null and second_field != null:
		_expect_true(first_field.resource_local_to_scene, "GroundBlockField should be local to each Scene01 instance.")
		_expect_true(second_field.resource_local_to_scene, "Second GroundBlockField should also be local to scene.")
		_expect_true(first_field != second_field, "Scene01 instances must not share GroundBlockField state.")

	for controller in [first_grab_drop, second_grab_drop]:
		_expect_true(
			controller.get_node_or_null("GrabDropInteractionPreview/Slot0") is MeshInstance3D,
			"GrabDrop preview slot 0 should come from the static PackedScene."
		)
		_expect_true(
			controller.get_node_or_null("GrabDropInteractionPreview/Slot1") is MeshInstance3D,
			"GrabDrop preview slot 1 should come from the static PackedScene."
		)
		_expect_true(
			controller.get_node_or_null("GrabDropInteractionPreview_0") == null,
			"GrabDrop controller must not create legacy runtime preview meshes."
		)


func _test_ground_policy_and_instance_isolation(first_scene, second_scene, first_manager, second_manager) -> void:
	_expect_true(
		first_manager.get_ground_cell_interface(Vector2i(-1, -1)) == null,
		"Scene adapter should reject an out-of-grid ground cell."
	)
	var first_field = first_manager.get_ground_block_field()
	_expect_true(
		first_field == null or first_field.get_cell_interface(Vector2i(-1, -1)) == null,
		"GroundBlockField policy should reject the same out-of-grid cell."
	)

	var first_cell := Vector2i(4, 1)
	var second_cell := Vector2i(5, 1)
	var first_interface = first_manager.get_ground_cell_interface(first_cell)
	var second_interface = second_manager.get_ground_cell_interface(second_cell)
	_expect_true(first_interface != null and second_interface != null, "Both instances should expose legal ground cells.")
	if first_interface == null or second_interface == null:
		return
	var first_block := STANDARD_BLOCK_SCRIPT.create()
	var second_block := STANDARD_BLOCK_SCRIPT.create()
	_expect_true(first_interface.put_item(first_block).is_success(), "First instance should accept a ground block.")
	_expect_true(second_interface.put_item(second_block).is_success(), "Second instance should accept an independent ground block.")
	_expect_true(first_manager.get_ground_block_visual(first_cell) != null, "First ground visual should belong to first Scene01.")
	_expect_true(second_manager.get_ground_block_visual(second_cell) != null, "Second ground visual should belong to second Scene01.")
	_expect_true(second_manager.get_ground_block_visual(first_cell) == null, "First visual must not leak into second Scene01.")
	_expect_true(first_manager.get_ground_block_visual(second_cell) == null, "Second visual must not leak into first Scene01.")

	first_scene.call("reset_scene")
	_expect_false(first_manager.has_ground_block(first_cell), "Resetting first Scene01 should clear only its ground state.")
	_expect_true(second_manager.has_ground_block(second_cell), "Resetting first Scene01 must preserve second ground state.")
	_expect_false(first_block.is_claimed(), "First reset should release first block ownership.")
	_expect_true(second_block.is_claimed_by(second_manager.get_ground_block_field()), "Second block ownership should remain local.")

	second_scene.call("reset_scene")


func _test_moving_tray_is_not_interactable(controller, selection, vehicle_manager) -> void:
	var arm = vehicle_manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.ARM_VEHICLE_ID)
	var transport = vehicle_manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.TRANSPORT_VEHICLE_ID)
	_expect_true(arm != null and transport != null, "Moving tray test requires both vehicles.")
	if arm == null or transport == null or arm.runtime_state == null or transport.runtime_state == null:
		return

	var waiting_interfaces: Array[Variant] = transport.runtime_state.get_item_interaction_interfaces(
		transport.get_occupied_cells()
	)
	_expect_true(waiting_interfaces.has(transport.runtime_state.tray_state), "Waiting transport should expose tray interface.")

	_expect_true(transport.runtime_state.begin_move_planning(), "Transport should enter Planning for interaction boundary.")
	_expect_equal(
		transport.runtime_state.get_item_interaction_interfaces(transport.get_occupied_cells()).size(),
		0,
		"Planning transport must not expose tray interaction interfaces."
	)
	transport.runtime_state.clear_move_command()

	var start: Vector2i = transport.runtime_state.anchor_cell
	var target := start + Vector2i(-1, 0)
	var move := MOVE_COMMAND_SCRIPT.new()
	_expect_true(move.configure(target, [start, target]), "Moving tray fixture should configure a MoveCommand.")
	_expect_true(transport.start_move(move), "Transport should enter Moving for interaction boundary.")
	_expect_equal(
		transport.runtime_state.motion_state,
		VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.MOVING,
		"Transport fixture should actually be Moving."
	)
	_expect_equal(
		transport.runtime_state.get_item_interaction_interfaces(transport.get_occupied_cells()).size(),
		0,
		"Moving transport must not expose tray interaction interfaces."
	)

	_expect_true(selection.select_vehicle(arm), "Arm should be selectable while transport moves.")
	arm.runtime_state.anchor_cell = Vector2i(start.x - 2, start.y)
	arm.runtime_state.facing = VEHICLE_RUNTIME_STATE_SCRIPT.Facing.EAST
	arm.sync_from_state()
	_expect_true(
		controller.resolve_target_for_vehicle(arm) != transport.runtime_state.tray_state,
		"Moving transport tray must not resolve as a GrabDrop target at its stale logical anchor."
	)

	transport.cancel_move()
	_expect_equal(
		transport.runtime_state.motion_state,
		VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.BLOCKED,
		"Cancel should leave transport Blocked."
	)
	var blocked_interfaces: Array[Variant] = transport.runtime_state.get_item_interaction_interfaces(
		transport.get_occupied_cells()
	)
	_expect_true(blocked_interfaces.has(transport.runtime_state.tray_state), "Blocked stationary transport should expose tray again.")


func _test_feedback_is_instance_local(controller, selection, vehicle_manager, first_status: Label, second_status: Label) -> void:
	if first_status == null or second_status == null:
		return
	var arm = vehicle_manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.ARM_VEHICLE_ID)
	if arm == null or arm.runtime_state == null:
		return
	arm.reset_actor()
	arm.runtime_state.anchor_cell = Vector2i(1, 3)
	arm.runtime_state.facing = VEHICLE_RUNTIME_STATE_SCRIPT.Facing.WEST
	arm.sync_from_state()
	_expect_true(selection.select_vehicle(arm), "Feedback isolation fixture should select first-scene arm.")
	var second_before := second_status.text
	var result = controller.request_selected_grab_drop()
	_expect_true(result.is_success(), "First Scene01 Grab should succeed for feedback isolation.")
	_expect_equal(first_status.text, "抓取成功", "First Scene01 player UI should receive localized controller feedback.")
	_expect_equal(second_status.text, second_before, "Second Scene01 UI must not receive first controller feedback.")


func _finish_scenes(first_scene: Node, second_scene: Node) -> void:
	first_scene.queue_free()
	second_scene.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	if failures == 0:
		print("Scene 01 GrabDrop isolation tests passed.")
		quit(0)
		return
	push_error("Scene 01 GrabDrop isolation tests failed: %d failure(s)." % failures)
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


func _expect_false(value: bool, message: String) -> void:
	if not value:
		return
	failures += 1
	push_error(message)

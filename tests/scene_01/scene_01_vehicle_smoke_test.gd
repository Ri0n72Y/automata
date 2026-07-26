extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const VEHICLE_MANAGER_SCRIPT := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const VEHICLE_ACTOR_SCRIPT := preload("res://scripts/vehicles/vehicle_actor.gd")
const VEHICLE_DEFINITION_SCRIPT := preload("res://scripts/vehicles/vehicle_definition.gd")
const VEHICLE_RUNTIME_STATE_SCRIPT := preload("res://scripts/vehicles/vehicle_runtime_state.gd")

var failures: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	_expect_true(packed_scene != null, "Scene 01 should load for vehicle tests.")
	if packed_scene == null:
		_finish()
		return
	var scene := packed_scene.instantiate()
	root.add_child(scene)
	await process_frame
	var grid_root := scene.get_node_or_null("SceneRoot/GridRoot") as Node3D
	var manager := scene.get_node_or_null("SceneRoot/RobotRoot/Scene01VehicleManager") as VEHICLE_MANAGER_SCRIPT
	_expect_true(grid_root != null, "Scene 01 should contain GridRoot.")
	_expect_true(manager != null, "Scene 01 should contain the vehicle manager.")
	if manager != null:
		_expect_equal(manager.get_vehicle_count(), 2, "Scene 01 should spawn two preset vehicles.")
		var arm := manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.ARM_VEHICLE_ID) as VEHICLE_ACTOR_SCRIPT
		var transport := manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.TRANSPORT_VEHICLE_ID) as VEHICLE_ACTOR_SCRIPT
		_expect_true(arm != null, "Scene 01 should spawn the arm vehicle.")
		_expect_true(transport != null, "Scene 01 should spawn the transport vehicle.")
		if arm != null:
			_test_arm_vehicle(scene, arm)
		if transport != null:
			_test_transport_vehicle(scene, transport)
		if arm != null and transport != null:
			_test_reset(scene, arm, transport)
		if grid_root != null and arm != null:
			_test_grid_transform_sync(scene, grid_root, arm)
		_test_invalid_batch_commit_is_rejected(scene, manager)
		_test_failed_grid_reinitialization_is_atomic(scene, manager)
		_expect_true(bool(scene.call("initialize_grid")), "Reinitializing the grid should rebuild preset vehicles.")
		await process_frame
		_expect_equal(manager.get_vehicle_count(), 2, "Grid reinitialization should not duplicate preset vehicles.")
	scene.queue_free()
	await process_frame
	_finish()

func _test_invalid_batch_commit_is_rejected(scene: Node, manager: VEHICLE_MANAGER_SCRIPT) -> void:
	var original_arm := manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.ARM_VEHICLE_ID)
	var original_transport := manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.TRANSPORT_VEHICLE_ID)
	_expect_false(manager.commit_vehicle_batch(scene, null), "Null preparation should be rejected.")
	_expect_equal(manager.get_vehicle_count(), 2, "Rejected commit should preserve vehicle count.")
	_expect_true(manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.ARM_VEHICLE_ID) == original_arm, "Rejected commit should preserve arm Actor.")
	_expect_true(manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.TRANSPORT_VEHICLE_ID) == original_transport, "Rejected commit should preserve transport Actor.")
	var preparation = manager.prepare_vehicle_batch(scene, scene.get("grid_cell_size"))
	_expect_true(preparation != null, "Valid preparation should succeed.")
	_expect_true(manager.discard_vehicle_batch(preparation), "Prepared batch should be discardable once.")
	_expect_false(manager.commit_vehicle_batch(scene, preparation), "Consumed preparation should not commit.")
	_expect_false(manager.discard_vehicle_batch(preparation), "Consumed preparation should not discard twice.")
	_expect_equal(manager.get_vehicle_count(), 2, "Consumed token misuse should preserve current vehicles.")

func _test_arm_vehicle(scene: Node, arm: VEHICLE_ACTOR_SCRIPT) -> void:
	var definition = arm.definition
	var runtime = arm.runtime_state
	_expect_true(definition != null, "Arm actor should expose its definition.")
	_expect_true(runtime != null, "Arm actor should expose its runtime state.")
	if definition == null or runtime == null:
		return
	_expect_equal(definition.vehicle_kind, VEHICLE_DEFINITION_SCRIPT.VehicleKind.ARM, "Arm actor should use the arm preset definition.")
	_expect_equal(definition.footprint, Vector2i(2, 2), "Arm actor should occupy 2x2 cells.")
	_expect_true(runtime.definition == definition, "Arm actor and runtime should share one definition.")
	_expect_true(definition.has_capability(VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_GRAB), "Arm actor should expose can_grab.")
	_assert_actor_grid_state(scene, arm, "Arm vehicle")
	_expect_true(arm.get_visual_part(&"ArmColumn") != null, "Arm visual should contain a column.")
	_expect_true(arm.get_visual_part(&"ArmBeam") != null, "Arm visual should contain a beam.")
	_expect_true(arm.get_visual_part(&"Tray") == null, "Arm visual should not contain a tray.")
	_expect_true(arm.get_debug_label_text().contains("18.0 kg"), "Arm debug label should show weight.")
	_assert_selection_area(arm, VEHICLE_MANAGER_SCRIPT.ARM_VEHICLE_ID, "Arm vehicle")

func _test_transport_vehicle(scene: Node, transport: VEHICLE_ACTOR_SCRIPT) -> void:
	var definition = transport.definition
	var runtime = transport.runtime_state
	_expect_true(definition != null, "Transport actor should expose its definition.")
	_expect_true(runtime != null, "Transport actor should expose its runtime state.")
	if definition == null or runtime == null:
		return
	_expect_equal(definition.vehicle_kind, VEHICLE_DEFINITION_SCRIPT.VehicleKind.TRANSPORT, "Transport actor should use the transport preset definition.")
	_expect_equal(definition.footprint, Vector2i(2, 2), "Transport actor should occupy 2x2 cells.")
	_expect_equal(definition.tray_capacity, 8, "Transport actor should expose tray capacity eight.")
	_expect_true(runtime.definition == definition, "Transport actor and runtime should share one definition.")
	_assert_actor_grid_state(scene, transport, "Transport vehicle")
	_expect_true(transport.get_visual_part(&"Tray") != null, "Transport visual should contain a tray.")
	_expect_true(transport.get_visual_part(&"ArmColumn") == null, "Transport visual should not contain an arm column.")
	_expect_true(transport.get_debug_label_text().contains("16.0 kg"), "Transport debug label should show weight.")
	_assert_selection_area(transport, VEHICLE_MANAGER_SCRIPT.TRANSPORT_VEHICLE_ID, "Transport vehicle")

func _assert_selection_area(actor: VEHICLE_ACTOR_SCRIPT, expected_id: StringName, context: String) -> void:
	var selection_area := actor.get_selection_area()
	_expect_true(selection_area != null, "%s should expose a selection area." % context)
	if selection_area == null:
		return
	_expect_equal(selection_area.collision_layer, 2, "%s selection should not use ground layer 1." % context)
	_expect_equal(selection_area.get_meta("vehicle_id", &""), expected_id, "%s selection area should identify its vehicle." % context)

func _assert_actor_grid_state(scene: Node, actor: VEHICLE_ACTOR_SCRIPT, context: String) -> void:
	var definition = actor.definition
	var runtime = actor.runtime_state
	var expected_world: Vector3 = scene.call("grid_footprint_center_to_world", runtime.anchor_cell, definition.footprint)
	_expect_vector3_approx(actor.global_position, expected_world, "%s should be centered over its footprint." % context)
	var occupied_cells := actor.get_occupied_cells()
	_expect_equal(occupied_cells.size(), 4, "%s should expose four occupied cells." % context)
	for cell in occupied_cells:
		_expect_true(bool(scene.call("is_grid_cell_walkable", cell)), "%s occupied cell %s should be walkable." % [context, str(cell)])

func _test_reset(scene: Node, arm: VEHICLE_ACTOR_SCRIPT, transport: VEHICLE_ACTOR_SCRIPT) -> void:
	var arm_initial_cell: Vector2i = arm.runtime_state.anchor_cell
	var transport_initial_cell: Vector2i = transport.runtime_state.anchor_cell
	arm.runtime_state.anchor_cell = Vector2i(4, 2)
	arm.runtime_state.motion_state = VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.MOVING
	arm.runtime_state.set_arm_has_item(true)
	arm.sync_from_state()
	transport.runtime_state.anchor_cell = Vector2i(6, 4)
	transport.runtime_state.set_tray_count(5)
	transport.sync_from_state()
	scene.call("reset_scene")
	_expect_equal(arm.runtime_state.anchor_cell, arm_initial_cell, "Reset should restore arm start cell.")
	_expect_equal(transport.runtime_state.anchor_cell, transport_initial_cell, "Reset should restore transport start cell.")
	_expect_false(arm.runtime_state.arm_has_item, "Reset should clear arm carried-item state.")
	_expect_equal(transport.runtime_state.tray_count, 0, "Reset should clear transport tray count.")
	_expect_equal(arm.runtime_state.motion_state, VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.WAITING, "Reset should restore Waiting state.")

func _test_grid_transform_sync(scene: Node, grid_root: Node3D, arm: VEHICLE_ACTOR_SCRIPT) -> void:
	grid_root.position = Vector3(5.0, 0.0, -2.0)
	grid_root.rotation.y = PI / 2.0
	grid_root.scale = Vector3(1.5, 1.0, 2.0)
	arm.sync_from_state()
	var expected_world: Vector3 = scene.call("grid_footprint_center_to_world", arm.runtime_state.anchor_cell, arm.definition.footprint)
	_expect_vector3_approx(arm.global_position, expected_world, "Vehicle actor should follow transformed GridRoot coordinates.")
	var expected_basis := grid_root.global_basis * Basis(Vector3.UP, -float(arm.runtime_state.facing) * PI * 0.5)
	_expect_vector3_approx(arm.global_basis.x, expected_basis.x, "Actor basis X should match grid and facing.")
	_expect_vector3_approx(arm.global_basis.y, expected_basis.y, "Actor basis Y should match grid and facing.")
	_expect_vector3_approx(arm.global_basis.z, expected_basis.z, "Actor basis Z should match grid and facing.")

func _test_failed_grid_reinitialization_is_atomic(scene: Node, manager: VEHICLE_MANAGER_SCRIPT) -> void:
	var previous_model = scene.get("grid_model")
	var previous_width: int = previous_model.width
	var previous_height: int = previous_model.height
	var previous_count := manager.get_vehicle_count()
	var original_arm := manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.ARM_VEHICLE_ID) as VEHICLE_ACTOR_SCRIPT
	var original_transport := manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.TRANSPORT_VEHICLE_ID) as VEHICLE_ACTOR_SCRIPT
	if original_arm == null or original_transport == null:
		failures += 1
		return
	var original_arm_runtime = original_arm.runtime_state
	var original_transport_runtime = original_transport.runtime_state
	original_arm_runtime.anchor_cell = Vector2i(4, 3)
	original_arm_runtime.motion_state = VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.MOVING
	original_arm_runtime.enqueue_command({"type": "MoveTo", "target": Vector2i(4, 3)})
	original_arm_runtime.set_arm_has_item(true)
	original_transport_runtime.set_tray_count(5)
	original_arm.sync_from_state()
	original_transport.sync_from_state()
	scene.set("grid_width", 4)
	scene.set("grid_height", 4)
	_expect_false(bool(scene.call("initialize_grid")), "A grid that cannot contain preset starts should be rejected.")
	var restored_model = scene.get("grid_model")
	var restored_arm := manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.ARM_VEHICLE_ID) as VEHICLE_ACTOR_SCRIPT
	var restored_transport := manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.TRANSPORT_VEHICLE_ID) as VEHICLE_ACTOR_SCRIPT
	_expect_true(restored_model == previous_model, "Rejected grid should preserve the GridModel instance.")
	_expect_equal(restored_model.width, previous_width, "Failed initialization should preserve grid width.")
	_expect_equal(restored_model.height, previous_height, "Failed initialization should preserve grid height.")
	_expect_equal(manager.get_vehicle_count(), previous_count, "Failed initialization should preserve a complete vehicle batch.")
	_expect_true(restored_arm == original_arm, "Rejected grid should preserve the arm Actor instance.")
	_expect_true(restored_transport == original_transport, "Rejected grid should preserve the transport Actor instance.")
	_expect_true(restored_arm.runtime_state == original_arm_runtime, "Rejected grid should preserve the arm RuntimeState instance.")
	_expect_true(restored_transport.runtime_state == original_transport_runtime, "Rejected grid should preserve the transport RuntimeState instance.")
	_expect_equal(restored_arm.runtime_state.anchor_cell, Vector2i(4, 3), "Rejected grid should preserve the arm anchor cell.")
	_expect_equal(restored_arm.runtime_state.motion_state, VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.MOVING, "Rejected grid should preserve the arm motion state.")
	_expect_equal(restored_arm.runtime_state.command_queue.size(), 1, "Rejected grid should preserve queued commands.")
	_expect_true(restored_arm.runtime_state.arm_has_item, "Rejected grid should preserve carried-item state.")
	_expect_equal(restored_transport.runtime_state.tray_count, 5, "Rejected grid should preserve tray state.")
	scene.set("grid_width", previous_width)
	scene.set("grid_height", previous_height)

func _finish() -> void:
	if failures == 0:
		print("Scene 01 vehicle smoke tests passed.")
		quit(0)
		return
	push_error("Scene 01 vehicle smoke tests failed: %d failure(s)." % failures)
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

func _expect_false(value: bool, message: String) -> void:
	if not value:
		return
	failures += 1
	push_error(message)

extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const MANAGER := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const ACTOR := preload("res://scripts/vehicles/vehicle_actor.gd")
const DEFINITION := preload("res://scripts/vehicles/vehicle_definition.gd")
const RUNTIME := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const GRID_MODEL := preload("res://scripts/grid/grid_model.gd")
const CONTRACT := preload("res://tests/support/contract_test.gd")

var test := CONTRACT.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := (load(SCENE_PATH) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var grid_root := scene.get_node_or_null("SceneRoot/GridRoot") as Node3D
	var manager := scene.get_node_or_null("SceneRoot/RobotRoot/Scene01VehicleManager") as MANAGER
	test.expect_true(grid_root != null and manager != null, "Vehicle integration dependencies should exist.")
	if grid_root != null and manager != null:
		var arm := manager.get_vehicle_by_id(MANAGER.ARM_VEHICLE_ID) as ACTOR
		var transport := manager.get_vehicle_by_id(MANAGER.TRANSPORT_VEHICLE_ID) as ACTOR
		_test_initial_batch(scene, manager, arm, transport)
		if arm != null and transport != null:
			_test_reset_contract(scene, arm, transport)
			_test_grid_transform_sync(scene, grid_root, arm)
			_test_failed_reinitialization_atomicity(scene, manager, arm, transport)
			await _test_successful_reinitialization(scene, manager, arm, transport)
	scene.queue_free()
	await process_frame
	test.finish(self, "Scene 01 vehicle integration tests")


func _test_initial_batch(scene: Node, manager, arm, transport) -> void:
	test.expect_equal(manager.get_vehicle_count(), 2, "Scene should expose exactly two preset vehicles.")
	test.expect_true(arm != null and transport != null, "Both preset Actors should exist.")
	test.expect_true(manager.get_node_or_null("ArmVehicle") == arm, "Arm should retain its stable node path.")
	test.expect_true(manager.get_node_or_null("TransportVehicle") == transport, "Transport should retain its stable node path.")
	if arm == null or transport == null:
		return
	var cases: Array[Dictionary] = [
		{
			"name": "arm",
			"actor": arm,
			"id": MANAGER.ARM_VEHICLE_ID,
			"kind": DEFINITION.VehicleKind.ARM,
			"weight_text": "18.0 kg",
			"required_part": &"ArmColumn",
			"forbidden_part": &"Tray",
			"tray_capacity": 0,
		},
		{
			"name": "transport",
			"actor": transport,
			"id": MANAGER.TRANSPORT_VEHICLE_ID,
			"kind": DEFINITION.VehicleKind.TRANSPORT,
			"weight_text": "16.0 kg",
			"required_part": &"Tray",
			"forbidden_part": &"ArmColumn",
			"tray_capacity": 8,
		},
	]
	for case in cases:
		var actor = case["actor"]
		test.expect_true(actor.definition != null and actor.runtime_state != null, "%s should expose definition and runtime." % case["name"])
		if actor.definition == null or actor.runtime_state == null:
			continue
		test.expect_equal(actor.definition.vehicle_kind, case["kind"], "%s preset kind." % case["name"])
		test.expect_equal(actor.definition.footprint, Vector2i(2, 2), "%s footprint." % case["name"])
		test.expect_equal(actor.definition.tray_capacity, case["tray_capacity"], "%s tray capacity." % case["name"])
		test.expect_true(actor.runtime_state.definition == actor.definition, "%s should share one definition object." % case["name"])
		test.expect_true(actor.get_visual_part(case["required_part"]) != null, "%s should expose required visual part." % case["name"])
		test.expect_true(actor.get_visual_part(case["forbidden_part"]) == null, "%s should omit forbidden visual part." % case["name"])
		test.expect_true(actor.get_debug_label_text().contains(case["weight_text"]), "%s debug label should show weight." % case["name"])
		_expect_actor_grid_contract(scene, actor, case["name"])
		_expect_selection_area(actor, case["id"], case["name"])


func _expect_actor_grid_contract(scene: Node, actor, context: String) -> void:
	var expected: Vector3 = scene.call("grid_footprint_center_to_world", actor.runtime_state.anchor_cell, actor.definition.footprint)
	test.expect_vector3_approx(actor.global_position, expected, "%s should be centered over its footprint." % context)
	var occupied := actor.get_occupied_cells()
	test.expect_equal(occupied.size(), 4, "%s should expose four occupied cells." % context)
	for cell in occupied:
		test.expect_true(bool(scene.call("is_grid_cell_walkable", cell)), "%s occupied cell %s should be walkable." % [context, str(cell)])


func _expect_selection_area(actor, expected_id: StringName, context: String) -> void:
	var area := actor.get_selection_area()
	test.expect_true(area != null, "%s should expose a selection area." % context)
	if area != null:
		test.expect_equal(area.collision_layer, 2, "%s selection should use layer 2." % context)
		test.expect_equal(area.collision_mask, 0, "%s selection should not query other layers." % context)
		test.expect_equal(area.get_meta("vehicle_id", &""), expected_id, "%s selection metadata." % context)


func _test_reset_contract(scene: Node, arm, transport) -> void:
	var arm_start: Vector2i = arm.runtime_state.anchor_cell
	var transport_start: Vector2i = transport.runtime_state.anchor_cell
	arm.runtime_state.anchor_cell = Vector2i(4, 2)
	arm.runtime_state.motion_state = RUNTIME.MotionState.MOVING
	arm.runtime_state.set_arm_has_item(true)
	transport.runtime_state.anchor_cell = Vector2i(6, 4)
	transport.runtime_state.set_tray_count(5)
	arm.sync_from_state()
	transport.sync_from_state()
	scene.call("reset_scene")
	test.expect_equal(arm.runtime_state.anchor_cell, arm_start, "Reset should restore arm anchor.")
	test.expect_equal(transport.runtime_state.anchor_cell, transport_start, "Reset should restore transport anchor.")
	test.expect_equal(arm.runtime_state.motion_state, RUNTIME.MotionState.WAITING, "Reset should restore Waiting.")
	test.expect_false(arm.runtime_state.arm_has_item, "Reset should clear carried item.")
	test.expect_equal(transport.runtime_state.tray_count, 0, "Reset should clear tray count.")


func _test_grid_transform_sync(scene: Node, grid_root: Node3D, arm) -> void:
	var camera_rig := scene.get_node_or_null("SceneRoot/CameraRoot/Scene01CameraRig") as Node3D
	var operations: Array[Callable] = [
		Callable(scene, "preview_restore_grid_transform"),
		Callable(scene, "preview_rotate_grid").bind(1),
		Callable(scene, "preview_toggle_grid_scale"),
		Callable(scene, "preview_toggle_grid_offset"),
		Callable(scene, "preview_restore_grid_transform"),
	]
	for operation in operations:
		operation.call()
		var expected: Vector3 = scene.call("grid_footprint_center_to_world", arm.runtime_state.anchor_cell, arm.definition.footprint)
		test.expect_vector3_approx(arm.global_position, expected, "Grid transform operation should synchronize Actor position.")
		var expected_basis := grid_root.global_basis * Basis(Vector3.UP, -float(arm.runtime_state.facing) * PI * 0.5)
		test.expect_vector3_approx(arm.global_basis.x, expected_basis.x, "Grid transform operation should synchronize Actor basis X.")
		if camera_rig != null:
			var model := scene.get("grid_model") as GRID_MODEL
			var local_center := model.local_origin + Vector3(float(model.width) * model.cell_size * 0.5, 0.0, float(model.height) * model.cell_size * 0.5)
			test.expect_vector3_approx(camera_rig.global_position, grid_root.to_global(local_center), "Grid transform operation should reframe camera center.")


func _test_failed_reinitialization_atomicity(scene: Node, manager, arm, transport) -> void:
	var previous_model = scene.get("grid_model")
	var previous_size := Vector2i(previous_model.width, previous_model.height)
	var arm_runtime = arm.runtime_state
	var transport_runtime = transport.runtime_state
	arm_runtime.anchor_cell = Vector2i(4, 3)
	arm_runtime.motion_state = RUNTIME.MotionState.MOVING
	arm_runtime.enqueue_command({"type": "MoveTo", "target": Vector2i(4, 3)})
	arm_runtime.set_arm_has_item(true)
	transport_runtime.set_tray_count(5)
	arm.sync_from_state()
	transport.sync_from_state()
	scene.set("grid_width", 4)
	scene.set("grid_height", 4)
	var initialized := bool(_quiet(Callable(scene, "initialize_grid")))
	test.expect_false(initialized, "Grid too small for preset starts should be rejected.")
	test.expect_true(scene.get("grid_model") == previous_model, "Rejected initialization should preserve GridModel identity.")
	test.expect_equal(Vector2i(previous_model.width, previous_model.height), previous_size, "Rejected initialization should preserve grid dimensions.")
	test.expect_true(manager.get_vehicle_by_id(MANAGER.ARM_VEHICLE_ID) == arm, "Rejected initialization should preserve arm Actor.")
	test.expect_true(manager.get_vehicle_by_id(MANAGER.TRANSPORT_VEHICLE_ID) == transport, "Rejected initialization should preserve transport Actor.")
	test.expect_true(arm.runtime_state == arm_runtime and transport.runtime_state == transport_runtime, "Rejected initialization should preserve RuntimeState identities.")
	test.expect_equal(arm_runtime.anchor_cell, Vector2i(4, 3), "Rejected initialization should preserve arm anchor.")
	test.expect_equal(arm_runtime.motion_state, RUNTIME.MotionState.MOVING, "Rejected initialization should preserve motion state.")
	test.expect_equal(arm_runtime.command_queue.size(), 1, "Rejected initialization should preserve queued commands.")
	test.expect_true(arm_runtime.arm_has_item, "Rejected initialization should preserve carried item.")
	test.expect_equal(transport_runtime.tray_count, 5, "Rejected initialization should preserve tray state.")
	scene.set("grid_width", previous_size.x)
	scene.set("grid_height", previous_size.y)


func _test_successful_reinitialization(scene: Node, manager, old_arm, old_transport) -> void:
	test.expect_true(bool(scene.call("initialize_grid")), "Valid grid reinitialization should succeed.")
	await process_frame
	test.expect_equal(manager.get_vehicle_count(), 2, "Successful reinitialization should retain one complete batch.")
	var new_arm = manager.get_vehicle_by_id(MANAGER.ARM_VEHICLE_ID)
	var new_transport = manager.get_vehicle_by_id(MANAGER.TRANSPORT_VEHICLE_ID)
	test.expect_true(new_arm != null and new_transport != null, "Successful reinitialization should expose both presets.")
	test.expect_true(new_arm != old_arm and new_transport != old_transport, "Successful reinitialization should replace Actor instances.")
	test.expect_true(manager.get_node_or_null("ArmVehicle") == new_arm, "Replacement arm should retain stable node path.")
	test.expect_true(manager.get_node_or_null("TransportVehicle") == new_transport, "Replacement transport should retain stable node path.")


func _quiet(callback: Callable) -> Variant:
	var previous := Engine.print_error_messages
	Engine.print_error_messages = false
	var result: Variant = callback.call()
	Engine.print_error_messages = previous
	return result

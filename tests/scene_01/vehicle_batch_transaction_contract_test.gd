extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const MANAGER := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const ARM_SCENE := preload("res://scenes/scene_01/vehicles/arm_vehicle_placeholder.tscn")
const CONTRACT := preload("res://tests/support/contract_test.gd")

var test := CONTRACT.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_incomplete_static_batch_rejection()
	var scene := (load(SCENE_PATH) as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	var manager := scene.get_node_or_null("SceneRoot/RobotRoot/Scene01VehicleManager") as MANAGER
	test.expect_true(manager != null, "Scene should expose vehicle manager.")
	if manager != null:
		_test_commit_rejection_is_atomic(scene, manager)
		_test_handle_identity_and_supersession(scene, manager)
		await _test_exit_cleanup(scene, manager)
	scene.queue_free()
	await process_frame
	test.finish(self, "Vehicle batch transaction contract tests")


func _test_incomplete_static_batch_rejection() -> void:
	var manager := MANAGER.new()
	manager.add_child(ARM_SCENE.instantiate())
	var controller := Node.new()
	var configured := bool(_quiet(Callable(manager, "configure").bind(controller, 1.0)))
	test.expect_false(configured, "A manager with one static preset should reject configuration.")
	test.expect_equal(manager.get_child_count(), 1, "Rejected static configuration should not add fallback vehicles.")
	test.expect_false(manager.has_pending_vehicle_batch(), "Rejected static configuration should leave no pending batch.")
	controller.free()
	manager.free()


func _test_commit_rejection_is_atomic(scene: Node, manager) -> void:
	var original_arm = manager.get_vehicle_by_id(MANAGER.ARM_VEHICLE_ID)
	var original_transport = manager.get_vehicle_by_id(MANAGER.TRANSPORT_VEHICLE_ID)
	var invalid_handles: Array = [null]
	var preparation = manager.prepare_vehicle_batch(scene, scene.get("grid_cell_size"))
	test.expect_true(preparation != null, "Valid preparation should succeed.")
	test.expect_true(manager.discard_vehicle_batch(preparation), "Valid preparation should discard once.")
	invalid_handles.append(preparation)
	for handle in invalid_handles:
		test.expect_false(bool(_quiet(Callable(manager, "commit_vehicle_batch").bind(scene, handle))), "Invalid or consumed handle should not commit.")
		test.expect_equal(manager.get_vehicle_count(), 2, "Rejected commit should preserve vehicle count.")
		test.expect_true(manager.get_vehicle_by_id(MANAGER.ARM_VEHICLE_ID) == original_arm, "Rejected commit should preserve arm Actor.")
		test.expect_true(manager.get_vehicle_by_id(MANAGER.TRANSPORT_VEHICLE_ID) == original_transport, "Rejected commit should preserve transport Actor.")
	test.expect_false(manager.discard_vehicle_batch(preparation), "Consumed handle should not discard twice.")


func _test_handle_identity_and_supersession(scene: Node, manager) -> void:
	var first = manager.prepare_vehicle_batch(scene, scene.get("grid_cell_size"))
	test.expect_true(first != null and manager.is_vehicle_batch_preparation_active(first), "Fresh handle should be active.")
	test.expect_true(manager.has_pending_vehicle_batch(), "Fresh handle should retain one pending batch.")
	var second = manager.prepare_vehicle_batch(scene, scene.get("grid_cell_size"))
	test.expect_true(second != null, "Second preparation should succeed.")
	test.expect_false(manager.is_vehicle_batch_preparation_active(first), "New preparation should invalidate the old handle.")
	test.expect_false(bool(_quiet(Callable(manager, "commit_vehicle_batch").bind(scene, first))), "Superseded handle should not commit.")
	test.expect_true(manager.is_vehicle_batch_preparation_active(second), "Newest handle should remain active.")

	var forged := MANAGER.VehicleBatchPreparation.new(scene)
	test.expect_false(manager.is_vehicle_batch_preparation_active(forged), "Same-type forged handle should not become active.")
	test.expect_false(bool(_quiet(Callable(manager, "commit_vehicle_batch").bind(scene, forged))), "Forged handle should fail identity validation.")
	test.expect_true(manager.is_vehicle_batch_preparation_active(second), "Forged-handle rejection should preserve the real handle.")
	test.expect_true(manager.discard_vehicle_batch(second), "Newest real handle should discard.")
	test.expect_false(manager.has_pending_vehicle_batch(), "Discard should release the pending batch.")


func _test_exit_cleanup(scene: Node, manager) -> void:
	var preparation = manager.prepare_vehicle_batch(scene, scene.get("grid_cell_size"))
	test.expect_true(preparation != null, "Exit-cleanup preparation should succeed.")
	var pending: Array = manager.get("_prepared_vehicle_batch")
	test.expect_equal(pending.size(), 2, "Pending batch should contain both preset candidates.")
	var references: Array[WeakRef] = []
	for candidate in pending:
		if candidate is Node:
			references.append(weakref(candidate))
			test.expect_true(candidate.get_parent() == null and not candidate.is_inside_tree(), "Prepared candidates should remain detached.")
	var parent := manager.get_parent()
	test.expect_true(parent != null, "Manager should have a parent before exit cleanup.")
	if parent == null:
		return
	parent.remove_child(manager)
	test.expect_false(manager.is_vehicle_batch_preparation_active(preparation), "Tree exit should invalidate the active handle.")
	test.expect_false(manager.has_pending_vehicle_batch(), "Tree exit should release pending candidates.")
	test.expect_false(bool(_quiet(Callable(manager, "commit_vehicle_batch").bind(scene, preparation))), "Exit-cleaned handle should not commit.")
	manager.free()
	await process_frame
	for reference in references:
		test.expect_true(reference.get_ref() == null, "Tree exit should free detached candidates.")


func _quiet(callback: Callable) -> Variant:
	var previous := Engine.print_error_messages
	Engine.print_error_messages = false
	var result: Variant = callback.call()
	Engine.print_error_messages = previous
	return result

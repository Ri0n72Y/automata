extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const VEHICLE_MANAGER_SCRIPT := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	_expect_true(packed_scene != null, "Scene 01 should load for preparation lifecycle tests.")
	if packed_scene == null:
		_finish()
		return

	var scene := packed_scene.instantiate()
	root.add_child(scene)
	await process_frame
	var manager := scene.get_node_or_null(
		"SceneRoot/RobotRoot/Scene01VehicleManager"
	) as VEHICLE_MANAGER_SCRIPT
	_expect_true(manager != null, "Scene 01 should contain the vehicle manager.")
	if manager != null:
		_test_new_preparation_replaces_old(scene, manager)
		_test_forged_preparation_is_rejected(scene, manager)
		await _test_exit_tree_discards_pending(scene, manager)

	scene.queue_free()
	await process_frame
	_finish()


func _test_new_preparation_replaces_old(
	scene: Node,
	manager: VEHICLE_MANAGER_SCRIPT
) -> void:
	var first = manager.prepare_vehicle_batch(scene, scene.get("grid_cell_size"))
	_expect_true(first != null, "First preparation should succeed.")
	_expect_true(
		manager.is_vehicle_batch_preparation_active(first),
		"Fresh preparation should be the active opaque handle."
	)
	_expect_true(manager.has_pending_vehicle_batch(), "Manager should retain one pending batch.")

	var second = manager.prepare_vehicle_batch(scene, scene.get("grid_cell_size"))
	_expect_true(second != null, "Second preparation should succeed.")
	_expect_false(
		manager.is_vehicle_batch_preparation_active(first),
		"Preparing again should invalidate the previous handle."
	)
	_expect_false(
		manager.commit_vehicle_batch(scene, first),
		"Superseded preparation should not commit."
	)
	_expect_true(
		manager.is_vehicle_batch_preparation_active(second),
		"Only the newest handle should remain active."
	)
	_expect_true(manager.has_pending_vehicle_batch(), "Only the newest batch should remain pending.")
	_expect_true(
		manager.discard_vehicle_batch(second),
		"Newest preparation should remain discardable."
	)
	_expect_false(manager.has_pending_vehicle_batch(), "Discard should release the pending batch.")


func _test_forged_preparation_is_rejected(
	scene: Node,
	manager: VEHICLE_MANAGER_SCRIPT
) -> void:
	var valid = manager.prepare_vehicle_batch(scene, scene.get("grid_cell_size"))
	_expect_true(valid != null, "Valid opaque preparation should be created.")
	var forged := VEHICLE_MANAGER_SCRIPT.VehicleBatchPreparation.new(scene)
	_expect_false(
		manager.is_vehicle_batch_preparation_active(forged),
		"A same-type forged handle should not become active."
	)
	_expect_false(
		manager.commit_vehicle_batch(scene, forged),
		"A same-type forged handle should be rejected by identity."
	)
	_expect_true(
		manager.is_vehicle_batch_preparation_active(valid),
		"Rejecting a forged handle should preserve the valid pending handle."
	)
	_expect_true(
		manager.discard_vehicle_batch(valid),
		"The original valid handle should remain discardable."
	)


func _test_exit_tree_discards_pending(
	scene: Node,
	manager: VEHICLE_MANAGER_SCRIPT
) -> void:
	var preparation = manager.prepare_vehicle_batch(scene, scene.get("grid_cell_size"))
	_expect_true(preparation != null, "Exit cleanup preparation should succeed.")
	_expect_true(manager.has_pending_vehicle_batch(), "Manager should have a pending batch before cleanup.")

	var pending_batch: Array = manager.get("_prepared_vehicle_batch")
	_expect_true(pending_batch.size() == 2, "Pending preparation should contain both preset actors.")
	var candidate_refs: Array[WeakRef] = []
	for candidate in pending_batch:
		if candidate is Node:
			candidate_refs.append(weakref(candidate))
			_expect_true(candidate.get_parent() == null, "Prepared actor should remain detached before commit.")
			_expect_false(candidate.is_inside_tree(), "Prepared actor should not enter the SceneTree before commit.")

	var manager_parent: Node = manager.get_parent()
	_expect_true(manager_parent != null, "Manager should have a parent before the exit test.")
	if manager_parent == null:
		return
	manager_parent.remove_child(manager)

	_expect_false(
		manager.is_vehicle_batch_preparation_active(preparation),
		"Real tree exit should invalidate the pending opaque handle."
	)
	_expect_false(manager.has_pending_vehicle_batch(), "Real tree exit should release pending actors.")
	_expect_false(
		manager.commit_vehicle_batch(scene, preparation),
		"Exit-cleaned preparation should not commit."
	)

	manager.queue_free()
	await process_frame
	for candidate_ref in candidate_refs:
		_expect_true(
			candidate_ref.get_ref() == null,
			"Pending actors should be freed after the manager exits the SceneTree."
		)


func _finish() -> void:
	if failures == 0:
		print("Vehicle batch preparation smoke tests passed.")
		quit(0)
		return
	push_error("Vehicle batch preparation smoke tests failed: %d failure(s)." % failures)
	quit(1)


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

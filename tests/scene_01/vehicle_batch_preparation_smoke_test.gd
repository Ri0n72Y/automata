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
		_test_exit_tree_discards_pending(scene, manager)

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
	manager._exit_tree()
	_expect_false(
		manager.is_vehicle_batch_preparation_active(preparation),
		"Exit cleanup should invalidate the pending opaque handle."
	)
	_expect_false(manager.has_pending_vehicle_batch(), "Exit cleanup should release pending actors.")
	_expect_false(
		manager.commit_vehicle_batch(scene, preparation),
		"Exit-cleaned preparation should not commit."
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

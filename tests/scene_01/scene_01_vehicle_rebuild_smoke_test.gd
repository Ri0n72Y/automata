extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	_expect_true(packed_scene != null, "Scene 01 should load for vehicle rebuild tests.")
	if packed_scene == null:
		_finish()
		return

	var scene := packed_scene.instantiate()
	root.add_child(scene)
	await process_frame
	var manager := scene.get_node_or_null(
		"SceneRoot/RobotRoot/Scene01VehicleManager"
	) as VehicleManagerScript
	_expect_true(manager != null, "Scene 01 should contain the vehicle manager.")
	if manager == null:
		await _cleanup(scene)
		_finish()
		return

	var initial_arm := manager.get_vehicle_by_id(VehicleManagerScript.ARM_VEHICLE_ID)
	var initial_transport := manager.get_vehicle_by_id(VehicleManagerScript.TRANSPORT_VEHICLE_ID)
	_expect_true(initial_arm != null and initial_transport != null, "Initial preset vehicles should exist.")
	var initial_ids := [
		initial_arm.get_instance_id() if initial_arm != null else 0,
		initial_transport.get_instance_id() if initial_transport != null else 0,
	]

	_expect_true(
		manager.rebuild_vehicles(scene, scene.get("grid_cell_size")),
		"Vehicle manager should rebuild a complete candidate batch."
	)
	_expect_equal(manager.get_vehicle_count(), 2, "Successful rebuild should keep exactly two preset vehicles.")
	var rebuilt_arm := manager.get_vehicle_by_id(VehicleManagerScript.ARM_VEHICLE_ID)
	var rebuilt_transport := manager.get_vehicle_by_id(VehicleManagerScript.TRANSPORT_VEHICLE_ID)
	_expect_true(rebuilt_arm != null and rebuilt_transport != null, "Successful rebuild should expose both vehicle ids.")
	if rebuilt_arm != null and rebuilt_transport != null:
		_expect_false(
			[rebuilt_arm.get_instance_id(), rebuilt_transport.get_instance_id()] == initial_ids,
			"Successful rebuild should replace the previous actors."
		)

	var preserved_arm_id := rebuilt_arm.get_instance_id() if rebuilt_arm != null else 0
	var preserved_transport_id := rebuilt_transport.get_instance_id() if rebuilt_transport != null else 0
	var original_arm_start := manager.arm_start_cell
	manager.arm_start_cell = Vector2i(-1, -1)
	_expect_false(
		manager.rebuild_vehicles(scene, scene.get("grid_cell_size")),
		"Invalid candidate geometry should reject the rebuild."
	)
	manager.arm_start_cell = original_arm_start
	var arm_after_failure := manager.get_vehicle_by_id(VehicleManagerScript.ARM_VEHICLE_ID)
	var transport_after_failure := manager.get_vehicle_by_id(VehicleManagerScript.TRANSPORT_VEHICLE_ID)
	_expect_true(arm_after_failure != null and transport_after_failure != null, "Failed rebuild should preserve the current vehicles.")
	if arm_after_failure != null and transport_after_failure != null:
		_expect_equal(arm_after_failure.get_instance_id(), preserved_arm_id, "Failed rebuild must preserve the current arm actor.")
		_expect_equal(transport_after_failure.get_instance_id(), preserved_transport_id, "Failed rebuild must preserve the current transport actor.")

	await _cleanup(scene)
	_finish()


func _cleanup(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
		await process_frame


func _finish() -> void:
	if failures == 0:
		print("Vehicle rebuild smoke tests passed.")
		quit(0)
		return
	push_error("Vehicle rebuild smoke tests failed: %d failure(s)." % failures)
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

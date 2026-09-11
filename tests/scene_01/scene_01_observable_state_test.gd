extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const ContractTestScript := preload("res://tests/support/contract_test.gd")
const ObservableStateScript := preload("res://scripts/scene_01/scene_01_observable_state.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const RuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const MissionStateScript := preload("res://scripts/scene_01/scene_01_mission_state.gd")
const StandardBlockScript := preload("res://scripts/objects/standard_block.gd")

var test := ContractTestScript.new()
var vehicle_events: Array[Array] = []
var arm_item_events: Array[Array] = []
var tray_events: Array[Vector2i] = []
var box_events: Array[Vector2i] = []
var mission_events: Array[Vector2i] = []
var publication_order: Array[StringName] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	test.expect_true(packed != null, "Scene 01 should load for observable state test.")
	if packed == null:
		test.finish(self, "Scene 01 observable state tests")
		return

	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame

	var observable := scene.get_node_or_null("SceneRoot/Scene01ObservableState") as ObservableStateScript
	var manager := scene.get_node_or_null("SceneRoot/RobotRoot/Scene01VehicleManager") as VehicleManagerScript
	test.expect_true(observable != null and observable.is_configured(), "Observable state should configure in production Scene 01.")
	test.expect_true(manager != null, "Observable state test requires vehicle manager.")
	if observable == null or manager == null:
		await _cleanup(scene)
		test.finish(self, "Scene 01 observable state tests")
		return

	var arm = manager.get_vehicle_by_id(VehicleManagerScript.ARM_VEHICLE_ID)
	var transport = manager.get_vehicle_by_id(VehicleManagerScript.TRANSPORT_VEHICLE_ID)
	test.expect_true(arm != null and transport != null, "Observable state test requires both vehicles.")
	if arm == null or transport == null:
		await _cleanup(scene)
		test.finish(self, "Scene 01 observable state tests")
		return

	_bind_events(observable)
	_test_initial_reads(observable)
	_test_vehicle_and_arm_notifications(observable, arm)
	_test_tray_notification(observable, transport)
	_test_box_notification(observable, scene)
	_test_mission_notification(observable, scene)
	await _test_reset_reads(observable, scene)

	await _cleanup(scene)
	test.finish(self, "Scene 01 observable state tests")


func _bind_events(observable: ObservableStateScript) -> void:
	observable.vehicle_state_changed.connect(
		func(vehicle_id: StringName, previous_state: int, current_state: int) -> void:
			vehicle_events.append([vehicle_id, previous_state, current_state])
	)
	observable.arm_has_item_changed.connect(
		func(previous_value: bool, current_value: bool) -> void:
			arm_item_events.append([previous_value, current_value])
	)
	observable.tray_count_changed.connect(
		func(previous_count: int, current_count: int) -> void:
			tray_events.append(Vector2i(previous_count, current_count))
	)
	observable.standard_box_count_changed.connect(
		func(previous_count: int, current_count: int) -> void:
			box_events.append(Vector2i(previous_count, current_count))
			publication_order.append(&"box")
	)
	observable.mission_state_changed.connect(
		func(previous_state: int, current_state: int) -> void:
			mission_events.append(Vector2i(previous_state, current_state))
			publication_order.append(&"mission")
	)


func _test_initial_reads(observable: ObservableStateScript) -> void:
	test.expect_equal(
		observable.get_vehicle_state(VehicleManagerScript.ARM_VEHICLE_ID),
		RuntimeStateScript.MotionState.WAITING,
		"Arm observable state should start WAITING."
	)
	test.expect_equal(
		observable.get_vehicle_state(VehicleManagerScript.TRANSPORT_VEHICLE_ID),
		RuntimeStateScript.MotionState.WAITING,
		"Transport observable state should start WAITING."
	)
	test.expect_false(observable.get_arm_has_item(), "Arm observable cargo should start empty.")
	test.expect_equal(observable.get_tray_count(), 0, "Tray observable count should start at zero.")
	test.expect_equal(observable.get_standard_box_count(), 3, "Box observable count should start at 3.")
	test.expect_equal(observable.get_mission_state(), MissionStateScript.State.READY, "Mission observable state should start READY.")


func _test_vehicle_and_arm_notifications(observable: ObservableStateScript, arm) -> void:
	test.expect_true(arm.runtime_state.begin_move_planning(), "Arm planning fixture should start.")
	test.expect_equal(observable.get_vehicle_state(VehicleManagerScript.ARM_VEHICLE_ID), RuntimeStateScript.MotionState.PLANNING, "Observable state should read owner motion state directly.")
	test.expect_equal(vehicle_events.size(), 1, "Motion change should publish once.")
	if not vehicle_events.is_empty():
		test.expect_equal(vehicle_events[0][0], VehicleManagerScript.ARM_VEHICLE_ID, "Vehicle notification should identify the owner.")
	arm.runtime_state.clear_move_command()

	var block := StandardBlockScript.create()
	test.expect_true(arm.runtime_state.claim_carried_item(block), "Arm cargo fixture should claim a block.")
	test.expect_true(observable.get_arm_has_item(), "Observable cargo should read true from runtime owner.")
	test.expect_equal(arm_item_events.size(), 1, "Cargo change should publish once.")
	test.expect_true(arm.runtime_state.release_carried_item() == block, "Arm cargo fixture should release the same block.")


func _test_tray_notification(observable: ObservableStateScript, transport) -> void:
	var block := StandardBlockScript.create()
	test.expect_true(transport.runtime_state.tray_state.put_item(block).is_success(), "Tray fixture should accept a block.")
	test.expect_equal(observable.get_tray_count(), 1, "Observable tray count should read owner count.")
	test.expect_equal(tray_events, [Vector2i(0, 1)], "Tray count should publish the owner transition once.")


func _test_box_notification(observable: ObservableStateScript, scene: Node) -> void:
	var object_manager = scene.get_node("SceneRoot/ObjectRoot/Scene01ObjectManager")
	var box = object_manager.get_standard_box()
	var block := StandardBlockScript.create()
	test.expect_true(box.put_item(block).is_success(), "Box fixture should accept a block.")
	test.expect_equal(observable.get_standard_box_count(), 4, "Observable box count should read owner count.")
	test.expect_equal(box_events, [Vector2i(3, 4)], "Box count should publish the owner transition once.")


func _test_mission_notification(observable: ObservableStateScript, scene: Node) -> void:
	scene.call("run_scene")
	test.expect_equal(observable.get_mission_state(), MissionStateScript.State.RUNNING, "Observable mission state should read Mission owner state.")
	test.expect_equal(mission_events, [Vector2i(MissionStateScript.State.READY, MissionStateScript.State.RUNNING)], "Mission transition should be forwarded once.")

	var box = scene.get_node("SceneRoot/ObjectRoot/Scene01ObjectManager").get_standard_box()
	while box.get_current_count() < 7:
		test.expect_true(box.put_item(StandardBlockScript.create()).is_success(), "Completion fixture should fill box to 7/8.")
	publication_order.clear()
	test.expect_true(box.put_item(StandardBlockScript.create()).is_success(), "Completion fixture should fill box to 8/8.")
	test.expect_equal(publication_order, [&"box", &"mission"], "Observable should publish the box fact before derived Mission completion.")
	test.expect_equal(observable.get_mission_state(), MissionStateScript.State.COMPLETED, "Observable mission state should expose completion from Mission owner.")


func _test_reset_reads(observable: ObservableStateScript, scene: Node) -> void:
	test.expect_true(bool(scene.call("reset_scene")), "Scene Reset should succeed.")
	await process_frame
	test.expect_equal(observable.get_vehicle_state(VehicleManagerScript.ARM_VEHICLE_ID), RuntimeStateScript.MotionState.WAITING, "Reset should leave arm observable state WAITING.")
	test.expect_false(observable.get_arm_has_item(), "Reset should leave arm observable cargo empty.")
	test.expect_equal(observable.get_tray_count(), 0, "Reset should publish and expose cleared tray count.")
	test.expect_equal(observable.get_standard_box_count(), 3, "Reset should publish and expose restored box count.")
	test.expect_equal(observable.get_mission_state(), MissionStateScript.State.READY, "Reset should expose Mission READY.")


func _cleanup(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
		await process_frame

extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const LifecycleStateScript := preload("res://scripts/scene_01/scene_01_lifecycle_state.gd")
const LifecycleControllerScript := preload("res://scripts/scene_01/scene_01_lifecycle_controller.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const VehicleSelectionScript := preload("res://scripts/input/vehicle_selection_controller.gd")
const GrabDropControllerScript := preload("res://scripts/input/vehicle_grab_drop_controller.gd")
const GrabDropResultScript := preload("res://scripts/vehicles/grab_drop_result.gd")


class CountingAcceptingGate:
	extends Node
	var call_count: int = 0

	func prepare_scene_run() -> bool:
		call_count += 1
		return true


class RejectingGate:
	extends Node
	var call_count: int = 0

	func prepare_scene_run() -> bool:
		call_count += 1
		return false


var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for run preparation contract test.")
	if packed == null:
		_finish()
		return

	var scene := packed.instantiate() as LifecycleControllerScript
	_expect_true(scene != null, "Scene 01 should use the lifecycle controller.")
	if scene == null:
		_finish()
		return
	root.add_child(scene)
	await process_frame

	_expect_true(
		scene.has_method("try_start_gameplay_command"),
		"Lifecycle controller should expose one synchronous gameplay-start boundary."
	)
	_expect_false(
		scene.has_method("begin_gameplay_command_validation"),
		"Lifecycle controller should not expose token begin validation."
	)
	_expect_false(
		scene.has_method("commit_gameplay_command_validation"),
		"Lifecycle controller should not expose token commit validation."
	)
	_expect_false(
		scene.has_method("cancel_gameplay_command_validation"),
		"Lifecycle controller should not expose token cancel validation."
	)

	var vehicle_manager := scene.get_node_or_null(
		"SceneRoot/RobotRoot/Scene01VehicleManager"
	) as VehicleManagerScript
	var vehicle_selection := scene.get_node_or_null(
		"SceneRoot/GridRoot/VehicleSelectionController"
	) as VehicleSelectionScript
	var grab_drop_controller := scene.get_node_or_null(
		"SceneRoot/GridRoot/VehicleGrabDropController"
	) as GrabDropControllerScript
	_expect_true(
		vehicle_manager != null and vehicle_selection != null and grab_drop_controller != null,
		"Run preparation contract test requires vehicle and GrabDrop controllers."
	)
	if vehicle_manager == null or vehicle_selection == null or grab_drop_controller == null:
		await _cleanup(scene)
		_finish()
		return

	var transport := vehicle_manager.get_vehicle_by_id(&"transport_vehicle")
	var arm := vehicle_manager.get_vehicle_by_id(&"arm_vehicle")
	_expect_true(transport != null and arm != null, "Run preparation contract test requires both vehicles.")
	if transport == null or arm == null:
		await _cleanup(scene)
		_finish()
		return

	var gate := CountingAcceptingGate.new()
	gate.name = "CountingAcceptingGate"
	scene.add_child(gate)
	scene.run_preparation_gate_path = NodePath("CountingAcceptingGate")

	_expect_true(vehicle_selection.select_vehicle(transport), "Transport should be selectable.")
	await _push_key(KEY_A)
	_expect_equal(
		gate.call_count,
		1,
		"One failed Viewport A attempt must execute run preparation exactly once."
	)
	_expect_equal(
		scene.get_lifecycle_state(),
		LifecycleStateScript.State.READY,
		"Capability rejection after preparation must keep lifecycle READY."
	)

	var transport_grab_result := grab_drop_controller.request_selected_grab_drop()
	_expect_equal(
		transport_grab_result.status,
		GrabDropResultScript.Status.NO_CAPABILITY,
		"Transport GrabDrop should reject with NO_CAPABILITY after preparation."
	)
	_expect_equal(gate.call_count, 2, "Each READY gameplay attempt should prepare exactly once.")
	_expect_equal(
		scene.get_lifecycle_state(),
		LifecycleStateScript.State.READY,
		"Rejected GrabDrop after preparation must keep lifecycle READY."
	)

	_expect_true(vehicle_selection.select_vehicle(arm), "Arm should be selectable.")
	_expect_true(
		grab_drop_controller.rotate_selected_arm(1),
		"Valid arm rotation should start after preparation and post-compile validation."
	)
	_expect_equal(gate.call_count, 3, "Successful READY command should prepare exactly once.")
	_expect_equal(
		scene.get_lifecycle_state(),
		LifecycleStateScript.State.RUNNING,
		"Successful prepared command should commit lifecycle RUNNING."
	)
	_expect_true(scene.is_running, "Legacy is_running compatibility view should mirror RUNNING.")

	scene.pause_scene()
	_expect_equal(gate.call_count, 3, "Pause must not re-run preparation.")
	scene.resume_scene()
	_expect_equal(gate.call_count, 3, "Resume must not re-run preparation.")

	scene.reset_scene()
	_expect_equal(gate.call_count, 3, "Reset must not itself re-run preparation.")
	_expect_equal(
		scene.get_lifecycle_state(),
		LifecycleStateScript.State.READY,
		"Reset should return READY."
	)

	scene.run_scene()
	_expect_equal(gate.call_count, 4, "A new Run after Reset should enter the gate once.")
	_expect_equal(
		scene.get_lifecycle_state(),
		LifecycleStateScript.State.RUNNING,
		"A new prepared Run after Reset should enter RUNNING."
	)

	scene.reset_scene()
	_expect_true(vehicle_selection.select_vehicle(arm), "Arm should be selectable after second Reset.")
	var rejecting_gate := RejectingGate.new()
	rejecting_gate.name = "RejectingGate"
	scene.add_child(rejecting_gate)
	scene.run_preparation_gate_path = NodePath("RejectingGate")
	var rejected_grab := grab_drop_controller.request_selected_grab_drop()
	_expect_equal(
		rejected_grab.status,
		GrabDropResultScript.Status.RUN_PREPARATION_FAILED,
		"Run preparation rejection must not be reported as vehicle BUSY."
	)
	_expect_equal(rejecting_gate.call_count, 1, "Rejected GrabDrop should prepare exactly once.")
	_expect_equal(
		scene.get_lifecycle_state(),
		LifecycleStateScript.State.READY,
		"Rejected run preparation must keep lifecycle READY."
	)

	await _cleanup(scene)
	_finish()


func _push_key(keycode: int) -> void:
	root.push_input(_key_event(keycode, true))
	await process_frame
	root.push_input(_key_event(keycode, false))
	await process_frame


func _key_event(keycode: int, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = pressed
	event.keycode = keycode
	return event


func _cleanup(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
		await process_frame


func _finish() -> void:
	if failures == 0:
		print("Scene 01 lifecycle run preparation contract tests passed.")
		quit(0)
		return
	push_error("Scene 01 lifecycle run preparation contract tests failed: %d failure(s)." % failures)
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

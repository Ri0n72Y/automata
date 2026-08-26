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
var run_preparation_failures: Array[StringName] = []
var grab_drop_completion_count: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for run preparation behavior test.")
	if packed == null:
		_finish()
		return

	var scene := packed.instantiate() as LifecycleControllerScript
	_expect_true(scene != null, "Scene 01 should use the lifecycle controller.")
	if scene == null:
		_finish()
		return
	scene.lifecycle_run_preparation_failed.connect(_on_run_preparation_failed)
	root.add_child(scene)
	await process_frame

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
		"Run preparation behavior test requires vehicle and GrabDrop controllers."
	)
	if vehicle_manager == null or vehicle_selection == null or grab_drop_controller == null:
		await _cleanup(scene)
		_finish()
		return
	grab_drop_controller.grab_drop_completed.connect(_on_grab_drop_completed)

	var transport := vehicle_manager.get_vehicle_by_id(&"transport_vehicle")
	var arm := vehicle_manager.get_vehicle_by_id(&"arm_vehicle")
	_expect_true(transport != null and arm != null, "Both Scene 01 vehicles should exist.")
	if transport == null or arm == null:
		await _cleanup(scene)
		_finish()
		return

	var accepting_gate := CountingAcceptingGate.new()
	accepting_gate.name = "CountingAcceptingGate"
	scene.add_child(accepting_gate)
	scene.run_preparation_gate_path = NodePath("CountingAcceptingGate")

	_expect_true(vehicle_selection.select_vehicle(transport), "Transport should be selectable.")
	var transport_facing_before: int = transport.runtime_state.facing
	await _push_key(KEY_A)
	_expect_equal(accepting_gate.call_count, 1, "One gameplay input should execute run preparation exactly once.")
	_expect_equal(scene.get_lifecycle_state(), LifecycleStateScript.State.RUNNING, "A gameplay attempt should start the simulation after successful preparation.")
	_expect_equal(transport.runtime_state.facing, transport_facing_before, "Missing arm capability should reject rotation without mutating transport state.")

	_expect_true(scene.reset_scene(), "Reset should succeed before the GrabDrop behavior check.")
	_expect_true(vehicle_selection.select_vehicle(transport), "Transport should be selectable after Reset.")
	var grab_result := grab_drop_controller.request_selected_grab_drop()
	_expect_true(grab_result != null, "A domain GrabDrop rejection should return a real GrabDropResult.")
	if grab_result != null:
		_expect_equal(grab_result.status, GrabDropResultScript.Status.NO_CAPABILITY, "Transport GrabDrop should reject with NO_CAPABILITY.")
	_expect_equal(accepting_gate.call_count, 2, "GrabDrop attempt should prepare once from READY.")
	_expect_equal(scene.get_lifecycle_state(), LifecycleStateScript.State.RUNNING, "Domain command rejection should not roll the simulation back to READY.")

	_expect_true(scene.reset_scene(), "Reset should succeed before rejecting gate coverage.")
	_expect_true(vehicle_selection.select_vehicle(arm), "Arm should be selectable after Reset.")
	var rejecting_gate := RejectingGate.new()
	rejecting_gate.name = "RejectingGate"
	scene.add_child(rejecting_gate)
	scene.run_preparation_gate_path = NodePath("RejectingGate")
	run_preparation_failures.clear()
	grab_drop_completion_count = 0
	var rejected_before_domain := grab_drop_controller.request_selected_grab_drop()
	_expect_true(rejected_before_domain == null, "A lifecycle rejection should not fabricate a GrabDropResult.")
	_expect_equal(rejecting_gate.call_count, 1, "Rejected gameplay start should execute the gate once.")
	_expect_equal(scene.get_lifecycle_state(), LifecycleStateScript.State.READY, "Rejected run preparation should keep READY.")
	_expect_equal(grab_drop_completion_count, 0, "A command blocked before domain execution must not emit grab_drop_completed.")
	_expect_equal(run_preparation_failures, [&"run_preparation_rejected"], "Rejected preparation should expose the lifecycle failure reason.")

	await _cleanup(scene)
	_finish()


func _on_run_preparation_failed(reason: StringName) -> void:
	run_preparation_failures.append(reason)


func _on_grab_drop_completed(_vehicle_id: StringName, _action: int, _status: int) -> void:
	grab_drop_completion_count += 1


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
		print("Scene 01 lifecycle run preparation behavior tests passed.")
		quit(0)
		return
	push_error("Scene 01 lifecycle run preparation behavior tests failed: %d failure(s)." % failures)
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

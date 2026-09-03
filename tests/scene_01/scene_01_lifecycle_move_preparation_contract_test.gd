extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const LifecycleStateScript := preload("res://scripts/scene_01/scene_01_lifecycle_state.gd")
const LifecycleControllerScript := preload("res://scripts/scene_01/scene_01_lifecycle_controller.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const VehicleSelectionScript := preload("res://scripts/input/vehicle_selection_controller.gd")
const VehicleMoveScript := preload("res://scripts/input/vehicle_move_controller.gd")
const GridSelectionScript := preload("res://scripts/input/grid_selection_controller.gd")
const VehicleRuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")


class CountingAcceptingGate:
	extends Node
	var call_count: int = 0

	func prepare_scene_run() -> bool:
		call_count += 1
		return true


var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for MoveTo behavior test.")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate() as LifecycleControllerScript
	_expect_true(scene != null, "Scene 01 should use lifecycle controller.")
	if scene == null:
		_finish()
		return
	root.add_child(scene)
	await process_frame

	var vehicle_manager := scene.get_node_or_null("SceneRoot/RobotRoot/Scene01VehicleManager") as VehicleManagerScript
	var vehicle_selection := scene.get_node_or_null("SceneRoot/GridRoot/VehicleSelectionController") as VehicleSelectionScript
	var move_controller := scene.get_node_or_null("SceneRoot/GridRoot/VehicleMoveController") as VehicleMoveScript
	var grid_selection := scene.get_node_or_null("SceneRoot/GridRoot/GridSelectionController") as GridSelectionScript
	_expect_true(vehicle_manager != null and vehicle_selection != null and move_controller != null and grid_selection != null, "MoveTo behavior test requires Scene 01 movement controllers.")
	if vehicle_manager == null or vehicle_selection == null or move_controller == null or grid_selection == null:
		await _cleanup(scene)
		_finish()
		return

	var gate := CountingAcceptingGate.new()
	gate.name = "CountingAcceptingGate"
	scene.add_child(gate)
	scene.run_preparation_gate_path = NodePath("CountingAcceptingGate")
	var arm := vehicle_manager.get_vehicle_by_id(&"arm_vehicle")
	_expect_true(arm != null and vehicle_selection.select_vehicle(arm), "Arm should exist and be selectable.")
	if arm == null:
		await _cleanup(scene)
		_finish()
		return

	_expect_false(move_controller.request_selected_vehicle_move(Vector2i(-1, -1)), "Invalid MoveTo should be rejected by the MoveTo service.")
	_expect_equal(gate.call_count, 1, "READY MoveTo attempt should execute run preparation once.")
	_expect_equal(scene.get_lifecycle_state(), LifecycleStateScript.State.RUNNING, "Successful run preparation should start simulation even when the domain command is later rejected.")
	_expect_equal(arm.runtime_state.motion_state, VehicleRuntimeStateScript.MotionState.BLOCKED, "Rejected no-path MoveTo should leave the vehicle Blocked without an active command.")
	_expect_true(arm.runtime_state.active_move_command == null, "Rejected MoveTo must not create an active MoveCommand.")
	_expect_equal(move_controller.get_last_rejection_reason(), &"no_path", "MoveTo should preserve its domain no_path rejection reason.")

	_expect_true(scene.reset_scene(), "Reset should succeed before M target mode coverage.")
	_expect_true(vehicle_selection.select_vehicle(arm), "Arm should be selectable after Reset.")
	_expect_true(grid_selection.activate_live_target_mode(), "M-equivalent target mode should start after successful run preparation.")
	_expect_equal(gate.call_count, 2, "M-equivalent activation should execute run preparation once.")
	_expect_equal(scene.get_lifecycle_state(), LifecycleStateScript.State.RUNNING, "M-equivalent activation should leave simulation RUNNING.")
	_expect_true(grid_selection.is_live_target_mode(), "M-equivalent activation should enter target mode.")
	grid_selection.deactivate_live_target_mode()

	scene.pause_scene()
	_expect_equal(gate.call_count, 2, "Pause must not execute run preparation.")
	scene.resume_scene()
	_expect_equal(gate.call_count, 2, "Resume must not execute run preparation.")
	_expect_true(scene.reset_scene(), "Reset should remain functional after Pause/Resume.")
	_expect_equal(gate.call_count, 2, "Reset must not execute run preparation.")

	await _cleanup(scene)
	_finish()


func _cleanup(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
		await process_frame


func _finish() -> void:
	if failures == 0:
		print("Scene 01 lifecycle MoveTo behavior tests passed.")
		quit(0)
		return
	push_error("Scene 01 lifecycle MoveTo behavior tests failed: %d failure(s)." % failures)
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

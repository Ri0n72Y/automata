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
var _scene: LifecycleControllerScript
var reset_observations: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for MoveTo preparation contract test.")
	if packed == null:
		_finish()
		return

	_scene = packed.instantiate() as LifecycleControllerScript
	_expect_true(_scene != null, "Scene 01 should use lifecycle controller.")
	if _scene == null:
		_finish()
		return
	root.add_child(_scene)
	await process_frame

	var vehicle_manager := _scene.get_node_or_null(
		"SceneRoot/RobotRoot/Scene01VehicleManager"
	) as VehicleManagerScript
	var vehicle_selection := _scene.get_node_or_null(
		"SceneRoot/GridRoot/VehicleSelectionController"
	) as VehicleSelectionScript
	var move_controller := _scene.get_node_or_null(
		"SceneRoot/GridRoot/VehicleMoveController"
	) as VehicleMoveScript
	var grid_selection := _scene.get_node_or_null(
		"SceneRoot/GridRoot/GridSelectionController"
	) as GridSelectionScript
	_expect_true(
		vehicle_manager != null
		and vehicle_selection != null
		and move_controller != null
		and grid_selection != null,
		"MoveTo preparation contract test requires Scene 01 movement controllers."
	)
	if (
		vehicle_manager == null
		or vehicle_selection == null
		or move_controller == null
		or grid_selection == null
	):
		await _cleanup_and_finish()
		return

	var gate := CountingAcceptingGate.new()
	gate.name = "CountingAcceptingGate"
	_scene.add_child(gate)
	_scene.run_preparation_gate_path = NodePath("CountingAcceptingGate")

	var arm := vehicle_manager.get_vehicle_by_id(&"arm_vehicle")
	_expect_true(arm != null, "Arm vehicle should exist.")
	if arm == null:
		await _cleanup_and_finish()
		return
	_expect_true(vehicle_selection.select_vehicle(arm), "Arm should be selectable.")
	vehicle_selection.selection_changed.connect(_on_vehicle_selection_changed_during_reset)

	_expect_false(
		move_controller.request_selected_vehicle_move(Vector2i(-1, -1)),
		"Invalid READY MoveTo should be rejected after run preparation."
	)
	_expect_equal(gate.call_count, 1, "Invalid READY MoveTo should execute the run gate once.")
	_expect_equal(
		_scene.get_lifecycle_state(),
		LifecycleStateScript.State.READY,
		"Invalid MoveTo after preparation must keep lifecycle READY."
	)
	_expect_equal(
		arm.runtime_state.motion_state,
		VehicleRuntimeStateScript.MotionState.WAITING,
		"MoveTo preflight rejection must not mutate runtime motion state to Blocked."
	)
	_expect_true(
		arm.runtime_state.active_move_command == null,
		"MoveTo preflight rejection must not create an active MoveCommand."
	)
	_expect_equal(
		move_controller.get_last_rejection_reason(),
		&"no_path",
		"Invalid MoveTo should preserve the existing no_path rejection reason."
	)

	_expect_false(
		_scene.commit_gameplay_command_validation(999999),
		"A fabricated validation token must not bypass run preparation."
	)
	_expect_equal(
		_scene.get_lifecycle_state(),
		LifecycleStateScript.State.READY,
		"Fabricated commit token must keep lifecycle READY."
	)
	_expect_equal(gate.call_count, 1, "Fabricated commit token must not invoke or bypass the gate.")

	_expect_true(
		grid_selection.activate_live_target_mode(),
		"M-equivalent target mode should start after preparation and post-compile move validation."
	)
	_expect_equal(gate.call_count, 2, "READY M-equivalent command should execute the gate exactly once.")
	_expect_equal(
		_scene.get_lifecycle_state(),
		LifecycleStateScript.State.RUNNING,
		"Valid M-equivalent command should commit lifecycle RUNNING."
	)
	_expect_true(grid_selection.is_live_target_mode(), "Valid M-equivalent command should enter target mode.")
	grid_selection.deactivate_live_target_mode()

	_scene.pause_scene()
	_expect_equal(gate.call_count, 2, "Pause must not rerun MoveTo preparation.")
	_scene.resume_scene()
	_expect_equal(gate.call_count, 2, "Resume must not rerun MoveTo preparation.")

	reset_observations.clear()
	_scene.reset_scene()
	_expect_equal(gate.call_count, 2, "Reset must not execute run preparation.")
	_expect_true(
		reset_observations.size() >= 1,
		"Reset should publish at least one vehicle deselection observation."
	)
	if not reset_observations.is_empty():
		_expect_equal(
			reset_observations[0],
			{
				"legacy_running": true,
				"lifecycle_state": LifecycleStateScript.State.RUNNING,
			},
			"Domain reset callbacks should observe legacy is_running matching the formal RUNNING state until lifecycle Reset commits."
		)
	_expect_false(_scene.is_running, "Legacy is_running should be false after lifecycle Reset completes.")
	_expect_equal(
		_scene.get_lifecycle_state(),
		LifecycleStateScript.State.READY,
		"Lifecycle should be READY after Reset completes."
	)

	_expect_true(vehicle_selection.select_vehicle(arm), "Arm should be selectable again after Reset.")
	_scene.run_scene()
	_expect_equal(gate.call_count, 3, "A new explicit Run after Reset should execute the gate once.")
	_expect_equal(
		_scene.get_lifecycle_state(),
		LifecycleStateScript.State.RUNNING,
		"Prepared explicit Run after Reset should enter RUNNING."
	)

	await _cleanup_and_finish()


func _on_vehicle_selection_changed_during_reset(
	_vehicle_id: StringName,
	has_selection: bool
) -> void:
	if has_selection or _scene == null:
		return
	reset_observations.append({
		"legacy_running": _scene.is_running,
		"lifecycle_state": _scene.get_lifecycle_state(),
	})


func _cleanup_and_finish() -> void:
	if _scene != null and is_instance_valid(_scene):
		_scene.queue_free()
		await process_frame
	_finish()


func _finish() -> void:
	if failures == 0:
		print("Scene 01 lifecycle MoveTo preparation contract tests passed.")
		quit(0)
		return
	push_error("Scene 01 lifecycle MoveTo preparation contract tests failed: %d failure(s)." % failures)
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

extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const LifecycleStateScript := preload("res://scripts/scene_01/scene_01_lifecycle_state.gd")
const LifecycleControllerScript := preload("res://scripts/scene_01/scene_01_lifecycle_controller.gd")
const LifecycleControlsScript := preload("res://scripts/scene_01/scene_01_lifecycle_controls.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const VehicleSelectionScript := preload("res://scripts/input/vehicle_selection_controller.gd")
const VehicleMoveScript := preload("res://scripts/input/vehicle_move_controller.gd")
const ObjectManagerScript := preload("res://scripts/scene_01/scene_01_object_manager.gd")


class RejectingRunPreparationGate:
	extends Node
	var call_count: int = 0

	func prepare_scene_run() -> bool:
		call_count += 1
		return false


var failures: int = 0
var lifecycle_events: Array[Dictionary] = []
var run_preparation_failures: Array[StringName] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var baseline_root_child_count := root.get_child_count()
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for lifecycle smoke test.")
	if packed == null:
		_finish()
		return

	var scene := packed.instantiate() as LifecycleControllerScript
	_expect_true(scene != null, "Scene 01 root should use lifecycle controller.")
	if scene == null:
		_finish()
		return
	_bind_lifecycle_events(scene)
	root.add_child(scene)
	await process_frame
	_expect_equal(lifecycle_events, [], "Initial scene construction must not masquerade as an explicit Reset.")

	var lifecycle_ui := scene.get_node_or_null("LifecycleUIRoot") as LifecycleControlsScript
	var run_pause_button := scene.get_node_or_null("LifecycleUIRoot/RootControl/Panel/Margin/Controls/RunPauseButton") as Button
	var speed_button := scene.get_node_or_null("LifecycleUIRoot/RootControl/Panel/Margin/Controls/SpeedButton") as Button
	var vehicle_manager := scene.get_node_or_null("SceneRoot/RobotRoot/Scene01VehicleManager") as VehicleManagerScript
	var vehicle_selection := scene.get_node_or_null("SceneRoot/GridRoot/VehicleSelectionController") as VehicleSelectionScript
	var move_controller := scene.get_node_or_null("SceneRoot/GridRoot/VehicleMoveController") as VehicleMoveScript
	var object_manager := scene.get_node_or_null("SceneRoot/ObjectRoot/Scene01ObjectManager") as ObjectManagerScript
	_expect_true(lifecycle_ui != null and run_pause_button != null and speed_button != null and vehicle_manager != null and vehicle_selection != null and move_controller != null and object_manager != null, "Lifecycle integration dependencies should exist.")
	if lifecycle_ui == null or vehicle_manager == null or vehicle_selection == null or move_controller == null or object_manager == null:
		await _cleanup(scene)
		_finish()
		return

	var arm := vehicle_manager.get_vehicle_by_id(&"arm_vehicle")
	var transport := vehicle_manager.get_vehicle_by_id(&"transport_vehicle")
	_expect_true(arm != null and transport != null, "Scene 01 should provide both vehicles.")
	if arm == null or transport == null:
		await _cleanup(scene)
		_finish()
		return

	_expect_true(scene.is_scene_initialized(), "Valid Scene 01 composition should initialize once before gameplay.")
	_expect_true(object_manager.is_initialized(), "Object domain should be initialized before lifecycle gameplay begins.")
	_expect_equal(scene.get_lifecycle_state(), LifecycleStateScript.State.READY, "Scene should start READY.")
	_expect_equal(scene.get_simulation_speed(), 1.0, "Scene should start at 1x.")
	_expect_equal(run_pause_button.text, "▶", "READY should show play icon.")

	lifecycle_ui._on_run_pause_pressed()
	_expect_equal(scene.get_lifecycle_state(), LifecycleStateScript.State.RUNNING, "Play should enter RUNNING.")
	_expect_equal(run_pause_button.text, "⏸", "RUNNING should show pause icon.")
	_expect_true(vehicle_selection.select_vehicle(arm), "Arm should be selectable.")
	_expect_true(move_controller.request_selected_vehicle_move(Vector2i(4, 2)), "RUNNING should accept a valid MoveTo.")
	move_controller._physics_process(0.20)
	var position_before_pause: Vector3 = arm.global_position
	var anchor_before_pause: Vector2i = arm.runtime_state.anchor_cell
	var command_before_pause = arm.runtime_state.active_move_command
	var timer_before_pause: float = scene.timer
	lifecycle_ui._on_run_pause_pressed()
	_expect_equal(scene.get_lifecycle_state(), LifecycleStateScript.State.PAUSED, "Pause should enter PAUSED.")
	move_controller._physics_process(1.0)
	scene._process(1.0)
	_expect_vector_approx(arm.global_position, position_before_pause, "Paused vehicle should not advance.")
	_expect_equal(arm.runtime_state.anchor_cell, anchor_before_pause, "Pause should preserve discrete anchor.")
	_expect_true(arm.runtime_state.active_move_command == command_before_pause, "Pause should preserve active MoveCommand identity.")
	_expect_float_approx(scene.timer, timer_before_pause, "Paused timer should not advance.")
	_expect_false(move_controller.request_selected_vehicle_stop(), "PAUSED should reject stop requests.")

	lifecycle_ui._on_speed_pressed()
	_expect_equal(scene.get_simulation_speed(), 2.0, "Speed should cycle while paused.")
	_expect_equal(speed_button.text, "2×", "Speed label should update while paused.")
	lifecycle_ui._on_run_pause_pressed()
	move_controller._physics_process(0.20)
	_expect_true(arm.global_position.distance_to(position_before_pause) > 0.01, "Resume should continue the active move.")

	_expect_true(scene.set_simulation_speed(4.0), "4x should be accepted before Reset ordering coverage.")
	scene.pause_scene()
	lifecycle_events.clear()
	_expect_true(scene.reset_scene(), "Explicit Reset should succeed.")
	_expect_equal(scene.get_lifecycle_state(), LifecycleStateScript.State.READY, "Reset should return READY.")
	_expect_equal(scene.get_simulation_speed(), 1.0, "Reset should restore 1x.")
	_expect_equal(arm.runtime_state.anchor_cell, Vector2i(2, 2), "Reset should restore arm anchor.")
	_expect_false(arm.runtime_state.arm_has_item, "Reset should leave arm empty.")
	_expect_equal(transport.runtime_state.tray_count, 0, "Reset should empty transport tray.")
	_expect_equal(scene.box_count, 3, "Reset should restore standard box to 3/8.")
	_expect_equal(lifecycle_events, [
		{"kind": "speed", "previous": 4.0, "current": 1.0},
		{"kind": "state", "previous": LifecycleStateScript.State.PAUSED, "current": LifecycleStateScript.State.READY},
		{"kind": "reset"},
	], "Successful explicit Reset should publish speed, state, then reset-completed.")

	var rejecting_gate := RejectingRunPreparationGate.new()
	rejecting_gate.name = "RejectingRunPreparationGate"
	scene.add_child(rejecting_gate)
	scene.run_preparation_gate_path = NodePath("RejectingRunPreparationGate")
	run_preparation_failures.clear()
	_expect_true(vehicle_selection.select_vehicle(arm), "Arm should be selectable for rejecting gate coverage.")
	var facing_before_rejection: int = arm.runtime_state.facing
	var grab_drop_controller := scene.get_node("SceneRoot/GridRoot/VehicleGrabDropController")
	_expect_false(bool(grab_drop_controller.call("rotate_selected_arm", 1)), "Rejected run preparation should block arm rotation.")
	_expect_equal(arm.runtime_state.facing, facing_before_rejection, "Rejected run preparation must not mutate arm state.")
	_expect_equal(scene.get_lifecycle_state(), LifecycleStateScript.State.READY, "Rejected run preparation should keep READY.")
	_expect_equal(rejecting_gate.call_count, 1, "One rotation attempt should invoke one gate call.")
	_expect_equal(run_preparation_failures, [&"run_preparation_rejected"], "Rejected gate should expose one lifecycle failure.")

	var scene_instance_id := scene.get_instance_id()
	scene.queue_free()
	await process_frame
	_expect_false(is_instance_id_valid(scene_instance_id), "Freed Scene 01 root should not remain alive.")
	_expect_equal(root.get_child_count(), baseline_root_child_count, "Leaving Scene 01 should restore root child count.")
	var reentered_scene := packed.instantiate() as LifecycleControllerScript
	root.add_child(reentered_scene)
	await process_frame
	_expect_equal(reentered_scene.get_lifecycle_state(), LifecycleStateScript.State.READY, "Re-entered scene should start READY.")
	_expect_equal(reentered_scene.get_simulation_speed(), 1.0, "Re-entered scene should start at 1x.")
	await _cleanup(reentered_scene)
	_finish()


func _bind_lifecycle_events(scene: LifecycleControllerScript) -> void:
	scene.lifecycle_state_changed.connect(_on_lifecycle_state_changed)
	scene.simulation_speed_changed.connect(_on_simulation_speed_changed)
	scene.lifecycle_reset_completed.connect(_on_lifecycle_reset_completed)
	scene.lifecycle_run_preparation_failed.connect(_on_run_preparation_failed)


func _on_lifecycle_state_changed(previous_state: int, current_state: int) -> void:
	lifecycle_events.append({"kind": "state", "previous": previous_state, "current": current_state})


func _on_simulation_speed_changed(previous_speed: float, current_speed: float) -> void:
	lifecycle_events.append({"kind": "speed", "previous": previous_speed, "current": current_speed})


func _on_lifecycle_reset_completed() -> void:
	lifecycle_events.append({"kind": "reset"})


func _on_run_preparation_failed(reason: StringName) -> void:
	run_preparation_failures.append(reason)


func _cleanup(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
		await process_frame


func _finish() -> void:
	if failures == 0:
		print("Scene 01 lifecycle smoke tests passed.")
		quit(0)
		return
	push_error("Scene 01 lifecycle smoke tests failed: %d failure(s)." % failures)
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


func _expect_float_approx(actual: float, expected: float, message: String) -> void:
	if is_equal_approx(actual, expected):
		return
	failures += 1
	push_error("%s Expected %f, got %f." % [message, expected, actual])


func _expect_vector_approx(actual: Vector3, expected: Vector3, message: String) -> void:
	if actual.is_equal_approx(expected):
		return
	failures += 1
	push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])

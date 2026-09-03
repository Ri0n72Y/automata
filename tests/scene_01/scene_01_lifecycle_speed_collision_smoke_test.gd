extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const LifecycleControllerScript := preload("res://scripts/scene_01/scene_01_lifecycle_controller.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const VehicleMoveScript := preload("res://scripts/input/vehicle_move_controller.gd")
const VehicleActorScript := preload("res://scripts/vehicles/vehicle_actor.gd")
const MoveCommandScript := preload("res://scripts/vehicles/move_command.gd")
const RuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for speed collision smoke test.")
	if packed == null:
		_finish()
		return

	var scene := packed.instantiate() as LifecycleControllerScript
	_expect_true(scene != null, "Scene 01 root should use the lifecycle controller.")
	if scene == null:
		_finish()
		return
	root.add_child(scene)
	await process_frame

	var manager := scene.get_node_or_null(
		"SceneRoot/RobotRoot/Scene01VehicleManager"
	) as VehicleManagerScript
	var move_controller := scene.get_node_or_null(
		"SceneRoot/GridRoot/VehicleMoveController"
	) as VehicleMoveScript
	_expect_true(manager != null and move_controller != null, "Speed collision test requires vehicle manager and move controller.")
	if manager == null or move_controller == null:
		scene.queue_free()
		await process_frame
		_finish()
		return

	var arm := manager.get_vehicle_by_id(&"arm_vehicle")
	var transport := manager.get_vehicle_by_id(&"transport_vehicle")
	_expect_true(arm != null and transport != null, "Speed collision test requires both vehicles.")
	if arm == null or transport == null:
		scene.queue_free()
		await process_frame
		_finish()
		return

	scene.run_scene()
	_expect_true(scene.set_simulation_speed(1.0), "1x speed should be accepted.")
	_prepare_static_collision(arm, transport)
	move_controller._physics_process(2.0)
	_expect_equal(arm.runtime_state.motion_state, RuntimeStateScript.MotionState.BLOCKED, "1x collision should block arm.")
	_expect_equal(transport.runtime_state.motion_state, RuntimeStateScript.MotionState.WAITING, "1x static target should remain Waiting.")
	var one_x_safe_anchor: Vector2i = arm.runtime_state.anchor_cell
	_expect_equal(one_x_safe_anchor, Vector2i(2, 1), "1x collision should stop at the last safe anchor.")

	_expect_true(scene.set_simulation_speed(4.0), "4x speed should be accepted.")
	_prepare_static_collision(arm, transport)
	move_controller._physics_process(0.5)
	_expect_equal(arm.runtime_state.motion_state, RuntimeStateScript.MotionState.BLOCKED, "4x collision should block arm.")
	_expect_equal(transport.runtime_state.motion_state, RuntimeStateScript.MotionState.WAITING, "4x static target should remain Waiting.")
	_expect_equal(
		arm.runtime_state.anchor_cell,
		one_x_safe_anchor,
		"Equal simulated time at 1x and 4x should produce the same collision-safe anchor."
	)

	scene.queue_free()
	await process_frame
	_finish()


func _prepare_static_collision(
	arm: VehicleActorScript,
	transport: VehicleActorScript
) -> void:
	_place_vehicle(arm, Vector2i(1, 1))
	_place_vehicle(transport, Vector2i(4, 1))
	var command: MoveCommandScript = _command(
		Vector2i(5, 1),
		[
			Vector2i(1, 1),
			Vector2i(2, 1),
			Vector2i(3, 1),
			Vector2i(4, 1),
			Vector2i(5, 1),
		]
	)
	_expect_true(command != null, "Collision fixture command should configure.")
	if command != null:
		_expect_true(arm.start_move(command), "Collision fixture arm task should start.")


func _place_vehicle(vehicle: VehicleActorScript, anchor: Vector2i) -> void:
	vehicle.reset_actor()
	vehicle.runtime_state.anchor_cell = anchor
	vehicle.sync_from_state()


func _command(target: Vector2i, path: Array[Vector2i]) -> MoveCommandScript:
	var command: MoveCommandScript = MoveCommandScript.new()
	if not command.configure(target, path):
		return null
	return command


func _finish() -> void:
	if failures == 0:
		print("Scene 01 lifecycle speed collision smoke tests passed.")
		quit(0)
		return
	push_error("Scene 01 lifecycle speed collision smoke tests failed: %d failure(s)." % failures)
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

extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const ManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const LifecycleStateScript := preload("res://scripts/scene_01/scene_01_lifecycle_state.gd")
const RuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const GrabDropResultScript := preload("res://scripts/vehicles/grab_drop_result.gd")

var _failures: int = 0
var _scene: Node
var _manager: ManagerScript
var _arm: Node
var _selection: Node
var _move_controller: Node
var _grab_drop: Node
var _object_manager: Node
var _gate: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_check(packed != null, "Production Scene 01 loads.")
	if packed == null:
		_finish()
		return

	_scene = packed.instantiate()
	root.add_child(_scene)
	await process_frame
	await physics_frame

	_manager = _scene.get_node_or_null("SceneRoot/RobotRoot/Scene01VehicleManager") as ManagerScript
	_selection = _scene.get_node_or_null("SceneRoot/GridRoot/VehicleSelectionController")
	_move_controller = _scene.get_node_or_null("SceneRoot/GridRoot/VehicleMoveController")
	_grab_drop = _scene.get_node_or_null("SceneRoot/GridRoot/VehicleGrabDropController")
	_object_manager = _scene.get_node_or_null("SceneRoot/ObjectRoot/Scene01ObjectManager")
	_gate = _scene.get_node_or_null("SceneRoot/Scene01AssemblyCompileGate")
	_check(
		_manager != null and _selection != null and _move_controller != null
		and _grab_drop != null and _object_manager != null and _gate != null,
		"Production composition contains the gameplay controllers and compile gate."
	)
	if _manager == null or _selection == null or _move_controller == null or _grab_drop == null or _object_manager == null or _gate == null:
		await _cleanup()
		_finish()
		return

	_arm = _manager.get_vehicle_by_id(ManagerScript.ARM_VEHICLE_ID)
	_check(_arm != null, "Arm vehicle exists.")
	if _arm == null:
		await _cleanup()
		_finish()
		return

	await _test_initial_state_and_auto_run()
	await _test_pause_resume_same_command()
	await _test_real_pile_to_box_flow()
	await _test_reset_and_rerun()

	await _cleanup()
	_finish()


func _test_initial_state_and_auto_run() -> void:
	_check(bool(_scene.call("is_scene_initialized")), "Scene initializes.")
	_check(
		int(_scene.call("get_lifecycle_state")) == LifecycleStateScript.State.READY,
		"Scene starts READY."
	)
	_check(is_equal_approx(float(_scene.call("get_simulation_speed")), 1.0), "Scene starts at 1x.")
	_check(_object_manager.get_standard_box().get_current_count() == 3, "StandardBox starts 3/8.")
	_check(_gate.get_compile_result(&"arm_vehicle") == null, "No runtime compile publication before Run.")

	_check(bool(_selection.call("select_vehicle", _arm)), "Arm can be selected.")
	_check(
		bool(_move_controller.call("request_selected_vehicle_move", Vector2i(5, 2))),
		"READY MoveTo is accepted."
	)
	_check(
		int(_scene.call("get_lifecycle_state")) == LifecycleStateScript.State.RUNNING,
		"First gameplay command starts the scene."
	)
	_check(_compiled_success(&"arm_vehicle") and _compiled_success(&"transport_vehicle"), "Production gate compiled both vehicles before Run.")
	_check(_arm.runtime_state.motion_state == RuntimeStateScript.MotionState.MOVING, "MoveTo started.")


func _test_pause_resume_same_command() -> void:
	var command = _arm.runtime_state.active_move_command
	_check(command != null, "Moving arm has one active command.")
	_move_controller._physics_process(0.2)
	var frozen_position: Vector3 = _arm.global_position
	var frozen_anchor: Vector2i = _arm.runtime_state.anchor_cell

	_scene.call("pause_scene")
	_move_controller._physics_process(1.0)
	_check(
		int(_scene.call("get_lifecycle_state")) == LifecycleStateScript.State.PAUSED,
		"Pause enters PAUSED."
	)
	_check(_arm.global_position.is_equal_approx(frozen_position), "Pause freezes vehicle position.")
	_check(_arm.runtime_state.anchor_cell == frozen_anchor, "Pause freezes anchor progression.")
	_check(_arm.runtime_state.active_move_command == command, "Pause preserves MoveCommand identity.")

	_scene.call("resume_scene")
	_check(_arm.runtime_state.active_move_command == command, "Resume keeps the same MoveCommand.")
	await _wait_arrival(Vector2i(5, 2))
	_check(_arm.runtime_state.motion_state == RuntimeStateScript.MotionState.WAITING, "Resumed MoveTo completes.")


func _test_real_pile_to_box_flow() -> void:
	_check(bool(_scene.call("reset_scene")), "Reset before logistics succeeds.")
	await process_frame
	_check(bool(_selection.call("select_vehicle", _arm)), "Arm can be reselected after Reset.")
	_check(
		bool(_move_controller.call("request_selected_vehicle_move", Vector2i(1, 3))),
		"Arm can MoveTo the pile station."
	)
	await _wait_arrival(Vector2i(1, 3))
	_face(RuntimeStateScript.Facing.WEST)
	var grab_result = _grab_drop.call("request_selected_grab_drop")
	_check(
		grab_result != null and grab_result.status == GrabDropResultScript.Status.ACCEPTED,
		"Pile Grab succeeds through the real controller."
	)
	_check(
		_arm.runtime_state.carried_item != null
		and _arm.runtime_state.carried_item.is_claimed_by(_arm.runtime_state),
		"Grab transfers real block ownership to the arm."
	)

	_check(
		bool(_move_controller.call("request_selected_vehicle_move", Vector2i(13, 3))),
		"Loaded arm can MoveTo the box station."
	)
	await _wait_arrival(Vector2i(13, 3))
	_face(RuntimeStateScript.Facing.EAST)
	var box = _object_manager.get_standard_box()
	var before: int = box.get_current_count()
	var drop_result = _grab_drop.call("request_selected_grab_drop")
	_check(
		drop_result != null and drop_result.status == GrabDropResultScript.Status.ACCEPTED,
		"Box Drop succeeds through the real controller."
	)
	_check(box.get_current_count() == before + 1, "Box count advances exactly once.")
	_check(not _arm.runtime_state.arm_has_item, "Arm is empty after Box Drop.")


func _test_reset_and_rerun() -> void:
	_check(bool(_scene.call("set_simulation_speed", 4.0)), "Dirty state can use 4x speed.")
	_check(bool(_scene.call("reset_scene")), "Dirty-state Reset succeeds.")
	await process_frame
	_check(
		int(_scene.call("get_lifecycle_state")) == LifecycleStateScript.State.READY,
		"Reset returns READY."
	)
	_check(is_equal_approx(float(_scene.call("get_simulation_speed")), 1.0), "Reset restores 1x.")
	_check(_object_manager.get_standard_box().get_current_count() == 3, "Reset restores StandardBox 3/8.")
	_check(not _arm.runtime_state.arm_has_item, "Reset clears arm cargo.")
	_check(_arm.runtime_state.active_move_command == null, "Reset clears active MoveCommand.")

	_check(bool(_selection.call("select_vehicle", _arm)), "Arm can be selected after Reset.")
	_check(
		bool(_move_controller.call("request_selected_vehicle_move", Vector2i(5, 2))),
		"MoveTo works again without reloading the scene."
	)
	await _wait_arrival(Vector2i(5, 2))
	_check(_compiled_success(&"arm_vehicle") and _compiled_success(&"transport_vehicle"), "Compile publication remains healthy after Reset and rerun.")


func _compiled_success(vehicle_id: StringName) -> bool:
	var result = _gate.get_compile_result(vehicle_id)
	return result != null and result.is_success()


func _face(target_facing: int) -> void:
	var guard := 0
	while _arm.runtime_state.facing != target_facing and guard < 4:
		_grab_drop.call("rotate_selected_arm", 1)
		guard += 1
	_check(_arm.runtime_state.facing == target_facing, "Arm reaches required facing.")


func _wait_arrival(target: Vector2i) -> void:
	var steps := 0
	while _arm.runtime_state.motion_state == RuntimeStateScript.MotionState.MOVING and steps < 4000:
		_move_controller._physics_process(0.05)
		steps += 1
		if steps % 400 == 0:
			await process_frame
	_check(_arm.runtime_state.anchor_cell == target, "Vehicle arrives at %s." % str(target))


func _cleanup() -> void:
	if _scene != null and is_instance_valid(_scene):
		_scene.queue_free()
		await process_frame


func _finish() -> void:
	if _failures == 0:
		print("Scene 01 production E2E suite passed.")
		quit(0)
		return
	push_error("Scene 01 production E2E suite failed: %d failure(s)." % _failures)
	quit(1)


func _check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: %s" % message)
		return
	_failures += 1
	push_error("FAIL: %s" % message)

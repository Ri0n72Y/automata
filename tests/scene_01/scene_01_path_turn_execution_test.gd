extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const RUNTIME := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const VEHICLE_MANAGER := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for path-turn execution tests.")
	if packed == null:
		_finish()
		return

	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var manager := scene.get_node_or_null("SceneRoot/RobotRoot/Scene01VehicleManager")
	var selection := scene.get_node_or_null("SceneRoot/GridRoot/VehicleSelectionController")
	var move_controller := scene.get_node_or_null("SceneRoot/GridRoot/VehicleMoveController")
	_expect_true(manager != null and selection != null and move_controller != null, "Path-turn test dependencies should exist.")
	if manager == null or selection == null or move_controller == null:
		await _cleanup(scene)
		return

	var arm = manager.call("get_vehicle_by_id", VEHICLE_MANAGER.ARM_VEHICLE_ID)
	_expect_true(arm != null, "Arm vehicle should exist.")
	if arm == null:
		await _cleanup(scene)
		return

	await _test_straight_path(scene, move_controller, selection, arm)
	await _test_corner_path(scene, move_controller, selection, arm)
	await _test_pause_speed_stop_reset(scene, move_controller, selection, arm)

	await _cleanup(scene)


func _test_straight_path(scene: Node, move_controller: Node, selection: Node, arm: Node) -> void:
	scene.call("reset_scene")
	await process_frame
	_expect_true(bool(scene.call("ensure_gameplay_running")), "Straight-path fixture should start gameplay.")
	_expect_true(bool(selection.call("select_vehicle", arm)), "Straight-path fixture should select Arm.")
	var candidate := _find_candidate(scene, move_controller, arm, 0, true, true)
	_expect_true(not candidate.is_empty(), "Scene should expose an aligned straight MoveTo path.")
	if candidate.is_empty():
		return

	var path: Array = candidate["path"]
	var target: Vector2i = candidate["target"]
	var initial_facing: int = arm.runtime_state.facing
	var turn_count := [0]
	arm.turn_started.connect(func(_direction: int) -> void: turn_count[0] += 1)

	_expect_true(bool(move_controller.call("request_vehicle_move", arm, target)), "Straight MoveTo should be accepted.")
	_expect_equal(arm.runtime_state.facing, initial_facing, "Accepted straight MoveTo must not jump facing.")
	_drive_until_idle(move_controller, arm)

	_expect_equal(turn_count[0], 0, "Aligned straight MoveTo should not add a turn phase.")
	_expect_equal(arm.runtime_state.anchor_cell, target, "Straight MoveTo should reach its target.")
	_expect_equal(
		arm.runtime_state.facing,
		_facing_for_step(path[path.size() - 1] - path[path.size() - 2]),
		"Straight MoveTo final facing should match its traveled segment."
	)


func _test_corner_path(scene: Node, move_controller: Node, selection: Node, arm: Node) -> void:
	scene.call("reset_scene")
	await process_frame
	_expect_true(bool(scene.call("ensure_gameplay_running")), "Corner-path fixture should start gameplay.")
	_expect_true(bool(selection.call("select_vehicle", arm)), "Corner-path fixture should select Arm.")
	var candidate := _find_candidate(scene, move_controller, arm, 1, true, false)
	_expect_true(not candidate.is_empty(), "Scene should expose an aligned MoveTo path with at least one corner.")
	if candidate.is_empty():
		return

	var path: Array = candidate["path"]
	var target: Vector2i = candidate["target"]
	var corners := _corner_cells(path)
	var initial_facing: int = arm.runtime_state.facing
	var turn_anchors: Array[Vector2i] = []
	arm.turn_started.connect(
		func(_direction: int) -> void:
			turn_anchors.append(arm.runtime_state.anchor_cell)
	)

	_expect_true(bool(move_controller.call("request_vehicle_move", arm, target)), "Corner MoveTo should be accepted.")
	_expect_equal(arm.runtime_state.facing, initial_facing, "Accepted corner MoveTo must not publish final facing early.")
	_expect_false(arm.is_turning(), "Aligned first segment should begin by moving, not by an unnecessary turn.")

	var safety := 0
	var observed_turn := false
	while arm.runtime_state.motion_state == RUNTIME.MotionState.MOVING and safety < 1000:
		move_controller.call("_physics_process", 0.05)
		if arm.is_turning():
			observed_turn = true
			var turn_anchor: Vector2i = arm.runtime_state.anchor_cell
			var turn_world: Vector3 = scene.call("grid_footprint_center_to_world", turn_anchor, arm.definition.footprint)
			_expect_true(arm.global_position.is_equal_approx(turn_world), "Automatic corner turn should stay at the reached corner.")
		safety += 1

	_expect_true(safety < 1000, "Corner MoveTo should terminate within the safety bound.")
	_expect_true(observed_turn, "Corner MoveTo should expose a real turn phase.")
	_expect_equal(turn_anchors.size(), corners.size(), "Each path corner should produce one ordered 90-degree turn.")
	for index in range(mini(turn_anchors.size(), corners.size())):
		_expect_equal(turn_anchors[index], corners[index], "Automatic turn should start only after reaching its path corner.")
	_expect_equal(arm.runtime_state.anchor_cell, target, "Corner MoveTo should reach its target.")
	_expect_equal(
		arm.runtime_state.facing,
		_facing_for_step(path[path.size() - 1] - path[path.size() - 2]),
		"Corner MoveTo final facing should come from the last real segment."
	)


func _test_pause_speed_stop_reset(scene: Node, move_controller: Node, selection: Node, arm: Node) -> void:
	scene.call("reset_scene")
	await process_frame
	_expect_true(bool(scene.call("ensure_gameplay_running")), "Lifecycle fixture should start gameplay.")
	_expect_true(bool(selection.call("select_vehicle", arm)), "Lifecycle fixture should select Arm.")
	var candidate := _find_candidate(scene, move_controller, arm, 1, true, false)
	_expect_true(not candidate.is_empty(), "Lifecycle fixture should expose a corner path.")
	if candidate.is_empty():
		return
	var target: Vector2i = candidate["target"]

	_expect_true(bool(move_controller.call("request_vehicle_move", arm, target)), "Lifecycle corner MoveTo should be accepted.")
	_drive_until_turn(move_controller, arm)
	_expect_true(arm.is_turning(), "Lifecycle fixture should reach an automatic turn.")

	var paused_basis: Basis = arm.global_basis
	var paused_facing: int = arm.runtime_state.facing
	scene.call("pause_scene")
	move_controller.call("_physics_process", 1.0)
	_expect_true(arm.is_turning(), "Pause should freeze an automatic turn.")
	_expect_equal(arm.runtime_state.facing, paused_facing, "Pause should freeze turn-facing state.")
	_expect_true(arm.global_basis.is_equal_approx(paused_basis), "Pause should freeze visual turning pose.")

	scene.call("resume_scene")
	_expect_true(bool(scene.call("set_simulation_speed", 0.5)), "Lifecycle fixture should accept 0.5x simulation speed.")
	move_controller.call("_physics_process", 0.15)
	_expect_true(arm.is_turning(), "0.5x speed should leave a 0.3s automatic turn incomplete after 0.15s wall delta.")
	_expect_true(bool(scene.call("set_simulation_speed", 2.0)), "Lifecycle fixture should accept 2x simulation speed.")
	move_controller.call("_physics_process", 0.15)
	_expect_false(arm.is_turning(), "2x speed should advance the same automatic turn faster.")

	scene.call("reset_scene")
	await process_frame
	_expect_true(bool(scene.call("ensure_gameplay_running")), "Stop fixture should restart gameplay.")
	_expect_true(bool(selection.call("select_vehicle", arm)), "Stop fixture should reselect Arm.")
	_expect_true(bool(move_controller.call("request_vehicle_move", arm, target)), "Stop fixture MoveTo should be accepted.")
	_drive_until_turn(move_controller, arm)
	_expect_true(arm.is_turning(), "Stop fixture should reach an automatic turn.")
	_expect_true(bool(move_controller.call("request_selected_vehicle_stop")), "Stop should cancel MoveTo during an automatic turn.")
	_expect_false(arm.is_turning(), "Stop should clear automatic turning state.")
	_expect_equal(arm.runtime_state.motion_state, RUNTIME.MotionState.BLOCKED, "Stop during turn should preserve the MoveTo blocked contract.")

	scene.call("reset_scene")
	await process_frame
	_expect_true(bool(scene.call("ensure_gameplay_running")), "Reset fixture should restart gameplay.")
	_expect_true(bool(selection.call("select_vehicle", arm)), "Reset fixture should reselect Arm.")
	var initial_anchor: Vector2i = arm.runtime_state.anchor_cell
	var initial_facing: int = arm.runtime_state.facing
	_expect_true(bool(move_controller.call("request_vehicle_move", arm, target)), "Reset fixture MoveTo should be accepted.")
	_drive_until_turn(move_controller, arm)
	_expect_true(arm.is_turning(), "Reset fixture should reach an automatic turn.")
	scene.call("reset_scene")
	_expect_false(arm.is_turning(), "Reset should clear an automatic turn safely.")
	_expect_equal(arm.runtime_state.anchor_cell, initial_anchor, "Reset during turn should restore the initial anchor.")
	_expect_equal(arm.runtime_state.facing, initial_facing, "Reset during turn should restore the initial facing.")
	_expect_equal(arm.runtime_state.motion_state, RUNTIME.MotionState.WAITING, "Reset during turn should restore Waiting.")


func _find_candidate(
	scene: Node,
	move_controller: Node,
	vehicle: Node,
	min_corners: int,
	require_initial_alignment: bool,
	require_straight: bool
) -> Dictionary:
	var grid_size: Vector2i = scene.call("get_grid_size")
	for y in range(grid_size.y):
		for x in range(grid_size.x):
			var target := Vector2i(x, y)
			var path: Array = move_controller.call("_find_path", vehicle, target)
			if path.size() < 2:
				continue
			var corners := _corner_cells(path)
			if require_straight and not corners.is_empty():
				continue
			if corners.size() < min_corners:
				continue
			var first_facing := _facing_for_step(path[1] - path[0])
			if require_initial_alignment and first_facing != vehicle.runtime_state.facing:
				continue
			return {"target": target, "path": path}
	return {}


func _corner_cells(path: Array) -> Array[Vector2i]:
	var corners: Array[Vector2i] = []
	if path.size() < 3:
		return corners
	var previous_step: Vector2i = path[1] - path[0]
	for index in range(1, path.size() - 1):
		var next_step: Vector2i = path[index + 1] - path[index]
		if next_step != previous_step:
			corners.append(path[index])
		previous_step = next_step
	return corners


func _facing_for_step(step: Vector2i) -> int:
	if step == Vector2i(1, 0):
		return RUNTIME.Facing.EAST
	if step == Vector2i(-1, 0):
		return RUNTIME.Facing.WEST
	if step == Vector2i(0, 1):
		return RUNTIME.Facing.SOUTH
	if step == Vector2i(0, -1):
		return RUNTIME.Facing.NORTH
	return -1


func _drive_until_turn(move_controller: Node, vehicle: Node) -> void:
	var safety := 0
	while vehicle.runtime_state.motion_state == RUNTIME.MotionState.MOVING and not vehicle.is_turning() and safety < 500:
		move_controller.call("_physics_process", 0.05)
		safety += 1
	_expect_true(safety < 500, "MoveTo should reach a corner turn within the safety bound.")


func _drive_until_idle(move_controller: Node, vehicle: Node) -> void:
	var safety := 0
	while vehicle.runtime_state.motion_state == RUNTIME.MotionState.MOVING and safety < 1000:
		move_controller.call("_physics_process", 0.05)
		safety += 1
	_expect_true(safety < 1000, "MoveTo should terminate within the safety bound.")


func _cleanup(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	_finish()


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
	_expect_true(not value, message)


func _finish() -> void:
	if failures == 0:
		print("Scene 01 path-turn execution tests passed.")
	quit(failures)

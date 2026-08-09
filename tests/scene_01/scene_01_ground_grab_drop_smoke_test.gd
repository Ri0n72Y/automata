extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const GRAB_DROP_CONTROLLER_SCRIPT := preload("res://scripts/input/vehicle_grab_drop_controller.gd")
const VEHICLE_SELECTION_SCRIPT := preload("res://scripts/input/vehicle_selection_controller.gd")
const VEHICLE_MANAGER_SCRIPT := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const OBJECT_MANAGER_SCRIPT := preload("res://scripts/scene_01/scene_01_object_manager.gd")
const VEHICLE_RUNTIME_STATE_SCRIPT := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const GRAB_DROP_RESULT_SCRIPT := preload("res://scripts/vehicles/grab_drop_result.gd")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for ground GrabDrop integration.")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame

	var controller := scene.get_node_or_null(
		"SceneRoot/GridRoot/VehicleGrabDropController"
	) as GRAB_DROP_CONTROLLER_SCRIPT
	var selection := scene.get_node_or_null(
		"SceneRoot/GridRoot/VehicleSelectionController"
	) as VEHICLE_SELECTION_SCRIPT
	var vehicle_manager := scene.get_node_or_null(
		"SceneRoot/RobotRoot/Scene01VehicleManager"
	) as VEHICLE_MANAGER_SCRIPT
	var object_manager := scene.get_node_or_null(
		"SceneRoot/ObjectRoot/Scene01ObjectManager"
	) as OBJECT_MANAGER_SCRIPT
	var status_label := scene.get_node_or_null(
		"UIRoot/RootControl/Panel/Margin/VBox/StatusLabel"
	) as Label
	_expect_true(controller != null, "Ground test requires VehicleGrabDropController.")
	_expect_true(selection != null, "Ground test requires VehicleSelectionController.")
	_expect_true(vehicle_manager != null, "Ground test requires vehicle manager.")
	_expect_true(object_manager != null, "Ground test requires object manager.")
	_expect_true(status_label != null, "Ground test requires manual StatusLabel feedback.")
	if controller == null or selection == null or vehicle_manager == null or object_manager == null:
		scene.queue_free()
		await process_frame
		_finish()
		return

	var arm = vehicle_manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.ARM_VEHICLE_ID)
	_expect_true(arm != null and arm.runtime_state != null, "Ground test requires arm vehicle.")
	if arm == null or arm.runtime_state == null:
		scene.queue_free()
		await process_frame
		_finish()
		return
	_expect_true(selection.select_vehicle(arm), "Ground test should select arm.")
	_test_ground_socket_rotation_contract(controller, arm)

	var pile = object_manager.get_block_pile()
	var ground_field = object_manager.get_ground_block_field()
	_expect_true(pile != null and ground_field != null, "Ground test requires pile and ground field.")
	if pile == null or ground_field == null:
		scene.queue_free()
		await process_frame
		_finish()
		return

	_place_vehicle(arm, Vector2i(1, 3), VEHICLE_RUNTIME_STATE_SCRIPT.Facing.WEST)
	var first_grab = controller.request_selected_grab_drop()
	_expect_equal(first_grab.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "Pile Grab should prepare first ground block.")
	if not first_grab.is_success() or first_grab.item == null:
		await _finish_scene(scene)
		return
	var first_block = first_grab.item
	if status_label != null:
		_expect_equal(status_label.text, "Grab accepted", "Manual feedback should report successful Grab.")

	var ground_anchor := Vector2i(4, 2)
	var ground_cell := Vector2i(4, 1)
	_place_vehicle(arm, ground_anchor, VEHICLE_RUNTIME_STATE_SCRIPT.Facing.NORTH)
	_expect_equal(
		controller.get_primary_ground_interaction_cell(arm),
		ground_cell,
		"North-facing arm should use rotating front-left socket as ground target."
	)
	controller.refresh_interaction_preview()
	_expect_true(controller.is_interaction_preview_visible(), "Loaded arm should show ground interaction preview.")
	_expect_true(controller.is_interaction_preview_valid(), "Empty legal ground target should preview valid.")
	_expect_equal(controller.get_interaction_preview_cells(), [ground_cell], "Ground preview should highlight deterministic single cell.")

	var ground_drop = controller.request_selected_grab_drop()
	_expect_equal(ground_drop.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "Drop to legal ground cell should succeed.")
	_expect_true(ground_field.get_item(ground_cell) == first_block, "Ground Drop should preserve exact block identity.")
	_expect_true(first_block.is_claimed_by(ground_field), "Ground field should own dropped block.")
	_expect_true(object_manager.get_ground_block_visual(ground_cell) != null, "Ground Drop should create StandardBlock visual.")
	if status_label != null:
		_expect_equal(status_label.text, "Drop accepted", "Manual feedback should report successful Drop.")

	controller.refresh_interaction_preview()
	_expect_true(controller.is_interaction_preview_valid(), "Occupied ground should preview valid for empty-arm Grab.")
	_expect_equal(controller.get_interaction_preview_cells(), [ground_cell], "Ground Grab preview should keep same cell.")
	var ground_regrab = controller.request_selected_grab_drop()
	_expect_equal(ground_regrab.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "Empty arm should Grab block back from ground.")
	_expect_true(ground_regrab.item == first_block, "Ground round trip should preserve StandardBlock identity.")
	_expect_true(first_block.is_claimed_by(arm.runtime_state), "Re-grabbed ground block should return to arm ownership.")
	_expect_false(ground_field.has_item(ground_cell), "Ground cell should be empty after re-Grab.")
	_expect_true(object_manager.get_ground_block_visual(ground_cell) == null, "Ground visual registry should clear after re-Grab.")

	var second_drop = controller.request_selected_grab_drop()
	_expect_equal(second_drop.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "First block should be dropped back for occupied fixture.")
	_expect_true(first_block.is_claimed_by(ground_field), "Occupied fixture should leave first block ground-owned.")

	_place_vehicle(arm, Vector2i(1, 3), VEHICLE_RUNTIME_STATE_SCRIPT.Facing.WEST)
	var second_grab = controller.request_selected_grab_drop()
	_expect_equal(second_grab.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "Pile should provide second block.")
	if not second_grab.is_success() or second_grab.item == null:
		await _finish_scene(scene)
		return
	var second_block = second_grab.item
	_place_vehicle(arm, ground_anchor, VEHICLE_RUNTIME_STATE_SCRIPT.Facing.NORTH)
	controller.refresh_interaction_preview()
	_expect_true(controller.is_interaction_preview_visible(), "Occupied ground Drop target should still preview.")
	_expect_false(controller.is_interaction_preview_valid(), "Occupied ground Drop target should preview invalid.")
	_expect_equal(controller.get_interaction_preview_cells(), [ground_cell], "Occupied preview should identify blocking ground cell.")

	var occupied_drop = controller.request_selected_grab_drop()
	_expect_equal(
		occupied_drop.status,
		GRAB_DROP_RESULT_SCRIPT.Status.GROUND_OCCUPIED,
		"Second Drop to occupied ground should reject explicitly."
	)
	_expect_true(arm.runtime_state.carried_item == second_block, "Occupied rejection must preserve second block on arm.")
	_expect_true(second_block.is_claimed_by(arm.runtime_state), "Occupied rejection must restore arm ownership.")
	_expect_true(ground_field.get_item(ground_cell) == first_block, "Occupied rejection must preserve first ground block.")
	if status_label != null:
		_expect_equal(status_label.text, "Drop rejected: ground occupied", "Manual feedback should explain occupied ground rejection.")

	_place_vehicle(arm, Vector2i(1, 3), VEHICLE_RUNTIME_STATE_SCRIPT.Facing.WEST)
	_expect_true(
		controller.resolve_target_for_vehicle(arm) == null,
		"Loaded arm facing pile must not fall back to ground under static pile interaction cells."
	)

	scene.call("reset_scene")
	await process_frame
	_expect_false(first_block.is_claimed(), "Scene Reset should release ground block ownership.")
	_expect_false(second_block.is_claimed(), "Scene Reset should release carried block ownership.")
	_expect_equal(ground_field.get_occupied_cells().size(), 0, "Scene Reset should clear all ground blocks.")
	_expect_true(object_manager.get_ground_block_visual(ground_cell) == null, "Scene Reset should clear ground visuals.")

	_expect_true(selection.select_vehicle(arm), "Arm should be selectable after Reset.")
	_place_vehicle(arm, ground_anchor, VEHICLE_RUNTIME_STATE_SCRIPT.Facing.NORTH)
	controller.refresh_interaction_preview()
	_expect_true(controller.is_interaction_preview_visible(), "Empty arm should still show forward interaction edge.")
	_expect_false(controller.is_interaction_preview_valid(), "Empty ground with empty arm should preview invalid.")
	selection.cancel_selection()
	controller.refresh_interaction_preview()
	_expect_false(controller.is_interaction_preview_visible(), "Cancelling selection should hide interaction preview.")

	await _finish_scene(scene)


func _test_ground_socket_rotation_contract(controller, arm) -> void:
	var anchor := Vector2i(4, 3)
	var cases: Array[Dictionary] = [
		{"facing": VEHICLE_RUNTIME_STATE_SCRIPT.Facing.NORTH, "cell": Vector2i(4, 2), "name": "North"},
		{"facing": VEHICLE_RUNTIME_STATE_SCRIPT.Facing.EAST, "cell": Vector2i(6, 3), "name": "East"},
		{"facing": VEHICLE_RUNTIME_STATE_SCRIPT.Facing.SOUTH, "cell": Vector2i(5, 5), "name": "South"},
		{"facing": VEHICLE_RUNTIME_STATE_SCRIPT.Facing.WEST, "cell": Vector2i(3, 4), "name": "West"},
	]
	for socket_case: Dictionary in cases:
		_place_vehicle(arm, anchor, int(socket_case["facing"]))
		_expect_equal(
			controller.get_primary_ground_interaction_cell(arm),
			socket_case["cell"],
			"%s facing should rotate the same front-left ground socket." % String(socket_case["name"])
		)


func _place_vehicle(vehicle, anchor: Vector2i, facing: int) -> void:
	vehicle.runtime_state.anchor_cell = anchor
	vehicle.runtime_state.facing = facing
	vehicle.sync_from_state()


func _finish_scene(scene: Node) -> void:
	scene.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	if failures == 0:
		print("Scene 01 ground GrabDrop smoke tests passed.")
		quit(0)
		return
	push_error("Scene 01 ground GrabDrop smoke tests failed: %d failure(s)." % failures)
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

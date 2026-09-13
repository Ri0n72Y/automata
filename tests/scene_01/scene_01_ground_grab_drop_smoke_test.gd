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
	_expect_true(controller != null, "Ground test requires VehicleGrabDropController.")
	_expect_true(selection != null, "Ground test requires VehicleSelectionController.")
	_expect_true(vehicle_manager != null, "Ground test requires vehicle manager.")
	_expect_true(object_manager != null, "Ground test requires object manager.")
	if controller == null or selection == null or vehicle_manager == null or object_manager == null:
		await _finish_scene(scene)
		return

	var arm = vehicle_manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.ARM_VEHICLE_ID)
	_expect_true(arm != null and arm.runtime_state != null, "Ground test requires arm vehicle.")
	if arm == null or arm.runtime_state == null:
		await _finish_scene(scene)
		return
	_expect_true(selection.select_vehicle(arm), "Ground test should select arm.")
	_test_workspace_rotation_contract(controller, arm)

	var ground_field = object_manager.get_ground_block_field()
	_expect_true(object_manager.get_block_pile() != null and ground_field != null, "Ground test requires pile and ground field.")
	if ground_field == null:
		await _finish_scene(scene)
		return

	_place_vehicle(arm, Vector2i(1, 3), VEHICLE_RUNTIME_STATE_SCRIPT.Facing.WEST)
	var first_grab = controller.request_selected_grab_drop()
	_expect_equal(first_grab.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "Pile Grab should provide a block.")
	if not first_grab.is_success() or first_grab.item == null:
		await _finish_scene(scene)
		return
	var first_block = first_grab.item

	var ground_anchor := Vector2i(4, 2)
	var ground_cell := Vector2i(4, 1)
	_place_vehicle(arm, ground_anchor, VEHICLE_RUNTIME_STATE_SCRIPT.Facing.NORTH)
	controller.refresh_interaction_preview()
	_expect_equal(controller.get_forward_interaction_cells(arm), [ground_cell], "A 1x1 arm should expose one front workspace cell.")
	_expect_equal(controller.get_primary_ground_interaction_cell(arm), ground_cell, "The single workspace cell is the ground Drop target.")
	_expect_true(controller.is_interaction_preview_valid(), "Loaded arm should preview an empty legal ground cell as valid.")

	var first_drop = controller.request_selected_grab_drop()
	_expect_equal(first_drop.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "Drop to the single legal ground cell should succeed.")
	_expect_true(ground_field.get_item(ground_cell) == first_block, "Ground Drop should preserve exact block identity.")
	_expect_true(first_block.is_claimed_by(ground_field), "Ground field should own dropped block.")
	_expect_true(object_manager.get_ground_block_visual(ground_cell) != null, "Ground Drop should create StandardBlock visual.")

	controller.refresh_interaction_preview()
	_expect_true(controller.is_interaction_preview_valid(), "Empty arm should preview the occupied front cell as a valid Grab target.")
	var regrab = controller.request_selected_grab_drop()
	_expect_equal(regrab.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "Arm should Grab the block back from its single workspace cell.")
	_expect_true(regrab.item == first_block, "Ground round trip should preserve block identity.")
	_expect_false(ground_field.has_item(ground_cell), "Ground cell should empty after re-Grab.")

	var restore = controller.request_selected_grab_drop()
	_expect_equal(restore.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "Fixture should restore the first block to the ground cell.")
	_place_vehicle(arm, Vector2i(1, 3), VEHICLE_RUNTIME_STATE_SCRIPT.Facing.WEST)
	var second_grab = controller.request_selected_grab_drop()
	_expect_equal(second_grab.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "Pile should provide a second block.")
	if not second_grab.is_success() or second_grab.item == null:
		await _finish_scene(scene)
		return
	var second_block = second_grab.item

	_place_vehicle(arm, ground_anchor, VEHICLE_RUNTIME_STATE_SCRIPT.Facing.NORTH)
	controller.refresh_interaction_preview()
	_expect_false(controller.is_interaction_preview_valid(), "Occupied single workspace cell should reject another Drop.")
	var occupied_drop = controller.request_selected_grab_drop()
	_expect_equal(occupied_drop.status, GRAB_DROP_RESULT_SCRIPT.Status.NO_TARGET, "Single-cell workspace must not fall back to another cell.")
	_expect_true(ground_field.get_item(ground_cell) == first_block, "Rejected Drop must preserve existing ground block.")
	_expect_true(arm.runtime_state.carried_item == second_block, "Rejected Drop must preserve carried block.")

	_place_vehicle(arm, Vector2i(1, 3), VEHICLE_RUNTIME_STATE_SCRIPT.Facing.WEST)
	_expect_true(controller.resolve_target_for_vehicle(arm) == null, "Loaded arm facing the pile must not fall back to ground.")

	scene.call("reset_scene")
	await process_frame
	_expect_false(first_block.is_claimed(), "Reset should release ground block ownership.")
	_expect_false(second_block.is_claimed(), "Reset should release carried block ownership.")
	_expect_equal(ground_field.get_occupied_cells().size(), 0, "Reset should clear ground blocks.")
	_expect_true(object_manager.get_ground_block_visual(ground_cell) == null, "Reset should clear ground visual.")

	_expect_true(selection.select_vehicle(arm), "Arm should be selectable after Reset.")
	_place_vehicle(arm, ground_anchor, VEHICLE_RUNTIME_STATE_SCRIPT.Facing.NORTH)
	controller.refresh_interaction_preview()
	_expect_true(controller.is_interaction_preview_visible(), "Selected arm should show its single front workspace.")
	_expect_false(controller.is_interaction_preview_valid(), "Empty workspace with empty arm should preview invalid.")
	_expect_equal(controller.get_interaction_preview_cells(), [ground_cell], "Empty preview should remain one cell.")
	selection.cancel_selection()
	controller.refresh_interaction_preview()
	_expect_false(controller.is_interaction_preview_visible(), "Cancelling selection should hide interaction preview.")

	await _finish_scene(scene)


func _test_workspace_rotation_contract(controller, arm) -> void:
	var anchor := Vector2i(4, 3)
	var cases: Array[Dictionary] = [
		{"facing": VEHICLE_RUNTIME_STATE_SCRIPT.Facing.NORTH, "cell": Vector2i(4, 2), "name": "North"},
		{"facing": VEHICLE_RUNTIME_STATE_SCRIPT.Facing.EAST, "cell": Vector2i(5, 3), "name": "East"},
		{"facing": VEHICLE_RUNTIME_STATE_SCRIPT.Facing.SOUTH, "cell": Vector2i(4, 4), "name": "South"},
		{"facing": VEHICLE_RUNTIME_STATE_SCRIPT.Facing.WEST, "cell": Vector2i(3, 3), "name": "West"},
	]
	for workspace_case: Dictionary in cases:
		_place_vehicle(arm, anchor, int(workspace_case["facing"]))
		var cell: Vector2i = workspace_case["cell"]
		_expect_equal(
			controller.get_forward_interaction_cells(arm),
			[cell],
			"%s facing should expose one front workspace cell." % String(workspace_case["name"])
		)
		_expect_equal(
			controller.get_primary_ground_interaction_cell(arm),
			cell,
			"%s facing should use that cell as the ground target." % String(workspace_case["name"])
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

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
	_expect_true(status_label != null, "Ground test requires player StatusLabel feedback.")
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
	_test_workspace_rotation_contract(controller, arm)

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
		_expect_equal(status_label.text, "抓取成功", "Player feedback should report successful Grab in Chinese.")

	var ground_anchor := Vector2i(4, 2)
	var primary_cell := Vector2i(4, 1)
	var secondary_cell := Vector2i(5, 1)
	var workspace := [primary_cell, secondary_cell]
	_place_vehicle(arm, ground_anchor, VEHICLE_RUNTIME_STATE_SCRIPT.Facing.NORTH)
	_expect_equal(
		controller.get_forward_interaction_cells(arm),
		workspace,
		"North-facing 2x2 arm should expose both front workspace cells."
	)
	controller.refresh_interaction_preview()
	_expect_true(controller.is_interaction_preview_visible(), "Loaded arm should show ground interaction preview.")
	_expect_true(controller.is_interaction_preview_valid(), "Empty legal ground workspace should preview valid.")
	_expect_equal(controller.get_interaction_preview_cells(), workspace, "Ground preview should keep the full two-cell workspace.")

	var first_drop = controller.request_selected_grab_drop()
	_expect_equal(first_drop.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "Drop to legal ground workspace should succeed.")
	_expect_true(ground_field.get_item(primary_cell) == first_block, "First Drop should use deterministic primary workspace cell.")
	_expect_true(first_block.is_claimed_by(ground_field), "Ground field should own dropped block.")
	_expect_true(object_manager.get_ground_block_visual(primary_cell) != null, "Ground Drop should create StandardBlock visual.")
	if status_label != null:
		_expect_equal(status_label.text, "放置成功", "Player feedback should report successful Drop in Chinese.")

	controller.refresh_interaction_preview()
	_expect_true(controller.is_interaction_preview_valid(), "One occupied workspace cell should be a valid empty-arm Grab target.")
	_expect_equal(controller.get_interaction_preview_cells(), workspace, "Grab preview should still show both workspace cells.")
	var first_regrab = controller.request_selected_grab_drop()
	_expect_equal(first_regrab.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "Empty arm should Grab block back from either workspace cell.")
	_expect_true(first_regrab.item == first_block, "Ground round trip should preserve StandardBlock identity.")
	_expect_false(ground_field.has_item(primary_cell), "Primary ground cell should be empty after re-Grab.")

	var restore_primary = controller.request_selected_grab_drop()
	_expect_equal(restore_primary.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "First block should be dropped back to primary for fallback fixture.")

	_place_vehicle(arm, Vector2i(1, 3), VEHICLE_RUNTIME_STATE_SCRIPT.Facing.WEST)
	var second_grab = controller.request_selected_grab_drop()
	_expect_equal(second_grab.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "Pile should provide second block.")
	if not second_grab.is_success() or second_grab.item == null:
		await _finish_scene(scene)
		return
	var second_block = second_grab.item

	_place_vehicle(arm, ground_anchor, VEHICLE_RUNTIME_STATE_SCRIPT.Facing.NORTH)
	controller.refresh_interaction_preview()
	_expect_true(controller.is_interaction_preview_valid(), "Loaded arm should use the other workspace cell when primary is occupied.")
	_expect_equal(controller.get_interaction_preview_cells(), workspace, "Fallback Drop preview should still show the complete workspace.")
	var second_drop = controller.request_selected_grab_drop()
	_expect_equal(second_drop.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "Second Drop should fall back to the other front cell.")
	_expect_true(ground_field.get_item(primary_cell) == first_block, "Fallback Drop should preserve the first primary block.")
	_expect_true(ground_field.get_item(secondary_cell) == second_block, "Fallback Drop should place the second block in the other workspace cell.")

	controller.refresh_interaction_preview()
	_expect_false(controller.is_interaction_preview_valid(), "Two occupied front cells should be ambiguous for an empty-arm Grab.")
	_expect_equal(controller.get_interaction_preview_cells(), workspace, "Ambiguous preview should still identify the two-cell workspace.")
	var ambiguous_grab = controller.request_selected_grab_drop()
	_expect_equal(
		ambiguous_grab.status,
		GRAB_DROP_RESULT_SCRIPT.Status.NO_TARGET,
		"Two occupied ground cells should reject because the player did not choose one target."
	)
	_expect_false(arm.runtime_state.arm_has_item, "Ambiguous ground Grab should preserve empty arm state.")
	_expect_true(ground_field.get_item(primary_cell) == first_block, "Ambiguous Grab must preserve primary block.")
	_expect_true(ground_field.get_item(secondary_cell) == second_block, "Ambiguous Grab must preserve secondary block.")

	var cleared_primary = ground_field.take_item(primary_cell)
	_expect_true(cleared_primary.is_success(), "Fixture should be able to clear primary ground cell directly.")
	controller.refresh_interaction_preview()
	_expect_true(controller.is_interaction_preview_valid(), "A lone block in the secondary workspace cell should become a valid Grab target.")
	var secondary_regrab = controller.request_selected_grab_drop()
	_expect_equal(secondary_regrab.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "Arm should Grab from the non-primary front cell.")
	_expect_true(secondary_regrab.item == second_block, "Secondary-cell Grab should preserve block identity.")
	_expect_true(second_block.is_claimed_by(arm.runtime_state), "Secondary-cell Grab should transfer ownership to arm.")

	_place_vehicle(arm, Vector2i(1, 3), VEHICLE_RUNTIME_STATE_SCRIPT.Facing.WEST)
	_expect_true(
		controller.resolve_target_for_vehicle(arm) == null,
		"Loaded arm facing pile must not fall back to ground under static pile interaction cells."
	)

	scene.call("reset_scene")
	await process_frame
	_expect_false(first_block.is_claimed(), "Scene Reset should keep directly-cleared block unclaimed.")
	_expect_false(second_block.is_claimed(), "Scene Reset should release carried block ownership.")
	_expect_equal(ground_field.get_occupied_cells().size(), 0, "Scene Reset should clear all ground blocks.")
	_expect_true(object_manager.get_ground_block_visual(primary_cell) == null, "Scene Reset should clear primary ground visual.")
	_expect_true(object_manager.get_ground_block_visual(secondary_cell) == null, "Scene Reset should clear secondary ground visual.")

	_expect_true(selection.select_vehicle(arm), "Arm should be selectable after Reset.")
	_place_vehicle(arm, ground_anchor, VEHICLE_RUNTIME_STATE_SCRIPT.Facing.NORTH)
	controller.refresh_interaction_preview()
	_expect_true(controller.is_interaction_preview_visible(), "Empty arm should still show full forward workspace.")
	_expect_false(controller.is_interaction_preview_valid(), "Empty workspace with empty arm should preview invalid.")
	_expect_equal(controller.get_interaction_preview_cells(), workspace, "Empty workspace preview should keep both front cells.")
	selection.cancel_selection()
	controller.refresh_interaction_preview()
	_expect_false(controller.is_interaction_preview_visible(), "Cancelling selection should hide interaction preview.")

	await _finish_scene(scene)


func _test_workspace_rotation_contract(controller, arm) -> void:
	var anchor := Vector2i(4, 3)
	var cases: Array[Dictionary] = [
		{"facing": VEHICLE_RUNTIME_STATE_SCRIPT.Facing.NORTH, "cells": [Vector2i(4, 2), Vector2i(5, 2)], "primary": Vector2i(4, 2), "name": "North"},
		{"facing": VEHICLE_RUNTIME_STATE_SCRIPT.Facing.EAST, "cells": [Vector2i(6, 3), Vector2i(6, 4)], "primary": Vector2i(6, 3), "name": "East"},
		{"facing": VEHICLE_RUNTIME_STATE_SCRIPT.Facing.SOUTH, "cells": [Vector2i(4, 5), Vector2i(5, 5)], "primary": Vector2i(5, 5), "name": "South"},
		{"facing": VEHICLE_RUNTIME_STATE_SCRIPT.Facing.WEST, "cells": [Vector2i(3, 3), Vector2i(3, 4)], "primary": Vector2i(3, 4), "name": "West"},
	]
	for workspace_case: Dictionary in cases:
		_place_vehicle(arm, anchor, int(workspace_case["facing"]))
		_expect_equal(
			controller.get_forward_interaction_cells(arm),
			workspace_case["cells"],
			"%s facing should rotate the complete two-cell workspace." % String(workspace_case["name"])
		)
		_expect_equal(
			controller.get_primary_ground_interaction_cell(arm),
			workspace_case["primary"],
			"%s facing should preserve deterministic primary Drop priority." % String(workspace_case["name"])
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

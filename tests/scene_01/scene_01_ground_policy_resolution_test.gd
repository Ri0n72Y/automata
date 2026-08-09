extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const GRID_MODEL_SCRIPT := preload("res://scripts/grid/grid_model.gd")
const GRAB_DROP_CONTROLLER_SCRIPT := preload("res://scripts/input/vehicle_grab_drop_controller.gd")
const GRAB_DROP_RESULT_SCRIPT := preload("res://scripts/vehicles/grab_drop_result.gd")
const VEHICLE_MANAGER_SCRIPT := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const OBJECT_MANAGER_SCRIPT := preload("res://scripts/scene_01/scene_01_object_manager.gd")
const VEHICLE_RUNTIME_STATE_SCRIPT := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const STANDARD_BLOCK_SCRIPT := preload("res://scripts/objects/standard_block.gd")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for ground policy contract.")
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
	var vehicle_manager := scene.get_node_or_null(
		"SceneRoot/RobotRoot/Scene01VehicleManager"
	) as VEHICLE_MANAGER_SCRIPT
	var object_manager := scene.get_node_or_null(
		"SceneRoot/ObjectRoot/Scene01ObjectManager"
	) as OBJECT_MANAGER_SCRIPT
	_expect_true(controller != null, "Ground policy contract requires GrabDrop controller.")
	_expect_true(vehicle_manager != null, "Ground policy contract requires vehicle manager.")
	_expect_true(object_manager != null, "Ground policy contract requires object manager.")
	if controller == null or vehicle_manager == null or object_manager == null:
		await _finish_scene(scene)
		return

	_test_scene_adapter_legality(object_manager, vehicle_manager)
	_test_grid_policy_updates_immediately(scene, object_manager)
	_test_ground_and_tray_ambiguity(scene, controller, object_manager, vehicle_manager)

	await _finish_scene(scene)


func _test_scene_adapter_legality(object_manager, vehicle_manager) -> void:
	_expect_true(
		object_manager.get_ground_cell_interface(Vector2i(0, 3)) == null,
		"Static pile interaction cell must never be exposed as legal ground."
	)
	var transport = vehicle_manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.TRANSPORT_VEHICLE_ID)
	_expect_true(transport != null, "Ground legality fixture requires transport vehicle.")
	if transport == null or transport.runtime_state == null:
		return
	var occupied_cell: Vector2i = transport.runtime_state.anchor_cell
	_expect_true(
		object_manager.get_ground_cell_interface(occupied_cell) == null,
		"Vehicle-occupied cell must not be exposed as a ground interaction target."
	)
	_expect_true(
		object_manager.get_ground_cell_interface(Vector2i(4, 1)) != null,
		"Ordinary walkable unoccupied cell should remain a legal ground target."
	)


func _test_grid_policy_updates_immediately(scene, object_manager) -> void:
	var field = object_manager.get_ground_block_field()
	_expect_true(field != null and field.is_configured(), "Scene ground field should start configured.")
	if field == null:
		return
	var cell := Vector2i(4, 1)
	var interaction = object_manager.get_ground_cell_interface(cell)
	_expect_true(interaction != null, "Policy fixture requires a legal ground cell.")
	if interaction == null:
		return
	var block := STANDARD_BLOCK_SCRIPT.create()
	_expect_true(interaction.put_item(block).is_success(), "Policy fixture should place one real block.")
	_expect_true(field.get_item(cell) == block, "Ground field should own policy fixture block.")
	_expect_true(object_manager.get_ground_block_visual(cell) != null, "Policy fixture should create ground visual.")

	_expect_true(
		scene.call("set_grid_cell_type", cell, GRID_MODEL_SCRIPT.CellType.BOUNDARY),
		"Changing occupied ground cell to Boundary should succeed."
	)
	_expect_true(
		field.get_item(cell) == null,
		"Grid policy mutation must clear invalid ground state immediately without a getter refresh."
	)
	_expect_false(block.is_claimed(), "Grid policy mutation must immediately release block ownership.")
	_expect_true(
		object_manager.get_ground_block_visual(cell) == null,
		"Grid policy mutation must immediately remove the invalid ground visual."
	)
	_expect_true(
		scene.call("set_grid_cell_type", cell, GRID_MODEL_SCRIPT.CellType.NORMAL_TILE),
		"Ground policy fixture should restore the cell for subsequent tests."
	)
	_expect_true(
		object_manager.get_ground_cell_interface(cell) != null,
		"Restored walkable cell should become a legal ground target again."
	)


func _test_ground_and_tray_ambiguity(scene, controller, object_manager, vehicle_manager) -> void:
	scene.call("reset_scene")
	var arm = vehicle_manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.ARM_VEHICLE_ID)
	var transport = vehicle_manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.TRANSPORT_VEHICLE_ID)
	_expect_true(arm != null and transport != null, "Ambiguity fixture requires both vehicles.")
	if (
		arm == null
		or transport == null
		or arm.runtime_state == null
		or transport.runtime_state == null
		or transport.runtime_state.tray_state == null
	):
		return

	_place_vehicle(arm, Vector2i(4, 3), VEHICLE_RUNTIME_STATE_SCRIPT.Facing.EAST)
	_place_vehicle(transport, Vector2i(6, 4), VEHICLE_RUNTIME_STATE_SCRIPT.Facing.WEST)
	var ground_cell := Vector2i(6, 3)
	_expect_equal(
		controller.get_forward_interaction_cells(arm),
		[Vector2i(6, 3), Vector2i(6, 4)],
		"Ambiguity fixture should expose one ground cell and one tray cell on the same front edge."
	)
	_expect_equal(
		controller.get_primary_ground_interaction_cell(arm),
		ground_cell,
		"Ambiguity fixture should use the free front-left cell as ground socket."
	)
	var ground_interface = object_manager.get_ground_cell_interface(ground_cell)
	_expect_true(ground_interface != null, "Ambiguity fixture requires legal front-left ground.")
	if ground_interface == null:
		return
	var ground_block := STANDARD_BLOCK_SCRIPT.create()
	var tray_block := STANDARD_BLOCK_SCRIPT.create()
	_expect_true(ground_interface.put_item(ground_block).is_success(), "Ambiguity fixture should place ground block.")
	_expect_true(transport.runtime_state.tray_state.put_item(tray_block).is_success(), "Ambiguity fixture should load tray block.")
	_expect_true(
		controller.resolve_target_for_vehicle(arm) == null,
		"Ground and tray simultaneously matching the front edge must reject as ambiguous."
	)
	var selection = controller.vehicle_selection_controller
	_expect_true(selection != null and selection.select_vehicle(arm), "Ambiguity request should select the arm.")
	if selection == null:
		return
	var result = controller.request_selected_grab_drop()
	_expect_equal(
		result.status,
		GRAB_DROP_RESULT_SCRIPT.Status.NO_TARGET,
		"Ambiguous Grab must reject before consuming either source."
	)
	_expect_true(ground_block.is_claimed_by(object_manager.get_ground_block_field()), "Ambiguous rejection must preserve ground ownership.")
	_expect_true(tray_block.is_claimed_by(transport.runtime_state.tray_state), "Ambiguous rejection must preserve tray ownership.")
	_expect_false(arm.runtime_state.arm_has_item, "Ambiguous rejection must preserve empty arm state.")


func _place_vehicle(vehicle, anchor: Vector2i, facing: int) -> void:
	vehicle.runtime_state.anchor_cell = anchor
	vehicle.runtime_state.facing = facing
	vehicle.runtime_state.motion_state = VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.WAITING
	vehicle.sync_from_state()


func _finish_scene(scene: Node) -> void:
	scene.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	if failures == 0:
		print("Scene 01 ground policy and resolution tests passed.")
		quit(0)
		return
	push_error("Scene 01 ground policy and resolution tests failed: %d failure(s)." % failures)
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
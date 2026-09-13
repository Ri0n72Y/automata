extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const GRID_MODEL_SCRIPT := preload("res://scripts/grid/grid_model.gd")
const ITEM_TRANSFER_RESULT_SCRIPT := preload("res://scripts/objects/item_transfer_result.gd")
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

	var vehicle_manager := scene.get_node_or_null(
		"SceneRoot/RobotRoot/Scene01VehicleManager"
	) as VEHICLE_MANAGER_SCRIPT
	var object_manager := scene.get_node_or_null(
		"SceneRoot/ObjectRoot/Scene01ObjectManager"
	) as OBJECT_MANAGER_SCRIPT
	_expect_true(vehicle_manager != null, "Ground policy contract requires vehicle manager.")
	_expect_true(object_manager != null, "Ground policy contract requires object manager.")
	if vehicle_manager == null or object_manager == null:
		await _finish_scene(scene)
		return

	_test_scene_adapter_legality(object_manager, vehicle_manager)
	_test_cached_ground_interface_rechecks_dynamic_occupancy(object_manager, vehicle_manager)
	_test_grid_policy_updates_immediately(scene, object_manager)
	_test_runtime_grid_geometry_is_immutable(scene, object_manager)

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


func _test_cached_ground_interface_rechecks_dynamic_occupancy(object_manager, vehicle_manager) -> void:
	var transport = vehicle_manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.TRANSPORT_VEHICLE_ID)
	_expect_true(transport != null, "Cached-interface fixture requires transport vehicle.")
	if transport == null or transport.runtime_state == null:
		return
	var field = object_manager.get_ground_block_field()
	_expect_true(field != null, "Cached-interface fixture requires ground field.")
	if field == null:
		return
	var cell := Vector2i(4, 1)
	var cached_interface = object_manager.get_ground_cell_interface(cell)
	_expect_true(cached_interface != null, "Cached-interface fixture requires legal ground before vehicle arrival.")
	if cached_interface == null:
		return
	var block := STANDARD_BLOCK_SCRIPT.create()
	_expect_true(cached_interface.put_item(block).is_success(), "Cached-interface fixture should place a ground block.")
	var original_anchor: Vector2i = transport.runtime_state.anchor_cell
	var original_facing: int = transport.runtime_state.facing
	_place_vehicle(transport, cell, original_facing)

	_expect_false(
		cached_interface.can_take_item(),
		"Cached ground interface must become non-interactable after a vehicle occupies its cell."
	)
	_expect_equal(
		cached_interface.take_item().status,
		ITEM_TRANSFER_RESULT_SCRIPT.Status.INVALID_TARGET,
		"Cached ground interface must revalidate dynamic occupancy before take."
	)
	var rejected_block := STANDARD_BLOCK_SCRIPT.create()
	_expect_equal(
		field.put_item(cell, rejected_block).status,
		ITEM_TRANSFER_RESULT_SCRIPT.Status.INVALID_TARGET,
		"Raw GroundBlockField writes must also revalidate Scene dynamic occupancy."
	)
	_expect_false(rejected_block.is_claimed(), "Rejected raw Field write must not claim the block.")
	_expect_true(field.get_item(cell) == block, "Dynamic occupancy rejection must preserve existing ground ownership.")

	_place_vehicle(transport, original_anchor, original_facing)
	_expect_true(cached_interface.can_take_item(), "Cached ground interface should recover after vehicle leaves.")
	var recovered_take = cached_interface.take_item()
	_expect_true(
		recovered_take.is_success() and recovered_take.item == block,
		"Recovered cached interface should return the exact original ground block."
	)
	_expect_false(block.is_claimed(), "Recovered take should release ground ownership.")


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
		bool(scene.call("set_grid_cell_type", cell, GRID_MODEL_SCRIPT.CellType.BOUNDARY)),
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
		bool(scene.call("set_grid_cell_type", cell, GRID_MODEL_SCRIPT.CellType.NORMAL_TILE)),
		"Ground policy fixture should restore the cell for subsequent tests."
	)
	_expect_true(
		object_manager.get_ground_cell_interface(cell) != null,
		"Restored walkable cell should become a legal ground target again."
	)


func _test_runtime_grid_geometry_is_immutable(scene, object_manager) -> void:
	var field = object_manager.get_ground_block_field()
	if field == null:
		_expect_true(false, "Runtime geometry fixture requires ground field.")
		return
	var cell := Vector2i(4, 1)
	var interaction = object_manager.get_ground_cell_interface(cell)
	_expect_true(interaction != null, "Runtime geometry fixture requires legal ground cell.")
	if interaction == null:
		return
	var block := STANDARD_BLOCK_SCRIPT.create()
	_expect_true(interaction.put_item(block).is_success(), "Runtime geometry fixture should place one ground block.")
	var visual: Node3D = object_manager.get_ground_block_visual(cell) as Node3D
	_expect_true(visual != null, "Runtime geometry fixture should create an existing static block visual instance.")
	if visual == null:
		return

	var previous_model := scene.get("grid_model") as GRID_MODEL_SCRIPT
	_expect_true(previous_model != null, "Runtime geometry fixture requires current GridModel.")
	if previous_model == null:
		return
	var previous_visual_position: Vector3 = visual.position
	var previous_cell_size: float = previous_model.cell_size
	var previous_origin: Vector3 = previous_model.local_origin
	scene.set("grid_cell_size", previous_cell_size + 0.5)
	scene.set("grid_local_origin", previous_origin + Vector3(0.25, 0.0, -0.25))
	var initialized := bool(_call_with_expected_errors_suppressed(Callable(scene, "initialize_grid")))
	_expect_false(
		initialized,
		"Scene01 should reject runtime grid geometry changes because static scene objects are authored for fixed geometry."
	)
	_expect_true(scene.get("grid_model") == previous_model, "Rejected geometry rebuild must preserve GridModel identity.")
	_expect_equal(scene.get("grid_cell_size"), previous_cell_size, "Rejected geometry rebuild must restore exported cell size.")
	_expect_equal(scene.get("grid_local_origin"), previous_origin, "Rejected geometry rebuild must restore exported local origin.")
	_expect_true(field.get_item(cell) == block, "Rejected geometry rebuild must preserve ground block identity.")
	_expect_true(block.is_claimed_by(field), "Rejected geometry rebuild must preserve ground ownership.")
	_expect_true(object_manager.get_ground_block_visual(cell) == visual, "Rejected geometry rebuild must preserve visual identity.")
	_expect_true(visual.position.is_equal_approx(previous_visual_position), "Rejected geometry rebuild must preserve visual position.")
	field.reset()


func _call_with_expected_errors_suppressed(callback: Callable) -> Variant:
	var previous_print_error_messages := Engine.print_error_messages
	Engine.print_error_messages = false
	var result: Variant = callback.call()
	Engine.print_error_messages = previous_print_error_messages
	return result


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

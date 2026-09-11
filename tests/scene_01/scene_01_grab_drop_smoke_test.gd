extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const GrabDropControllerScript := preload("res://scripts/input/vehicle_grab_drop_controller.gd")
const MoveControllerScript := preload("res://scripts/input/vehicle_move_controller.gd")
const SelectionScript := preload("res://scripts/input/vehicle_selection_controller.gd")
const ManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const ObjectManagerScript := preload("res://scripts/scene_01/scene_01_object_manager.gd")
const RuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const MoveCommandScript := preload("res://scripts/vehicles/move_command.gd")
const GrabDropResultScript := preload("res://scripts/vehicles/grab_drop_result.gd")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_input_map()
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for GrabDrop integration.")
	if packed == null:
		_finish()
		return

	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame

	var controller := scene.get_node_or_null("SceneRoot/GridRoot/VehicleGrabDropController") as GrabDropControllerScript
	var move_controller := scene.get_node_or_null("SceneRoot/GridRoot/VehicleMoveController") as MoveControllerScript
	var selection := scene.get_node_or_null("SceneRoot/GridRoot/VehicleSelectionController") as SelectionScript
	var manager := scene.get_node_or_null("SceneRoot/RobotRoot/Scene01VehicleManager") as ManagerScript
	var objects := scene.get_node_or_null("SceneRoot/ObjectRoot/Scene01ObjectManager") as ObjectManagerScript
	_expect_true(
		controller != null and move_controller != null and selection != null
		and manager != null and objects != null,
		"Scene exposes GrabDrop integration dependencies."
	)
	if controller == null or move_controller == null or selection == null or manager == null or objects == null:
		await _cleanup(scene)
		_finish()
		return

	var arm = manager.get_vehicle_by_id(ManagerScript.ARM_VEHICLE_ID)
	var transport = manager.get_vehicle_by_id(ManagerScript.TRANSPORT_VEHICLE_ID)
	_expect_true(arm != null and transport != null, "GrabDrop integration has both vehicles.")
	if arm == null or transport == null:
		await _cleanup(scene)
		_finish()
		return

	_expect_true(selection.select_vehicle(arm), "Arm can be selected.")
	_test_rotation(controller, selection, arm, transport)
	_test_interface_registry(objects, transport)
	_test_pile_tray_box(controller, selection, arm, transport, objects)
	_test_busy_rejection(controller, arm)
	_test_collision_preserves_cargo(controller, move_controller, selection, arm, transport)
	await _test_reset(scene, controller, arm, transport, objects)

	await _cleanup(scene)
	_finish()


func _test_input_map() -> void:
	_expect_action_key(GrabDropControllerScript.GRAB_DROP_ACTION, KEY_C, "GrabDrop defaults to C.")
	_expect_action_key(GrabDropControllerScript.ROTATE_COUNTERCLOCKWISE_ACTION, KEY_A, "Arm CCW defaults to A.")
	_expect_action_key(GrabDropControllerScript.ROTATE_CLOCKWISE_ACTION, KEY_D, "Arm CW defaults to D.")


func _test_rotation(controller, selection, arm, transport) -> void:
	arm.reset_actor()
	var original: int = arm.runtime_state.facing
	_expect_true(controller.rotate_selected_arm(-1), "Waiting arm rotates counterclockwise.")
	_expect_equal(arm.runtime_state.facing, posmod(original - 1, 4), "CCW updates facing.")
	_expect_true(controller.rotate_selected_arm(1), "Waiting arm rotates clockwise.")
	_expect_equal(arm.runtime_state.facing, original, "Opposite rotations restore facing.")

	_expect_true(selection.select_vehicle(transport), "Transport can be selected.")
	var transport_facing: int = transport.runtime_state.facing
	_expect_false(controller.rotate_selected_arm(1), "Transport rejects arm rotation.")
	_expect_equal(transport.runtime_state.facing, transport_facing, "Rejected rotation preserves transport facing.")
	_expect_true(selection.select_vehicle(arm), "Arm selection restored.")


func _test_interface_registry(objects, transport) -> void:
	var object_interfaces: Array[Variant] = objects.get_item_interaction_interfaces()
	_expect_true(object_interfaces.has(objects.get_block_pile_source()), "Object registry exposes pile source.")
	_expect_true(object_interfaces.has(objects.get_standard_box_receiver()), "Object registry exposes box receiver.")
	var vehicle_interfaces: Array[Variant] = transport.runtime_state.get_item_interaction_interfaces(
		transport.get_occupied_cells()
	)
	_expect_true(vehicle_interfaces.has(transport.runtime_state.tray_state), "Waiting transport exposes tray interface.")


func _test_pile_tray_box(controller, selection, arm, transport, objects) -> void:
	var box = objects.get_standard_box()
	var initial_box_count: int = box.get_current_count()

	_place_vehicle(arm, Vector2i(1, 3), RuntimeStateScript.Facing.WEST)
	var grab = controller.request_selected_grab_drop()
	_expect_true(grab != null and grab.status == GrabDropResultScript.Status.ACCEPTED, "Arm grabs from infinite pile.")
	if grab == null or not grab.is_success() or grab.item == null:
		return
	var block = grab.item
	_expect_true(arm.runtime_state.carried_item == block, "Arm carries the exact pile block.")
	_expect_true(block.is_claimed_by(arm.runtime_state), "Arm owns the carried block.")

	_place_vehicle(arm, Vector2i(5, 4), RuntimeStateScript.Facing.EAST)
	var drop_to_tray = controller.request_selected_grab_drop()
	_expect_true(drop_to_tray != null and drop_to_tray.is_success(), "Arm drops into tray.")
	_expect_equal(transport.runtime_state.tray_count, 1, "Tray becomes 1/8.")
	_expect_true(block.is_claimed_by(transport.runtime_state.tray_state), "Tray owns transferred block.")

	var regrab = controller.request_selected_grab_drop()
	_expect_true(regrab != null and regrab.is_success(), "Arm re-grabs from tray.")
	_expect_equal(transport.runtime_state.tray_count, 0, "Tray returns to 0/8.")
	_expect_true(arm.runtime_state.carried_item == block, "Tray roundtrip preserves block identity.")

	_place_vehicle(arm, Vector2i(13, 3), RuntimeStateScript.Facing.EAST)
	var drop_to_box = controller.request_selected_grab_drop()
	_expect_true(drop_to_box != null and drop_to_box.is_success(), "Arm drops into StandardBox.")
	_expect_equal(box.get_current_count(), initial_box_count + 1, "Box increments exactly once.")
	_expect_true(box.contains_item(block), "Box owns the exact block.")
	_expect_false(arm.runtime_state.arm_has_item, "Arm empties after Box Drop.")

	selection.cancel_selection()
	_expect_true(box.contains_item(block), "Selection changes do not alter box ownership.")
	_expect_true(selection.select_vehicle(arm), "Arm can be selected again.")


func _test_busy_rejection(controller, arm) -> void:
	_place_vehicle(arm, Vector2i(1, 3), RuntimeStateScript.Facing.WEST)
	_expect_true(arm.runtime_state.begin_move_planning(), "Busy fixture enters Planning.")
	var busy = controller.request_selected_grab_drop()
	_expect_true(busy != null and busy.status == GrabDropResultScript.Status.BUSY, "Planning arm rejects GrabDrop as BUSY.")
	_expect_false(arm.runtime_state.arm_has_item, "Busy rejection leaves arm empty.")
	arm.runtime_state.clear_move_command()
	arm.sync_from_state()


func _test_collision_preserves_cargo(controller, move_controller, selection, arm, transport) -> void:
	arm.reset_actor()
	transport.reset_actor()
	_expect_true(selection.select_vehicle(arm), "Collision fixture selects arm.")
	_place_vehicle(arm, Vector2i(1, 3), RuntimeStateScript.Facing.WEST)
	var grab = controller.request_selected_grab_drop()
	if grab == null or not grab.is_success() or grab.item == null:
		_expect_true(false, "Collision fixture needs carried block.")
		return
	var carried = grab.item

	_place_vehicle(arm, Vector2i(3, 3), RuntimeStateScript.Facing.EAST)
	_place_vehicle(transport, Vector2i(6, 3), RuntimeStateScript.Facing.WEST)
	var arm_move := _move_command(Vector2i(4, 3), [Vector2i(3, 3), Vector2i(4, 3)])
	var transport_move := _move_command(Vector2i(5, 3), [Vector2i(6, 3), Vector2i(5, 3)])
	if arm_move == null or transport_move == null:
		return
	_expect_true(arm.start_move(arm_move), "Carrying arm collision task starts.")
	_expect_true(transport.start_move(transport_move), "Transport collision task starts.")
	move_controller._physics_process(1.0)
	_expect_equal(arm.runtime_state.motion_state, RuntimeStateScript.MotionState.BLOCKED, "Collision blocks carrying arm.")
	_expect_true(arm.runtime_state.carried_item == carried, "Collision preserves carried block identity.")
	_expect_true(carried.is_claimed_by(arm.runtime_state), "Collision preserves arm ownership.")
	arm.reset_actor()
	transport.reset_actor()
	_expect_true(selection.select_vehicle(arm), "Arm remains usable after collision cleanup.")


func _test_reset(scene, controller, arm, transport, objects) -> void:
	var box = objects.get_standard_box()
	_place_vehicle(arm, Vector2i(1, 3), RuntimeStateScript.Facing.WEST)
	var arm_grab = controller.request_selected_grab_drop()
	if arm_grab == null or not arm_grab.is_success() or arm_grab.item == null:
		_expect_true(false, "Reset fixture needs arm cargo.")
		return
	var arm_block = arm_grab.item
	var tray_block_result = objects.get_block_pile().take_item()
	if not tray_block_result.is_success() or tray_block_result.item == null:
		_expect_true(false, "Reset fixture needs tray cargo.")
		return
	var tray_block = tray_block_result.item
	_expect_true(transport.runtime_state.tray_state.put_item(tray_block).is_success(), "Reset fixture loads tray.")

	_expect_true(bool(scene.call("reset_scene")), "Scene Reset succeeds.")
	await process_frame
	_expect_false(arm.runtime_state.arm_has_item, "Reset clears arm cargo.")
	_expect_false(arm_block.is_claimed(), "Reset releases former arm cargo.")
	_expect_equal(transport.runtime_state.tray_count, 0, "Reset clears tray inventory.")
	_expect_false(tray_block.is_claimed(), "Reset releases former tray cargo.")
	_expect_equal(box.get_current_count(), 3, "Reset restores StandardBox 3/8.")


func _move_command(target: Vector2i, path: Array[Vector2i]) -> MoveCommandScript:
	var command := MoveCommandScript.new()
	if not command.configure(target, path):
		_expect_true(false, "Collision MoveCommand configures.")
		return null
	return command


func _place_vehicle(vehicle, anchor: Vector2i, facing: int) -> void:
	vehicle.runtime_state.anchor_cell = anchor
	vehicle.runtime_state.facing = facing
	vehicle.sync_from_state()


func _expect_action_key(action: StringName, keycode: int, message: String) -> void:
	_expect_true(InputMap.has_action(action), "%s action exists." % String(action))
	if not InputMap.has_action(action):
		return
	for input_event in InputMap.action_get_events(action):
		var key_event := input_event as InputEventKey
		if key_event != null and key_event.keycode == keycode:
			return
	_expect_true(false, message)


func _cleanup(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
		await process_frame


func _finish() -> void:
	if failures == 0:
		print("Scene 01 GrabDrop smoke tests passed.")
		quit(0)
		return
	push_error("Scene 01 GrabDrop smoke tests failed: %d failure(s)." % failures)
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

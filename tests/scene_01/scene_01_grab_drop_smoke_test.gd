extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const GRAB_DROP_CONTROLLER_SCRIPT := preload("res://scripts/input/vehicle_grab_drop_controller.gd")
const MOVE_CONTROLLER_SCRIPT := preload("res://scripts/input/vehicle_move_controller.gd")
const VEHICLE_SELECTION_SCRIPT := preload("res://scripts/input/vehicle_selection_controller.gd")
const VEHICLE_MANAGER_SCRIPT := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const OBJECT_MANAGER_SCRIPT := preload("res://scripts/scene_01/scene_01_object_manager.gd")
const VEHICLE_RUNTIME_STATE_SCRIPT := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const MOVE_COMMAND_SCRIPT := preload("res://scripts/vehicles/move_command.gd")
const GRAB_DROP_RESULT_SCRIPT := preload("res://scripts/vehicles/grab_drop_result.gd")
const VEHICLE_STATE_VISUAL_SCRIPT := preload("res://scripts/vehicles/vehicle_state_visual.gd")

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

	var controller := scene.get_node_or_null(
		"SceneRoot/GridRoot/VehicleGrabDropController"
	) as GRAB_DROP_CONTROLLER_SCRIPT
	var move_controller := scene.get_node_or_null(
		"SceneRoot/GridRoot/VehicleMoveController"
	) as MOVE_CONTROLLER_SCRIPT
	var selection := scene.get_node_or_null(
		"SceneRoot/GridRoot/VehicleSelectionController"
	) as VEHICLE_SELECTION_SCRIPT
	var vehicle_manager := scene.get_node_or_null(
		"SceneRoot/RobotRoot/Scene01VehicleManager"
	) as VEHICLE_MANAGER_SCRIPT
	var object_manager := scene.get_node_or_null(
		"SceneRoot/ObjectRoot/Scene01ObjectManager"
	) as OBJECT_MANAGER_SCRIPT
	_expect_true(controller != null, "Scene 01 should contain VehicleGrabDropController.")
	_expect_true(move_controller != null, "Scene 01 should contain VehicleMoveController.")
	_expect_true(selection != null, "Scene 01 should contain VehicleSelectionController.")
	_expect_true(vehicle_manager != null, "Scene 01 should contain Scene01VehicleManager.")
	_expect_true(object_manager != null, "Scene 01 should contain Scene01ObjectManager.")
	if (
		controller == null
		or move_controller == null
		or selection == null
		or vehicle_manager == null
		or object_manager == null
	):
		scene.queue_free()
		await process_frame
		_finish()
		return

	var arm = vehicle_manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.ARM_VEHICLE_ID)
	var transport = vehicle_manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.TRANSPORT_VEHICLE_ID)
	_expect_true(arm != null and transport != null, "GrabDrop integration requires both vehicles.")
	if arm == null or transport == null or arm.runtime_state == null or transport.runtime_state == null:
		scene.queue_free()
		await process_frame
		_finish()
		return

	_expect_true(selection.select_vehicle(arm), "Arm should be selectable for GrabDrop.")
	_test_rotation_contract(controller, selection, arm, transport)
	_test_interface_registry_contract(object_manager, transport)
	_test_pile_tray_box_flow(controller, selection, arm, transport, object_manager)
	_test_busy_boundary(controller, arm, object_manager)
	_test_collision_block_preserves_cargo(
		controller,
		move_controller,
		selection,
		arm,
		transport,
		object_manager
	)
	await _test_reset_contract(scene, controller, arm, transport, object_manager)

	scene.queue_free()
	await process_frame
	_finish()


func _test_input_map() -> void:
	_expect_action_key(GRAB_DROP_CONTROLLER_SCRIPT.GRAB_DROP_ACTION, KEY_C, "GrabDrop should default to C.")
	_expect_action_key(
		GRAB_DROP_CONTROLLER_SCRIPT.ROTATE_COUNTERCLOCKWISE_ACTION,
		KEY_A,
		"Arm counterclockwise rotation should default to A."
	)
	_expect_action_key(
		GRAB_DROP_CONTROLLER_SCRIPT.ROTATE_CLOCKWISE_ACTION,
		KEY_D,
		"Arm clockwise rotation should default to D."
	)


func _test_rotation_contract(controller, selection, arm, transport) -> void:
	arm.reset_actor()
	var original_facing: int = arm.runtime_state.facing
	_expect_true(controller.rotate_selected_arm(-1), "Selected Waiting arm should rotate counterclockwise.")
	_expect_equal(
		arm.runtime_state.facing,
		posmod(original_facing - 1, 4),
		"Counterclockwise rotation should update logical facing."
	)
	_expect_true(controller.rotate_selected_arm(1), "Selected Waiting arm should rotate clockwise.")
	_expect_equal(arm.runtime_state.facing, original_facing, "Opposite rotations should restore facing.")

	_expect_true(arm.runtime_state.begin_move_planning(), "Rotation busy fixture should enter Planning.")
	_expect_false(controller.rotate_selected_arm(1), "Planning arm must reject facing changes.")
	_expect_equal(arm.runtime_state.facing, original_facing, "Rejected rotation should preserve facing.")
	arm.runtime_state.clear_move_command()
	arm.sync_from_state()

	_expect_true(selection.select_vehicle(transport), "Transport should be selectable for capability boundary.")
	var transport_facing: int = transport.runtime_state.facing
	_expect_false(controller.rotate_selected_arm(1), "Transport should reject arm-facing rotation.")
	_expect_equal(transport.runtime_state.facing, transport_facing, "Rejected transport rotation preserves facing.")
	_expect_true(selection.select_vehicle(arm), "Arm selection should be restored after capability boundary.")


func _test_interface_registry_contract(object_manager, transport) -> void:
	var object_interfaces: Array[Variant] = object_manager.get_item_interaction_interfaces()
	_expect_true(
		object_interfaces.has(object_manager.get_block_pile_source()),
		"Object manager interaction registry should expose pile Source interface."
	)
	_expect_true(
		object_interfaces.has(object_manager.get_standard_box_receiver()),
		"Object manager interaction registry should expose box Receiver interface."
	)
	var vehicle_interfaces: Array[Variant] = transport.runtime_state.get_item_interaction_interfaces(
		transport.get_occupied_cells()
	)
	_expect_true(
		vehicle_interfaces.has(transport.runtime_state.tray_state),
		"Vehicle runtime interaction registry should expose tray interface without vehicle-id lookup."
	)
	_expect_equal(
		transport.runtime_state.tray_state.get_interaction_cells(),
		transport.get_occupied_cells(),
		"Tray interaction cells should follow current vehicle occupancy."
	)


func _test_pile_tray_box_flow(controller, selection, arm, transport, object_manager) -> void:
	var pile = object_manager.get_block_pile()
	var box = object_manager.get_standard_box()
	_expect_true(pile != null and box != null, "GrabDrop flow requires pile and box domains.")
	if pile == null or box == null:
		return
	var initial_box_count: int = box.get_current_count()

	_place_vehicle(arm, Vector2i(1, 3), VEHICLE_RUNTIME_STATE_SCRIPT.Facing.WEST)
	_expect_equal(
		controller.get_forward_interaction_cells(arm),
		[Vector2i(0, 3), Vector2i(0, 4)],
		"West-facing 2x2 arm should expose the pile interaction edge."
	)
	_expect_true(
		controller.resolve_target_for_vehicle(arm) == object_manager.get_block_pile_source(),
		"Pile interaction edge should resolve the Source interface."
	)
	var grab_from_pile = controller.request_selected_grab_drop()
	_expect_equal(
		grab_from_pile.status,
		GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED,
		"C-equivalent request should grab from infinite pile."
	)
	if not grab_from_pile.is_success() or grab_from_pile.item == null:
		_expect_true(false, "Pile grab must return a real StandardBlock.")
		return
	var block = grab_from_pile.item
	var block_id: int = block.get_block_id()
	_expect_true(arm.runtime_state.carried_item == block, "Arm should carry the exact pile block.")
	_expect_true(block.is_claimed_by(arm.runtime_state), "Pile block should be owned by arm runtime.")
	_expect_equal(pile.get_produced_count(), 1, "Pile should produce exactly one block.")

	selection.cancel_selection()
	_expect_true(arm.runtime_state.carried_item == block, "Cancelling selection must preserve carried block identity.")
	_expect_true(block.is_claimed_by(arm.runtime_state), "Cancelling selection must preserve arm ownership.")
	_expect_true(selection.select_vehicle(arm), "Arm should be reselectable after cancellation.")

	var arm_visual := arm.get_node_or_null("VisualRoot") as VEHICLE_STATE_VISUAL_SCRIPT
	_expect_true(arm_visual != null, "Arm should expose existing carry visual presenter.")
	if arm_visual != null:
		arm_visual.refresh_visual(true)
		_expect_true(arm_visual.is_carry_warning_visible(), "Real carried block should show yellow carry warning.")

	_place_vehicle(arm, Vector2i(5, 4), VEHICLE_RUNTIME_STATE_SCRIPT.Facing.EAST)
	_expect_true(
		controller.resolve_target_for_vehicle(arm) == transport.runtime_state.tray_state,
		"Arm front edge should resolve the tray through generic interaction interfaces."
	)
	var drop_to_tray = controller.request_selected_grab_drop()
	_expect_equal(drop_to_tray.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "Arm should drop into tray.")
	if not drop_to_tray.is_success() or drop_to_tray.item == null:
		_expect_true(false, "Tray drop must expose transferred block.")
		return
	_expect_false(arm.runtime_state.arm_has_item, "Tray drop should empty arm.")
	_expect_equal(transport.runtime_state.tray_count, 1, "Tray drop should create 1/8 real inventory.")
	_expect_equal(drop_to_tray.item.get_block_id(), block_id, "Tray drop should preserve block identity.")
	_expect_true(drop_to_tray.item.is_claimed_by(transport.runtime_state.tray_state), "Tray should own dropped block.")
	var transport_visual := transport.get_node_or_null("VisualRoot") as VEHICLE_STATE_VISUAL_SCRIPT
	_expect_true(transport_visual != null, "Transport should expose existing tray visual presenter.")
	if transport_visual != null:
		transport_visual.refresh_visual(true)
		_expect_equal(transport_visual.get_visible_tray_slot_count(), 1, "Real tray inventory should show one slot.")
		_expect_equal(transport_visual.get_tray_count_label_text(), "1/8", "Real tray label should show 1/8.")

	var regrab_from_tray = controller.request_selected_grab_drop()
	_expect_equal(regrab_from_tray.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "Empty arm should re-grab from tray.")
	if not regrab_from_tray.is_success() or regrab_from_tray.item == null:
		_expect_true(false, "Tray re-grab must expose transferred block.")
		return
	_expect_equal(transport.runtime_state.tray_count, 0, "Tray re-grab should restore 0/8.")
	_expect_equal(regrab_from_tray.item.get_block_id(), block_id, "Tray re-grab should preserve block identity.")
	_expect_true(regrab_from_tray.item.is_claimed_by(arm.runtime_state), "Re-grabbed block should return to arm ownership.")

	_place_vehicle(arm, Vector2i(9, 3), VEHICLE_RUNTIME_STATE_SCRIPT.Facing.EAST)
	_expect_equal(
		controller.get_forward_interaction_cells(arm),
		[Vector2i(11, 3), Vector2i(11, 4)],
		"East-facing 2x2 arm should expose the box interaction edge."
	)
	_expect_true(
		controller.resolve_target_for_vehicle(arm) == object_manager.get_standard_box_receiver(),
		"Loaded arm should resolve box Receiver interface as a Drop target."
	)
	var drop_to_box = controller.request_selected_grab_drop()
	_expect_equal(drop_to_box.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "Arm should drop into standard box.")
	if not drop_to_box.is_success() or drop_to_box.item == null:
		_expect_true(false, "Box drop must expose transferred block.")
		return
	_expect_equal(box.get_current_count(), initial_box_count + 1, "Box count should increment after real Drop.")
	_expect_equal(drop_to_box.item.get_block_id(), block_id, "Box Drop should preserve block identity.")
	_expect_true(box.contains_item(drop_to_box.item), "StandardBox should own the exact dropped block.")
	_expect_false(arm.runtime_state.arm_has_item, "Successful box Drop should empty arm.")

	var box_count_after_drop: int = box.get_current_count()
	_expect_true(
		controller.resolve_target_for_vehicle(arm) == null,
		"Empty arm must not resolve StandardBox as a Grab source."
	)
	var rejected_box_grab = controller.request_selected_grab_drop()
	_expect_equal(
		rejected_box_grab.status,
		GRAB_DROP_RESULT_SCRIPT.Status.NO_TARGET,
		"Empty arm facing box should report no compatible Grab target."
	)
	_expect_equal(box.get_current_count(), box_count_after_drop, "Rejected box Grab must preserve box count.")


func _test_busy_boundary(controller, arm, object_manager) -> void:
	var pile = object_manager.get_block_pile()
	if pile == null:
		return
	_place_vehicle(arm, Vector2i(1, 3), VEHICLE_RUNTIME_STATE_SCRIPT.Facing.WEST)
	var produced_before: int = pile.get_produced_count()
	_expect_true(arm.runtime_state.begin_move_planning(), "Busy GrabDrop fixture should enter Planning.")
	var busy = controller.request_selected_grab_drop()
	_expect_equal(busy.status, GRAB_DROP_RESULT_SCRIPT.Status.BUSY, "Planning arm should reject GrabDrop.")
	_expect_equal(pile.get_produced_count(), produced_before, "Busy rejection should not consume pile.")
	_expect_false(arm.runtime_state.arm_has_item, "Busy rejection should preserve empty arm.")
	arm.runtime_state.clear_move_command()
	arm.sync_from_state()


func _test_collision_block_preserves_cargo(
	controller,
	move_controller,
	selection,
	arm,
	transport,
	object_manager
) -> void:
	arm.reset_actor()
	transport.reset_actor()
	_expect_true(selection.select_vehicle(arm), "Collision cargo fixture should select arm.")
	_place_vehicle(arm, Vector2i(1, 3), VEHICLE_RUNTIME_STATE_SCRIPT.Facing.WEST)
	var pile = object_manager.get_block_pile()
	if pile == null:
		_expect_true(false, "Collision cargo fixture requires pile.")
		return
	var grab = controller.request_selected_grab_drop()
	if not grab.is_success() or grab.item == null:
		_expect_true(false, "Collision cargo fixture requires a real carried block.")
		return
	var carried = grab.item

	_place_vehicle(arm, Vector2i(3, 3), VEHICLE_RUNTIME_STATE_SCRIPT.Facing.EAST)
	_place_vehicle(transport, Vector2i(6, 3), VEHICLE_RUNTIME_STATE_SCRIPT.Facing.WEST)
	var arm_move := _move_command(Vector2i(4, 3), [Vector2i(3, 3), Vector2i(4, 3)])
	var transport_move := _move_command(Vector2i(5, 3), [Vector2i(6, 3), Vector2i(5, 3)])
	if arm_move == null or transport_move == null:
		return
	_expect_true(arm.start_move(arm_move), "Carrying arm collision task should start.")
	_expect_true(transport.start_move(transport_move), "Transport collision task should start.")
	move_controller._physics_process(1.0)

	_expect_equal(
		arm.runtime_state.motion_state,
		VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.BLOCKED,
		"Carrying arm should become Blocked on continuous collision."
	)
	_expect_true(arm.runtime_state.carried_item == carried, "Collision Blocked must preserve carried block identity.")
	_expect_true(carried.is_claimed_by(arm.runtime_state), "Collision Blocked must preserve arm ownership.")
	arm.reset_actor()
	transport.reset_actor()
	_expect_true(selection.select_vehicle(arm), "Arm should remain usable after collision fixture cleanup.")


func _test_reset_contract(scene, controller, arm, transport, object_manager) -> void:
	var pile = object_manager.get_block_pile()
	var box = object_manager.get_standard_box()
	if pile == null or box == null:
		return
	_place_vehicle(arm, Vector2i(1, 3), VEHICLE_RUNTIME_STATE_SCRIPT.Facing.WEST)
	var arm_grab = controller.request_selected_grab_drop()
	if not arm_grab.is_success() or arm_grab.item == null:
		_expect_true(false, "Reset fixture requires real arm cargo.")
		return
	var arm_block = arm_grab.item
	var tray_block_result = pile.take_item()
	if not tray_block_result.is_success() or tray_block_result.item == null:
		_expect_true(false, "Reset fixture requires real tray cargo.")
		return
	var tray_block = tray_block_result.item
	_expect_true(
		transport.runtime_state.tray_state.put_item(tray_block).is_success(),
		"Reset fixture should place a real block in tray."
	)
	_expect_equal(transport.runtime_state.tray_count, 1, "Reset fixture tray should reach 1/8.")

	scene.call("reset_scene")
	await process_frame
	_expect_false(arm.runtime_state.arm_has_item, "Scene Reset should clear arm real cargo.")
	_expect_true(arm.runtime_state.carried_item == null, "Scene Reset should clear carried item reference.")
	_expect_false(arm_block.is_claimed(), "Scene Reset should release former arm cargo ownership.")
	_expect_equal(transport.runtime_state.tray_count, 0, "Scene Reset should clear real tray inventory.")
	_expect_false(tray_block.is_claimed(), "Scene Reset should release former tray cargo ownership.")
	_expect_equal(box.get_current_count(), 3, "Scene Reset should restore StandardBox to 3/8.")
	_expect_equal(pile.get_produced_count(), 0, "Scene Reset should restore pile production statistic.")


func _move_command(target: Vector2i, path: Array[Vector2i]) -> MOVE_COMMAND_SCRIPT:
	var command := MOVE_COMMAND_SCRIPT.new()
	if not command.configure(target, path):
		_expect_true(false, "Collision fixture MoveCommand should configure.")
		return null
	return command


func _place_vehicle(vehicle, anchor: Vector2i, facing: int) -> void:
	vehicle.runtime_state.anchor_cell = anchor
	vehicle.runtime_state.facing = facing
	vehicle.sync_from_state()


func _expect_action_key(action: StringName, keycode: int, message: String) -> void:
	_expect_true(InputMap.has_action(action), "%s Input action must exist." % String(action))
	if not InputMap.has_action(action):
		return
	var found := false
	for input_event in InputMap.action_get_events(action):
		var key_event := input_event as InputEventKey
		if key_event != null and key_event.keycode == keycode:
			found = true
			break
	_expect_true(found, message)


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

extends SceneTree

const VEHICLE_DEFINITION_SCRIPT := preload("res://scripts/vehicles/vehicle_definition.gd")
const VEHICLE_RUNTIME_STATE_SCRIPT := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const MOVE_COMMAND_SCRIPT := preload("res://scripts/vehicles/move_command.gd")
const GRAB_DROP_COMMAND_SCRIPT := preload("res://scripts/vehicles/grab_drop_command.gd")
const GRAB_DROP_INTERACTION_POLICY_SCRIPT := preload("res://scripts/vehicles/grab_drop_interaction_policy.gd")
const GRAB_DROP_RESULT_SCRIPT := preload("res://scripts/vehicles/grab_drop_result.gd")
const ITEM_TRANSFER_RESULT_SCRIPT := preload("res://scripts/objects/item_transfer_result.gd")
const INFINITE_BLOCK_PILE_SCRIPT := preload("res://scripts/objects/infinite_block_pile.gd")
const STANDARD_BOX_SCRIPT := preload("res://scripts/objects/standard_box.gd")
const STANDARD_BLOCK_SCRIPT := preload("res://scripts/objects/standard_block.gd")
const GROUND_BLOCK_FIELD_SCRIPT := preload("res://scripts/objects/ground_block_field.gd")
const REJECTING_RECEIVER_SCRIPT := preload("res://tests/fixtures/rejecting_item_receiver.gd")

var failures: int = 0


func _init() -> void:
	_test_infinite_pile_to_arm_to_tray_round_trip()
	_test_standard_box_is_drop_only()
	_test_drop_failure_restores_arm_ownership()
	_test_busy_and_capability_boundaries()
	_test_cached_tray_respects_owner_motion_guard()
	_test_spatial_target_revalidation()
	_test_explicit_rejection_status_contract()
	_test_reset_and_compatibility_state()
	_test_no_target_contract()

	if failures == 0:
		print("GrabDrop command smoke tests passed.")
		quit(0)
		return
	push_error("GrabDrop command smoke tests failed: %d failure(s)." % failures)
	quit(1)


func _test_infinite_pile_to_arm_to_tray_round_trip() -> void:
	var arm := _make_arm_runtime()
	var transport := _make_transport_runtime()
	if arm == null or transport == null:
		return
	var pile := INFINITE_BLOCK_PILE_SCRIPT.new()
	var command := GRAB_DROP_COMMAND_SCRIPT.new()
	_bind_target_to_primary_front(arm, pile)
	_refresh_tray_target_cells(arm, transport)
	_expect_true(transport.tray_state.can_take_item(), "Transport tray must advertise take capability.")

	var grab = command.execute(arm, pile)
	_expect_equal(grab.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "Pile grab should succeed.")
	_expect_equal(grab.action, GRAB_DROP_RESULT_SCRIPT.Action.GRAB, "Pile operation should be Grab.")
	if not grab.is_success() or grab.item == null:
		_expect_true(false, "Successful pile grab should expose a real block.")
		return
	_expect_true(arm.arm_has_item, "Arm should derive arm_has_item from real carried item.")
	_expect_true(arm.carried_item == grab.item, "Arm should retain the exact grabbed block instance.")
	_expect_true(grab.item.is_claimed_by(arm), "Grabbed block should be owned by arm runtime.")
	_expect_equal(pile.get_produced_count(), 1, "Infinite pile should produce exactly one block.")
	_expect_float_approx(arm.get_effective_speed(), 0.5, "Carrying arm should use 0.25x base speed.")

	var block_id: int = grab.item.get_block_id()
	var drop = command.execute(arm, transport.tray_state)
	_expect_equal(drop.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "Tray drop should succeed.")
	_expect_equal(drop.action, GRAB_DROP_RESULT_SCRIPT.Action.DROP, "Tray operation should be Drop.")
	if not drop.is_success() or drop.item == null:
		_expect_true(false, "Successful tray drop should expose the transferred block.")
		return
	_expect_false(arm.arm_has_item, "Successful drop should clear arm carried item.")
	_expect_equal(transport.tray_count, 1, "Successful tray drop should increment real tray inventory.")
	_expect_true(drop.item.is_claimed_by(transport.tray_state), "Dropped block should be owned by tray.")
	_expect_equal(drop.item.get_block_id(), block_id, "Drop should preserve StandardBlock identity.")

	var regrab = command.execute(arm, transport.tray_state)
	_expect_equal(regrab.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "Tray re-grab should succeed.")
	if not regrab.is_success() or regrab.item == null:
		_expect_true(false, "Successful tray re-grab should expose the transferred block.")
		return
	_expect_equal(transport.tray_count, 0, "Tray re-grab should remove one real item.")
	_expect_true(arm.carried_item == regrab.item, "Re-grab should return the same block to arm.")
	_expect_equal(regrab.item.get_block_id(), block_id, "Tray round trip should preserve block identity.")
	_expect_true(regrab.item.is_claimed_by(arm), "Re-grabbed block should be arm-owned.")

	var box := STANDARD_BOX_SCRIPT.new()
	box.capacity = 8
	box.initial_count = 0
	box.reset()
	_bind_target_to_primary_front(arm, box)
	var box_drop = command.execute(arm, box)
	_expect_equal(box_drop.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "Box drop should succeed.")
	if not box_drop.is_success() or box_drop.item == null:
		_expect_true(false, "Successful box drop should expose the transferred block.")
		return
	_expect_equal(box.get_current_count(), 1, "Box should contain the dropped block.")
	_expect_true(box.contains_item(box_drop.item), "Box should own the exact round-trip block.")
	_expect_equal(box_drop.item.get_block_id(), block_id, "Box transfer should preserve StandardBlock identity.")


func _test_standard_box_is_drop_only() -> void:
	var arm := _make_arm_runtime()
	if arm == null:
		return
	var box := STANDARD_BOX_SCRIPT.new()
	box.capacity = 8
	box.initial_count = 3
	box.reset()
	_bind_target_to_primary_front(arm, box)
	var initial_count: int = box.get_current_count()
	var command := GRAB_DROP_COMMAND_SCRIPT.new()

	_expect_false(box.can_take_item(), "StandardBox must not advertise Grab source capability.")
	var invalid_grab = command.execute(arm, box)
	_expect_equal(
		invalid_grab.status,
		GRAB_DROP_RESULT_SCRIPT.Status.INVALID_TARGET,
		"Empty arm must reject StandardBox as a Grab source."
	)
	_expect_equal(box.get_current_count(), initial_count, "Rejected box Grab must preserve box count.")
	_expect_false(arm.arm_has_item, "Rejected box Grab must preserve empty arm state.")


func _test_drop_failure_restores_arm_ownership() -> void:
	var arm := _make_arm_runtime()
	if arm == null:
		return
	var pile := INFINITE_BLOCK_PILE_SCRIPT.new()
	var command := GRAB_DROP_COMMAND_SCRIPT.new()
	_bind_target_to_primary_front(arm, pile)
	var grab = command.execute(arm, pile)
	if not grab.is_success() or arm.carried_item == null:
		_expect_true(false, "Failure fixture requires one carried block.")
		return
	var carried = arm.carried_item
	var full_box := STANDARD_BOX_SCRIPT.new()
	full_box.capacity = 1
	full_box.initial_count = 1
	full_box.reset()
	_bind_target_to_primary_front(arm, full_box)
	var original_count := full_box.get_current_count()

	var failed_drop = command.execute(arm, full_box)
	_expect_equal(failed_drop.status, GRAB_DROP_RESULT_SCRIPT.Status.FULL, "Full box should reject Drop.")
	_expect_true(arm.carried_item == carried, "Failed Drop should restore exact arm item.")
	_expect_true(carried.is_claimed_by(arm), "Failed Drop should restore arm ownership.")
	_expect_equal(full_box.get_current_count(), original_count, "Failed Drop should preserve receiver count.")


func _test_busy_and_capability_boundaries() -> void:
	var arm := _make_arm_runtime()
	var transport := _make_transport_runtime()
	if arm == null or transport == null:
		return
	var pile := INFINITE_BLOCK_PILE_SCRIPT.new()
	var command := GRAB_DROP_COMMAND_SCRIPT.new()

	_expect_true(arm.begin_move_planning(), "Busy fixture should enter Planning.")
	var planning_busy = command.execute(arm, pile)
	_expect_equal(
		planning_busy.status,
		GRAB_DROP_RESULT_SCRIPT.Status.BUSY,
		"Planning arm should reject GrabDrop."
	)
	_expect_equal(pile.get_produced_count(), 0, "Planning rejection must not consume the source.")
	_expect_false(arm.arm_has_item, "Planning rejection must not mutate arm carry state.")
	arm.clear_move_command()

	var move_command := MOVE_COMMAND_SCRIPT.new()
	_expect_true(
		move_command.configure(Vector2i(3, 2), [Vector2i(2, 2), Vector2i(3, 2)]),
		"Moving fixture command should configure."
	)
	_expect_true(arm.assign_move_command(move_command), "Busy fixture should enter Moving.")
	var moving_busy = command.execute(arm, pile)
	_expect_equal(
		moving_busy.status,
		GRAB_DROP_RESULT_SCRIPT.Status.BUSY,
		"Moving arm should reject GrabDrop."
	)
	_expect_equal(pile.get_produced_count(), 0, "Moving rejection must not consume the source.")
	_expect_false(arm.arm_has_item, "Moving rejection must not mutate arm carry state.")
	arm.clear_move_command()

	var unsupported = command.execute(transport, pile)
	_expect_equal(
		unsupported.status,
		GRAB_DROP_RESULT_SCRIPT.Status.NO_CAPABILITY,
		"Transport vehicle should reject GrabDrop without can_grab."
	)
	_expect_equal(pile.get_produced_count(), 0, "Capability rejection must not consume source.")


func _test_cached_tray_respects_owner_motion_guard() -> void:
	var arm := _make_arm_runtime()
	var transport := _make_transport_runtime()
	if arm == null or transport == null or transport.tray_state == null:
		return
	var command := GRAB_DROP_COMMAND_SCRIPT.new()
	var cached_tray = transport.tray_state
	_refresh_tray_target_cells(arm, transport)
	var tray_block := STANDARD_BLOCK_SCRIPT.create()
	_expect_true(cached_tray.put_item(tray_block).is_success(), "Cached-tray fixture should load one block while Waiting.")
	_expect_equal(cached_tray.get_current_count(), 1, "Cached-tray fixture should start at 1/8.")

	_expect_true(transport.begin_move_planning(), "Cached tray owner should enter Planning.")
	_expect_false(cached_tray.can_take_item(), "Cached tray must become unavailable while owner is Planning.")
	var planning_grab = command.execute(arm, cached_tray)
	_expect_equal(
		planning_grab.status,
		GRAB_DROP_RESULT_SCRIPT.Status.NO_TARGET,
		"Shared command must reject a cached tray with cleared interaction cells while its owner is Planning."
	)
	_expect_equal(cached_tray.get_current_count(), 1, "Planning rejection must preserve cached tray inventory.")
	_expect_true(tray_block.is_claimed_by(cached_tray), "Planning rejection must preserve tray ownership.")
	_expect_false(arm.arm_has_item, "Planning target rejection must preserve empty arm.")

	transport.clear_move_command()
	var stale_waiting_grab = command.execute(arm, cached_tray)
	_expect_equal(
		stale_waiting_grab.status,
		GRAB_DROP_RESULT_SCRIPT.Status.NO_TARGET,
		"A stopped tray must remain non-interactable until its current cells are republished."
	)
	_refresh_tray_target_cells(arm, transport)
	_expect_true(cached_tray.can_take_item(), "Republished cached tray should recover while owner is Waiting.")
	var recovered_grab = command.execute(arm, cached_tray)
	_expect_equal(recovered_grab.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "Recovered cached tray should be grabbable.")
	_expect_true(arm.carried_item == tray_block, "Recovered Grab should transfer the exact cached tray block.")
	_expect_equal(cached_tray.get_current_count(), 0, "Recovered Grab should empty the tray.")

	var move_command := MOVE_COMMAND_SCRIPT.new()
	_expect_true(
		move_command.configure(Vector2i(5, 3), [Vector2i(6, 3), Vector2i(5, 3)]),
		"Cached-tray Moving fixture should configure."
	)
	_expect_true(transport.assign_move_command(move_command), "Cached tray owner should enter Moving.")
	_expect_false(cached_tray.can_take_item(), "Cached tray must remain unavailable while owner is Moving.")
	var moving_drop = command.execute(arm, cached_tray)
	_expect_equal(
		moving_drop.status,
		GRAB_DROP_RESULT_SCRIPT.Status.NO_TARGET,
		"Shared command must reject Drop to a cached tray with cleared cells while its owner is Moving."
	)
	_expect_true(arm.carried_item == tray_block, "Moving target rejection must preserve exact arm cargo.")
	_expect_true(tray_block.is_claimed_by(arm), "Moving target rejection must preserve arm ownership.")
	_expect_equal(cached_tray.get_current_count(), 0, "Moving target rejection must preserve empty tray inventory.")

	transport.clear_move_command()
	var stale_waiting_drop = command.execute(arm, cached_tray)
	_expect_equal(
		stale_waiting_drop.status,
		GRAB_DROP_RESULT_SCRIPT.Status.NO_TARGET,
		"Stopped cached tray must not regain stale spatial reach without registry refresh."
	)
	_refresh_tray_target_cells(arm, transport)
	var recovered_drop = command.execute(arm, cached_tray)
	_expect_equal(recovered_drop.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "Republished cached tray should accept Drop after owner stops.")
	_expect_true(cached_tray.contains_item(tray_block), "Recovered Drop should restore exact item to cached tray.")
	_expect_false(arm.arm_has_item, "Recovered Drop should empty the arm.")


func _test_spatial_target_revalidation() -> void:
	var arm := _make_arm_runtime()
	if arm == null:
		return
	var command := GRAB_DROP_COMMAND_SCRIPT.new()
	var pile := INFINITE_BLOCK_PILE_SCRIPT.new()
	_bind_target_to_primary_front(arm, pile)
	var original_target_cell := GRAB_DROP_INTERACTION_POLICY_SCRIPT.get_primary_interaction_cell(arm)
	arm.anchor_cell = Vector2i(5, 5)
	var remote_grab = command.execute(arm, pile)
	_expect_equal(
		remote_grab.status,
		GRAB_DROP_RESULT_SCRIPT.Status.NO_TARGET,
		"Shared command must reject a cached source after the arm moves away."
	)
	_expect_equal(pile.get_produced_count(), 0, "Remote Grab rejection must not consume the source.")
	_expect_false(arm.arm_has_item, "Remote Grab rejection must preserve empty arm state.")

	_bind_target_to_primary_front(arm, pile)
	var local_grab = command.execute(arm, pile)
	_expect_equal(local_grab.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "Retargeted source should become reachable again.")
	if not local_grab.is_success() or arm.carried_item == null:
		return
	var carried = arm.carried_item
	var box := STANDARD_BOX_SCRIPT.new()
	box.capacity = 8
	box.initial_count = 0
	box.reset()
	var stale_box_cells: Array[Vector2i] = [original_target_cell]
	box.set_interaction_cells(stale_box_cells)
	var remote_drop = command.execute(arm, box)
	_expect_equal(
		remote_drop.status,
		GRAB_DROP_RESULT_SCRIPT.Status.NO_TARGET,
		"Shared command must reject a receiver that is no longer on the current forward edge."
	)
	_expect_true(arm.carried_item == carried, "Remote Drop rejection must preserve exact cargo.")
	_expect_true(carried.is_claimed_by(arm), "Remote Drop rejection must preserve arm ownership.")
	_expect_equal(box.get_current_count(), 0, "Remote Drop rejection must not mutate receiver inventory.")

	var field := GROUND_BLOCK_FIELD_SCRIPT.new()
	var forward_cells := GRAB_DROP_INTERACTION_POLICY_SCRIPT.get_forward_interaction_cells(arm)
	if forward_cells.size() < 2:
		_expect_true(false, "Ground primary-socket fixture requires a 2-cell forward edge.")
		return
	var secondary_cell: Vector2i = forward_cells[1]
	var valid_cells: Array[Vector2i] = [secondary_cell]
	field.configure_valid_cells(valid_cells)
	var secondary_ground = field.get_cell_interface(secondary_cell)
	_expect_true(secondary_ground != null, "Ground primary-socket fixture requires a legal secondary ground interface.")
	if secondary_ground == null:
		return
	var secondary_drop = command.execute(arm, secondary_ground)
	_expect_equal(
		secondary_drop.status,
		GRAB_DROP_RESULT_SCRIPT.Status.NO_TARGET,
		"Ground receiver must require the primary/front-left socket even when another forward cell overlaps."
	)
	_expect_true(arm.carried_item == carried, "Secondary ground rejection must preserve exact cargo.")
	_expect_false(field.has_item(secondary_cell), "Secondary ground rejection must not place cargo.")


func _test_explicit_rejection_status_contract() -> void:
	var arm := _make_arm_runtime()
	var transport := _make_transport_runtime()
	if arm == null or transport == null or transport.tray_state == null:
		return
	var command := GRAB_DROP_COMMAND_SCRIPT.new()
	_refresh_tray_target_cells(arm, transport)

	var empty_grab = command.execute(arm, transport.tray_state)
	_expect_equal(
		empty_grab.status,
		GRAB_DROP_RESULT_SCRIPT.Status.EMPTY,
		"Empty compatible tray should surface source-empty through GrabDropCommand."
	)
	_expect_false(arm.arm_has_item, "Source-empty rejection must preserve empty arm.")
	_expect_equal(transport.tray_count, 0, "Source-empty rejection must preserve tray count.")

	var carried := STANDARD_BLOCK_SCRIPT.create()
	_expect_true(arm.claim_carried_item(carried), "Explicit rejection fixture requires one arm-owned block.")
	_assert_rejecting_drop_status(
		arm,
		command,
		ITEM_TRANSFER_RESULT_SCRIPT.Status.TYPE_MISMATCH,
		GRAB_DROP_RESULT_SCRIPT.Status.TYPE_MISMATCH,
		"Type mismatch"
	)
	_assert_rejecting_drop_status(
		arm,
		command,
		ITEM_TRANSFER_RESULT_SCRIPT.Status.ALREADY_CONTAINED,
		GRAB_DROP_RESULT_SCRIPT.Status.ALREADY_CONTAINED,
		"Duplicate consumption"
	)
	_assert_rejecting_drop_status(
		arm,
		command,
		ITEM_TRANSFER_RESULT_SCRIPT.Status.OCCUPIED,
		GRAB_DROP_RESULT_SCRIPT.Status.GROUND_OCCUPIED,
		"Occupied receiver"
	)


func _assert_rejecting_drop_status(
	arm: VEHICLE_RUNTIME_STATE_SCRIPT,
	command: GRAB_DROP_COMMAND_SCRIPT,
	transfer_status: int,
	expected_status: int,
	context: String
) -> void:
	var receiver := REJECTING_RECEIVER_SCRIPT.new()
	var cells: Array[Vector2i] = [
		GRAB_DROP_INTERACTION_POLICY_SCRIPT.get_primary_interaction_cell(arm),
	]
	_expect_true(receiver.configure_rejection(transfer_status, cells), "%s fixture should configure." % context)
	var carried = arm.carried_item
	var result = command.execute(arm, receiver)
	_expect_equal(result.status, expected_status, "%s should preserve GrabDrop result semantics." % context)
	_expect_equal(receiver.put_attempts, 1, "%s should execute exactly one receiver transaction." % context)
	_expect_true(arm.carried_item == carried, "%s rejection must restore exact arm cargo." % context)
	_expect_true(carried != null and carried.is_claimed_by(arm), "%s rejection must restore arm ownership." % context)


func _test_reset_and_compatibility_state() -> void:
	var arm := _make_arm_runtime()
	if arm == null:
		return
	_expect_true(arm.set_arm_has_item(true), "Legacy arm_has_item setter should create real cargo.")
	var compatibility_item = arm.carried_item
	if compatibility_item == null:
		_expect_true(false, "Compatibility true should create a StandardBlock.")
		return
	_expect_true(compatibility_item.is_claimed_by(arm), "Compatibility cargo should be arm-owned.")
	_expect_true(arm.set_arm_has_item(true), "Repeated compatibility true should be a no-op.")
	_expect_true(arm.carried_item == compatibility_item, "Repeated compatibility true should preserve identity.")
	_expect_true(arm.set_arm_has_item(false), "Compatibility false should release cargo.")
	_expect_false(compatibility_item.is_claimed(), "Compatibility false should release ownership.")
	_expect_false(arm.arm_has_item, "Compatibility false should clear derived state.")

	var pile := INFINITE_BLOCK_PILE_SCRIPT.new()
	var command := GRAB_DROP_COMMAND_SCRIPT.new()
	_bind_target_to_primary_front(arm, pile)
	var grab = command.execute(arm, pile)
	if not grab.is_success() or arm.carried_item == null:
		_expect_true(false, "Reset fixture requires one carried block.")
		return
	var carried = arm.carried_item
	arm.reset()
	_expect_false(arm.arm_has_item, "Reset should clear real arm cargo.")
	_expect_true(arm.carried_item == null, "Reset should clear carried item reference.")
	_expect_false(carried.is_claimed(), "Reset should release carried item ownership.")


func _test_no_target_contract() -> void:
	var arm := _make_arm_runtime()
	if arm == null:
		return
	var command := GRAB_DROP_COMMAND_SCRIPT.new()
	var empty_arm = command.execute(arm, null)
	_expect_equal(empty_arm.status, GRAB_DROP_RESULT_SCRIPT.Status.NO_TARGET, "Empty arm should report no Grab target.")
	_expect_equal(empty_arm.action, GRAB_DROP_RESULT_SCRIPT.Action.GRAB, "Empty arm no-target action should be Grab.")
	_expect_true(arm.set_arm_has_item(true), "No-target Drop fixture requires cargo.")
	var loaded_arm = command.execute(arm, null)
	_expect_equal(loaded_arm.status, GRAB_DROP_RESULT_SCRIPT.Status.NO_TARGET, "Loaded arm should report no Drop target.")
	_expect_equal(loaded_arm.action, GRAB_DROP_RESULT_SCRIPT.Action.DROP, "Loaded arm no-target action should be Drop.")
	_expect_true(arm.arm_has_item, "No-target Drop rejection should preserve cargo.")


func _bind_target_to_primary_front(runtime: VEHICLE_RUNTIME_STATE_SCRIPT, target: Object) -> void:
	if runtime == null or target == null or not target.has_method("set_interaction_cells"):
		return
	var cells: Array[Vector2i] = [
		GRAB_DROP_INTERACTION_POLICY_SCRIPT.get_primary_interaction_cell(runtime),
	]
	target.call("set_interaction_cells", cells)


func _refresh_tray_target_cells(
	arm: VEHICLE_RUNTIME_STATE_SCRIPT,
	transport: VEHICLE_RUNTIME_STATE_SCRIPT
) -> void:
	if arm == null or transport == null:
		return
	var cells: Array[Vector2i] = [
		GRAB_DROP_INTERACTION_POLICY_SCRIPT.get_primary_interaction_cell(arm),
	]
	transport.get_item_interaction_interfaces(cells)


func _make_arm_runtime() -> VEHICLE_RUNTIME_STATE_SCRIPT:
	var definition := VEHICLE_DEFINITION_SCRIPT.new()
	var configured := definition.configure(
		&"test_arm",
		"Test Arm",
		VEHICLE_DEFINITION_SCRIPT.VehicleKind.ARM,
		Vector2i(2, 2),
		2.0,
		18.0,
		0.0,
		8.0,
		PackedStringArray([
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_MOVE,
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_GRAB,
		]),
		0.25,
		0
	)
	_expect_true(configured, "Arm definition should configure.")
	if not configured:
		return null
	var runtime := VEHICLE_RUNTIME_STATE_SCRIPT.new()
	_expect_true(runtime.configure(definition, Vector2i(2, 2)), "Arm runtime should configure.")
	return runtime


func _make_transport_runtime() -> VEHICLE_RUNTIME_STATE_SCRIPT:
	var definition := VEHICLE_DEFINITION_SCRIPT.new()
	var configured := definition.configure(
		&"test_transport",
		"Test Transport",
		VEHICLE_DEFINITION_SCRIPT.VehicleKind.TRANSPORT,
		Vector2i(2, 2),
		2.4,
		16.0,
		0.0,
		8.0,
		PackedStringArray([
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_MOVE,
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_CARRY,
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_HAS_TRAY,
		]),
		1.0,
		8
	)
	_expect_true(configured, "Transport definition should configure.")
	if not configured:
		return null
	var runtime := VEHICLE_RUNTIME_STATE_SCRIPT.new()
	_expect_true(runtime.configure(definition, Vector2i(6, 3)), "Transport runtime should configure.")
	return runtime


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


func _expect_float_approx(actual: float, expected: float, message: String) -> void:
	if is_equal_approx(actual, expected):
		return
	failures += 1
	push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])

extends SceneTree

const VEHICLE_DEFINITION_SCRIPT := preload("res://scripts/vehicles/vehicle_definition.gd")
const VEHICLE_RUNTIME_STATE_SCRIPT := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const GRAB_DROP_COMMAND_SCRIPT := preload("res://scripts/vehicles/grab_drop_command.gd")
const GRAB_DROP_RESULT_SCRIPT := preload("res://scripts/vehicles/grab_drop_result.gd")
const INFINITE_BLOCK_PILE_SCRIPT := preload("res://scripts/objects/infinite_block_pile.gd")
const STANDARD_BOX_SCRIPT := preload("res://scripts/objects/standard_box.gd")

var failures: int = 0


func _init() -> void:
	_test_infinite_pile_to_arm_to_tray_round_trip()
	_test_drop_failure_restores_arm_ownership()
	_test_busy_and_capability_boundaries()
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
	var box_drop = command.execute(arm, box)
	_expect_equal(box_drop.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "Box drop should succeed.")
	if not box_drop.is_success() or box_drop.item == null:
		_expect_true(false, "Successful box drop should expose the transferred block.")
		return
	_expect_equal(box.get_current_count(), 1, "Box should contain the dropped block.")
	_expect_true(box.contains_item(box_drop.item), "Box should own the exact round-trip block.")
	_expect_equal(box_drop.item.get_block_id(), block_id, "Box transfer should preserve block identity.")


func _test_drop_failure_restores_arm_ownership() -> void:
	var arm := _make_arm_runtime()
	if arm == null:
		return
	var pile := INFINITE_BLOCK_PILE_SCRIPT.new()
	var command := GRAB_DROP_COMMAND_SCRIPT.new()
	var grab = command.execute(arm, pile)
	if not grab.is_success() or arm.carried_item == null:
		_expect_true(false, "Failure fixture requires one carried block.")
		return
	var carried = arm.carried_item
	var full_box := STANDARD_BOX_SCRIPT.new()
	full_box.capacity = 1
	full_box.initial_count = 1
	full_box.reset()
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
	var busy = command.execute(arm, pile)
	_expect_equal(busy.status, GRAB_DROP_RESULT_SCRIPT.Status.BUSY, "Planning arm should reject GrabDrop.")
	_expect_equal(pile.get_produced_count(), 0, "Busy rejection must not consume the source.")
	_expect_false(arm.arm_has_item, "Busy rejection must not mutate arm carry state.")
	arm.clear_move_command()

	var unsupported = command.execute(transport, pile)
	_expect_equal(
		unsupported.status,
		GRAB_DROP_RESULT_SCRIPT.Status.NO_CAPABILITY,
		"Transport vehicle should reject GrabDrop without can_grab."
	)
	_expect_equal(pile.get_produced_count(), 0, "Capability rejection must not consume source.")


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

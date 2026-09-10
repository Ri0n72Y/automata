extends SceneTree

const VEHICLE_DEFINITION := preload("res://scripts/vehicles/vehicle_definition.gd")
const VEHICLE_RUNTIME := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const MOVE_COMMAND := preload("res://scripts/vehicles/move_command.gd")
const GRAB_DROP_COMMAND := preload("res://scripts/vehicles/grab_drop_command.gd")
const GRAB_DROP_POLICY := preload("res://scripts/vehicles/grab_drop_interaction_policy.gd")
const GRAB_DROP_RESULT := preload("res://scripts/vehicles/grab_drop_result.gd")
const ITEM_TRANSFER_RESULT := preload("res://scripts/objects/item_transfer_result.gd")
const INFINITE_BLOCK_PILE := preload("res://scripts/objects/infinite_block_pile.gd")
const STANDARD_BOX := preload("res://scripts/objects/standard_box.gd")
const STANDARD_BLOCK := preload("res://scripts/objects/standard_block.gd")
const REJECTING_RECEIVER := preload("res://tests/fixtures/rejecting_item_receiver.gd")
const CONTRACT := preload("res://tests/support/contract_test.gd")

var test := CONTRACT.new()


func _init() -> void:
	_test_round_trip_preserves_identity_and_ownership()
	_test_drop_failure_restores_arm_ownership()
	_test_busy_and_capability_boundaries()
	_test_moving_tray_is_not_a_target()
	_test_spatial_target_revalidation()
	_test_transfer_status_mapping()
	_test_reset_releases_arm_ownership()
	_test_no_target_actions()
	test.finish(self, "GrabDrop command smoke tests")


func _test_round_trip_preserves_identity_and_ownership() -> void:
	var arm := _make_arm_runtime()
	var transport := _make_transport_runtime()
	if arm == null or transport == null:
		return
	var pile := INFINITE_BLOCK_PILE.new()
	var command := GRAB_DROP_COMMAND.new()
	_bind_to_primary_front(arm, pile)
	_publish_tray_at_arm(arm, transport)

	var grab = command.execute(arm, pile)
	test.expect_equal(grab.status, GRAB_DROP_RESULT.Status.ACCEPTED, "Pile Grab should succeed.")
	if not grab.is_success() or grab.item == null:
		return
	var block = grab.item
	var block_id: int = block.get_block_id()
	test.expect_true(arm.carried_item == block, "Arm should carry the exact pile block.")
	test.expect_true(block.is_claimed_by(arm), "Arm should own the grabbed block.")
	test.expect_float_approx(arm.get_effective_speed(), 0.5, "Carrying should apply the arm speed multiplier.")

	var tray_drop = command.execute(arm, transport.tray_state)
	test.expect_equal(tray_drop.status, GRAB_DROP_RESULT.Status.ACCEPTED, "Tray Drop should succeed.")
	test.expect_false(arm.arm_has_item, "Successful Drop should empty the arm.")
	test.expect_equal(transport.tray_count, 1, "Tray should contain one real block.")
	test.expect_true(block.is_claimed_by(transport.tray_state), "Tray should own the transferred block.")

	var tray_grab = command.execute(arm, transport.tray_state)
	test.expect_equal(tray_grab.status, GRAB_DROP_RESULT.Status.ACCEPTED, "Tray re-Grab should succeed.")
	test.expect_true(arm.carried_item == block, "Tray round trip should preserve block identity.")
	test.expect_equal(block.get_block_id(), block_id, "Tray round trip should preserve block id.")
	test.expect_equal(transport.tray_count, 0, "Tray re-Grab should empty the tray.")
	test.expect_true(block.is_claimed_by(arm), "Re-grabbed block should return to arm ownership.")

	var box := STANDARD_BOX.new()
	box.capacity = 8
	box.initial_count = 0
	box.reset()
	_bind_to_primary_front(arm, box)
	var box_drop = command.execute(arm, box)
	test.expect_equal(box_drop.status, GRAB_DROP_RESULT.Status.ACCEPTED, "Box Drop should succeed.")
	test.expect_equal(box.get_current_count(), 1, "Box should contain the dropped block.")
	test.expect_true(box.contains_item(block), "Box should own the exact transferred block.")
	test.expect_equal(block.get_block_id(), block_id, "Box transfer should preserve block identity.")

	var invalid_box_grab = command.execute(arm, box)
	test.expect_equal(
		invalid_box_grab.status,
		GRAB_DROP_RESULT.Status.INVALID_TARGET,
		"StandardBox should remain Drop-only."
	)


func _test_drop_failure_restores_arm_ownership() -> void:
	var arm := _make_arm_runtime()
	if arm == null:
		return
	var block := STANDARD_BLOCK.create()
	test.expect_true(arm.claim_carried_item(block), "Failure fixture should load one real block.")
	var full_box := STANDARD_BOX.new()
	full_box.capacity = 1
	full_box.initial_count = 1
	full_box.reset()
	_bind_to_primary_front(arm, full_box)

	var result = GRAB_DROP_COMMAND.new().execute(arm, full_box)
	test.expect_equal(result.status, GRAB_DROP_RESULT.Status.FULL, "Full box should reject Drop.")
	test.expect_true(arm.carried_item == block, "Failed Drop should restore exact arm cargo.")
	test.expect_true(block.is_claimed_by(arm), "Failed Drop should restore arm ownership.")
	test.expect_equal(full_box.get_current_count(), 1, "Failed Drop should preserve receiver state.")


func _test_busy_and_capability_boundaries() -> void:
	var arm := _make_arm_runtime()
	var transport := _make_transport_runtime()
	if arm == null or transport == null:
		return
	var pile := INFINITE_BLOCK_PILE.new()
	var command := GRAB_DROP_COMMAND.new()

	test.expect_true(arm.begin_move_planning(), "Busy fixture should enter Planning.")
	var planning = command.execute(arm, pile)
	test.expect_equal(planning.status, GRAB_DROP_RESULT.Status.BUSY, "Planning arm should reject GrabDrop.")
	test.expect_false(arm.arm_has_item, "Planning rejection should preserve empty arm state.")
	arm.clear_move_command()

	var move := MOVE_COMMAND.new()
	test.expect_true(
		move.configure(Vector2i(3, 2), [Vector2i(2, 2), Vector2i(3, 2)]),
		"Moving fixture should configure."
	)
	test.expect_true(arm.assign_move_command(move), "Busy fixture should enter Moving.")
	var moving = command.execute(arm, pile)
	test.expect_equal(moving.status, GRAB_DROP_RESULT.Status.BUSY, "Moving arm should reject GrabDrop.")
	test.expect_false(arm.arm_has_item, "Moving rejection should preserve empty arm state.")
	arm.clear_move_command()

	var unsupported = command.execute(transport, pile)
	test.expect_equal(
		unsupported.status,
		GRAB_DROP_RESULT.Status.NO_CAPABILITY,
		"Transport should reject GrabDrop without can_grab."
	)


func _test_moving_tray_is_not_a_target() -> void:
	var arm := _make_arm_runtime()
	var transport := _make_transport_runtime()
	if arm == null or transport == null:
		return
	var tray = transport.tray_state
	var block := STANDARD_BLOCK.create()
	test.expect_true(tray.put_item(block).is_success(), "Tray fixture should load one block.")
	_publish_tray_at_arm(arm, transport)

	test.expect_true(transport.begin_move_planning(), "Tray owner should enter Planning.")
	var planning = GRAB_DROP_COMMAND.new().execute(arm, tray)
	test.expect_equal(planning.status, GRAB_DROP_RESULT.Status.NO_TARGET, "Planning tray should not be targetable.")
	test.expect_true(block.is_claimed_by(tray), "Planning rejection should preserve tray ownership.")
	transport.clear_move_command()

	_publish_tray_at_arm(arm, transport)
	var recovered = GRAB_DROP_COMMAND.new().execute(arm, tray)
	test.expect_equal(recovered.status, GRAB_DROP_RESULT.Status.ACCEPTED, "Republished stationary tray should be targetable.")
	test.expect_true(arm.carried_item == block, "Recovered Grab should preserve block identity.")

	var move := MOVE_COMMAND.new()
	test.expect_true(
		move.configure(Vector2i(5, 3), [Vector2i(6, 3), Vector2i(5, 3)]),
		"Moving tray fixture should configure."
	)
	test.expect_true(transport.assign_move_command(move), "Tray owner should enter Moving.")
	var moving_drop = GRAB_DROP_COMMAND.new().execute(arm, tray)
	test.expect_equal(moving_drop.status, GRAB_DROP_RESULT.Status.NO_TARGET, "Moving tray should reject Drop.")
	test.expect_true(arm.carried_item == block, "Moving tray rejection should preserve arm cargo.")
	test.expect_true(block.is_claimed_by(arm), "Moving tray rejection should preserve arm ownership.")


func _test_spatial_target_revalidation() -> void:
	var arm := _make_arm_runtime()
	if arm == null:
		return
	var pile := INFINITE_BLOCK_PILE.new()
	var command := GRAB_DROP_COMMAND.new()
	_bind_to_primary_front(arm, pile)
	arm.anchor_cell = Vector2i(5, 5)
	var stale = command.execute(arm, pile)
	test.expect_equal(stale.status, GRAB_DROP_RESULT.Status.NO_TARGET, "Cached remote source should be rejected.")
	test.expect_false(arm.arm_has_item, "Remote source rejection should preserve empty arm state.")

	_bind_to_primary_front(arm, pile)
	var current = command.execute(arm, pile)
	test.expect_equal(current.status, GRAB_DROP_RESULT.Status.ACCEPTED, "Retargeted source should be accepted.")


func _test_transfer_status_mapping() -> void:
	var arm := _make_arm_runtime()
	if arm == null:
		return
	var block := STANDARD_BLOCK.create()
	test.expect_true(arm.claim_carried_item(block), "Status fixture should load one real block.")
	var cases: Array[Dictionary] = [
		{"transfer": ITEM_TRANSFER_RESULT.Status.TYPE_MISMATCH, "grab_drop": GRAB_DROP_RESULT.Status.TYPE_MISMATCH},
		{"transfer": ITEM_TRANSFER_RESULT.Status.ALREADY_CONTAINED, "grab_drop": GRAB_DROP_RESULT.Status.ALREADY_CONTAINED},
		{"transfer": ITEM_TRANSFER_RESULT.Status.OCCUPIED, "grab_drop": GRAB_DROP_RESULT.Status.GROUND_OCCUPIED},
	]
	for case in cases:
		var receiver := REJECTING_RECEIVER.new()
		var cells: Array[Vector2i] = [GRAB_DROP_POLICY.get_primary_interaction_cell(arm)]
		test.expect_true(receiver.configure_rejection(int(case["transfer"]), cells), "Rejecting receiver should configure.")
		var result = GRAB_DROP_COMMAND.new().execute(arm, receiver)
		test.expect_equal(result.status, int(case["grab_drop"]), "Transfer rejection should preserve public status semantics.")
		test.expect_equal(receiver.put_attempts, 1, "Rejected Drop should attempt the receiver once.")
		test.expect_true(arm.carried_item == block, "Rejected Drop should restore exact arm cargo.")
		test.expect_true(block.is_claimed_by(arm), "Rejected Drop should restore arm ownership.")


func _test_reset_releases_arm_ownership() -> void:
	var arm := _make_arm_runtime()
	if arm == null:
		return
	var block := STANDARD_BLOCK.create()
	test.expect_true(arm.claim_carried_item(block), "Reset fixture should load one real block.")
	arm.reset()
	test.expect_true(arm.carried_item == null, "Reset should clear carried item reference.")
	test.expect_false(block.is_claimed(), "Reset should release former arm cargo ownership.")


func _test_no_target_actions() -> void:
	var arm := _make_arm_runtime()
	if arm == null:
		return
	var command := GRAB_DROP_COMMAND.new()
	var empty = command.execute(arm, null)
	test.expect_equal(empty.status, GRAB_DROP_RESULT.Status.NO_TARGET, "Empty arm should report no target.")
	test.expect_equal(empty.action, GRAB_DROP_RESULT.Action.GRAB, "Empty-arm no-target action should be Grab.")

	var block := STANDARD_BLOCK.create()
	test.expect_true(arm.claim_carried_item(block), "Loaded no-target fixture should use real cargo.")
	var loaded = command.execute(arm, null)
	test.expect_equal(loaded.status, GRAB_DROP_RESULT.Status.NO_TARGET, "Loaded arm should report no target.")
	test.expect_equal(loaded.action, GRAB_DROP_RESULT.Action.DROP, "Loaded-arm no-target action should be Drop.")
	test.expect_true(block.is_claimed_by(arm), "No-target Drop should preserve arm ownership.")


func _bind_to_primary_front(runtime: VEHICLE_RUNTIME, target: Object) -> void:
	if target == null or not target.has_method("set_interaction_cells"):
		return
	var cells: Array[Vector2i] = [GRAB_DROP_POLICY.get_primary_interaction_cell(runtime)]
	target.call("set_interaction_cells", cells)


func _publish_tray_at_arm(arm: VEHICLE_RUNTIME, transport: VEHICLE_RUNTIME) -> void:
	var cells: Array[Vector2i] = [GRAB_DROP_POLICY.get_primary_interaction_cell(arm)]
	transport.get_item_interaction_interfaces(cells)


func _make_arm_runtime() -> VEHICLE_RUNTIME:
	var definition := VEHICLE_DEFINITION.new()
	if not definition.configure(
		&"test_arm",
		"Test Arm",
		VEHICLE_DEFINITION.VehicleKind.ARM,
		Vector2i(2, 2),
		2.0,
		18.0,
		0.0,
		8.0,
		PackedStringArray([
			VEHICLE_DEFINITION.CAPABILITY_CAN_MOVE,
			VEHICLE_DEFINITION.CAPABILITY_CAN_GRAB,
		]),
		0.25,
		0
	):
		test.expect_true(false, "Arm definition should configure.")
		return null
	var runtime := VEHICLE_RUNTIME.new()
	test.expect_true(runtime.configure(definition, Vector2i(2, 2)), "Arm runtime should configure.")
	return runtime


func _make_transport_runtime() -> VEHICLE_RUNTIME:
	var definition := VEHICLE_DEFINITION.new()
	if not definition.configure(
		&"test_transport",
		"Test Transport",
		VEHICLE_DEFINITION.VehicleKind.TRANSPORT,
		Vector2i(2, 2),
		2.4,
		16.0,
		0.0,
		8.0,
		PackedStringArray([
			VEHICLE_DEFINITION.CAPABILITY_CAN_MOVE,
			VEHICLE_DEFINITION.CAPABILITY_CAN_CARRY,
			VEHICLE_DEFINITION.CAPABILITY_HAS_TRAY,
		]),
		1.0,
		8
	):
		test.expect_true(false, "Transport definition should configure.")
		return null
	var runtime := VEHICLE_RUNTIME.new()
	test.expect_true(runtime.configure(definition, Vector2i(6, 3)), "Transport runtime should configure.")
	return runtime

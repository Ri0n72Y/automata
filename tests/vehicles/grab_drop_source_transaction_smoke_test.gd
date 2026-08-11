extends SceneTree

const VEHICLE_DEFINITION_SCRIPT := preload("res://scripts/vehicles/vehicle_definition.gd")
const VEHICLE_RUNTIME_STATE_SCRIPT := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const GRAB_DROP_COMMAND_SCRIPT := preload("res://scripts/vehicles/grab_drop_command.gd")
const GRAB_DROP_INTERACTION_POLICY_SCRIPT := preload("res://scripts/vehicles/grab_drop_interaction_policy.gd")
const GRAB_DROP_RESULT_SCRIPT := preload("res://scripts/vehicles/grab_drop_result.gd")
const INFINITE_BLOCK_PILE_SCRIPT := preload("res://scripts/objects/infinite_block_pile.gd")
const REJECTING_RUNTIME_SCRIPT := preload("res://tests/fixtures/rejecting_carried_item_runtime.gd")

var failures: int = 0


func _init() -> void:
	_test_prepared_pile_transaction()
	_test_command_rolls_back_failed_source_claim()

	if failures == 0:
		print("GrabDrop source transaction smoke tests passed.")
		quit(0)
		return
	push_error("GrabDrop source transaction smoke tests failed: %d failure(s)." % failures)
	quit(1)


func _test_prepared_pile_transaction() -> void:
	var pile := INFINITE_BLOCK_PILE_SCRIPT.new()
	var transitions: Array[Vector2i] = []
	pile.produced_count_changed.connect(
		func(previous_count: int, current_count: int) -> void:
			transitions.append(Vector2i(previous_count, current_count))
	)

	var prepared = pile.prepare_take_item()
	_expect_true(prepared.is_success() and prepared.item != null, "Prepare should return one real block.")
	_expect_equal(pile.get_produced_count(), 0, "Prepare must not publish production before transfer commit.")
	_expect_equal(transitions.size(), 0, "Prepare must not emit produced_count_changed.")
	if prepared.item == null:
		return
	_expect_true(pile.rollback_prepared_take_item(prepared.item), "Prepared block should support rollback.")
	_expect_equal(pile.get_produced_count(), 0, "Rollback must preserve produced count.")
	_expect_equal(transitions.size(), 0, "Rollback must remain invisible to production observers.")
	_expect_false(pile.rollback_prepared_take_item(prepared.item), "Prepared block may only be rolled back once.")

	var committed = pile.prepare_take_item()
	_expect_true(committed.is_success() and committed.item != null, "Second prepare should remain available.")
	if committed.item == null:
		return
	_expect_true(pile.commit_prepared_take_item(committed.item), "Prepared block should commit once.")
	_expect_equal(pile.get_produced_count(), 1, "Commit should publish exactly one produced block.")
	_expect_equal(transitions, [Vector2i(0, 1)], "Commit should emit only the confirmed 0→1 transition.")
	_expect_false(pile.commit_prepared_take_item(committed.item), "Prepared block may only be committed once.")

	var direct = pile.take_item()
	_expect_true(direct.is_success(), "Legacy direct take_item should remain one-phase and available.")
	_expect_equal(pile.get_produced_count(), 2, "Direct take_item should retain its existing immediate count contract.")
	_expect_equal(transitions, [Vector2i(0, 1), Vector2i(1, 2)], "Direct take should emit its immediate production transition.")


func _test_command_rolls_back_failed_source_claim() -> void:
	var rejecting_runtime := _make_rejecting_arm_runtime()
	if rejecting_runtime == null:
		return
	var pile := INFINITE_BLOCK_PILE_SCRIPT.new()
	_bind_pile_to_runtime(pile, rejecting_runtime)
	var transitions: Array[Vector2i] = []
	pile.produced_count_changed.connect(
		func(previous_count: int, current_count: int) -> void:
			transitions.append(Vector2i(previous_count, current_count))
	)
	var command := GRAB_DROP_COMMAND_SCRIPT.new()

	var failed = command.execute(rejecting_runtime, pile)
	_expect_equal(
		failed.status,
		GRAB_DROP_RESULT_SCRIPT.Status.OWNERSHIP_CONFLICT,
		"Rejected arm claim should surface ownership conflict."
	)
	_expect_false(rejecting_runtime.arm_has_item, "Rejected source Grab must preserve empty arm state.")
	_expect_equal(pile.get_produced_count(), 0, "Rejected source Grab must roll back prepared pile production.")
	_expect_equal(transitions.size(), 0, "Rejected source Grab must not emit a production transition.")

	var normal_runtime := _make_normal_arm_runtime()
	if normal_runtime == null:
		return
	_bind_pile_to_runtime(pile, normal_runtime)
	var accepted = command.execute(normal_runtime, pile)
	_expect_equal(accepted.status, GRAB_DROP_RESULT_SCRIPT.Status.ACCEPTED, "Same pile should remain usable after rollback.")
	_expect_true(normal_runtime.arm_has_item, "Successful retry should leave arm carrying one block.")
	_expect_true(normal_runtime.carried_item == accepted.item, "Successful retry should expose the exact arm-owned block.")
	_expect_equal(pile.get_produced_count(), 1, "Successful retry should commit one production.")
	_expect_equal(transitions, [Vector2i(0, 1)], "Only successful retry should publish production.")


func _make_rejecting_arm_runtime() -> REJECTING_RUNTIME_SCRIPT:
	var definition := _make_arm_definition(&"rejecting_test_arm")
	if definition == null:
		return null
	var runtime := REJECTING_RUNTIME_SCRIPT.new()
	_expect_true(runtime.configure(definition, Vector2i(2, 2)), "Rejecting arm runtime should configure.")
	return runtime


func _make_normal_arm_runtime() -> VEHICLE_RUNTIME_STATE_SCRIPT:
	var definition := _make_arm_definition(&"normal_test_arm")
	if definition == null:
		return null
	var runtime := VEHICLE_RUNTIME_STATE_SCRIPT.new()
	_expect_true(runtime.configure(definition, Vector2i(2, 2)), "Normal arm runtime should configure.")
	return runtime


func _make_arm_definition(assembly_id: StringName) -> VEHICLE_DEFINITION_SCRIPT:
	var definition := VEHICLE_DEFINITION_SCRIPT.new()
	var configured := definition.configure(
		assembly_id,
		"Source Transaction Test Arm",
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
	_expect_true(configured, "Source transaction arm definition should configure.")
	return definition if configured else null


func _bind_pile_to_runtime(pile: INFINITE_BLOCK_PILE_SCRIPT, runtime: VEHICLE_RUNTIME_STATE_SCRIPT) -> void:
	var cells: Array[Vector2i] = [
		GRAB_DROP_INTERACTION_POLICY_SCRIPT.get_primary_interaction_cell(runtime),
	]
	pile.set_interaction_cells(cells)


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

extends SceneTree

const GROUND_BLOCK_FIELD_SCRIPT := preload("res://scripts/objects/ground_block_field.gd")
const ITEM_TRANSFER_RESULT_SCRIPT := preload("res://scripts/objects/item_transfer_result.gd")
const STANDARD_BLOCK_SCRIPT := preload("res://scripts/objects/standard_block.gd")

var failures: int = 0


func _init() -> void:
	_test_fail_closed_and_policy_contract()
	_test_put_take_and_occupied_contract()
	_test_policy_tightening_releases_ownership()
	_test_reset_releases_ownership()
	_test_cell_interface_is_stable_and_weak()

	if failures == 0:
		print("Ground block field smoke tests passed.")
		quit(0)
		return
	push_error("Ground block field smoke tests failed: %d failure(s)." % failures)
	quit(1)


func _test_fail_closed_and_policy_contract() -> void:
	var field := GROUND_BLOCK_FIELD_SCRIPT.new()
	var allowed_cell := Vector2i(4, 1)
	var rejected_cell := Vector2i(5, 1)
	var block := STANDARD_BLOCK_SCRIPT.create()
	_expect_false(field.is_configured(), "Fresh ground field should start unconfigured.")
	_expect_false(field.is_cell_allowed(allowed_cell), "Unconfigured ground field must fail closed.")
	_expect_true(field.get_cell_interface(allowed_cell) == null, "Unconfigured field must not expose cell interfaces.")
	_expect_equal(
		field.put_item(allowed_cell, block).status,
		ITEM_TRANSFER_RESULT_SCRIPT.Status.INVALID_TARGET,
		"Unconfigured ground field must reject writes."
	)
	_expect_false(block.is_claimed(), "Rejected unconfigured write must not claim the block.")

	field.configure_valid_cells([allowed_cell])
	_expect_true(field.is_configured(), "Configured ground field should report configured state.")
	_expect_true(field.is_cell_allowed(allowed_cell), "Configured allowed cell should be accepted.")
	_expect_false(field.is_cell_allowed(rejected_cell), "Cell outside policy must remain invalid.")
	_expect_true(field.get_cell_interface(rejected_cell) == null, "Policy-excluded cell must not expose an interface.")
	_expect_equal(
		field.put_item(rejected_cell, STANDARD_BLOCK_SCRIPT.create()).status,
		ITEM_TRANSFER_RESULT_SCRIPT.Status.INVALID_TARGET,
		"Policy-excluded cell must reject writes."
	)


func _test_put_take_and_occupied_contract() -> void:
	var field := GROUND_BLOCK_FIELD_SCRIPT.new()
	var cell := Vector2i(4, 1)
	field.configure_valid_cells([cell])
	var first := STANDARD_BLOCK_SCRIPT.create()
	var second := STANDARD_BLOCK_SCRIPT.create()

	var put_first = field.put_item(cell, first)
	_expect_equal(put_first.status, ITEM_TRANSFER_RESULT_SCRIPT.Status.ACCEPTED, "First ground put should succeed.")
	_expect_true(field.has_item(cell), "Ground cell should become occupied.")
	_expect_true(field.get_item(cell) == first, "Ground field should preserve exact block identity.")
	_expect_true(first.is_claimed_by(field), "Ground field should own placed block.")

	var occupied = field.put_item(cell, second)
	_expect_equal(occupied.status, ITEM_TRANSFER_RESULT_SCRIPT.Status.OCCUPIED, "Occupied ground cell should reject second block.")
	_expect_true(field.get_item(cell) == first, "Occupied rejection must preserve original block.")
	_expect_false(second.is_claimed(), "Occupied rejection must not claim rejected block.")

	var taken = field.take_item(cell)
	_expect_equal(taken.status, ITEM_TRANSFER_RESULT_SCRIPT.Status.ACCEPTED, "Ground take should succeed.")
	_expect_true(taken.item == first, "Ground take should return exact placed block.")
	_expect_false(first.is_claimed(), "Ground take should release field ownership.")
	_expect_false(field.has_item(cell), "Ground cell should become empty after take.")

	var empty = field.take_item(cell)
	_expect_equal(empty.status, ITEM_TRANSFER_RESULT_SCRIPT.Status.EMPTY, "Empty ground take should reject as EMPTY.")


func _test_policy_tightening_releases_ownership() -> void:
	var field := GROUND_BLOCK_FIELD_SCRIPT.new()
	var removed_cell := Vector2i(2, 2)
	var retained_cell := Vector2i(3, 2)
	field.configure_valid_cells([removed_cell, retained_cell])
	var removed_block := STANDARD_BLOCK_SCRIPT.create()
	_expect_true(field.put_item(removed_cell, removed_block).is_success(), "Policy fixture should place a block.")
	var old_interface = field.get_cell_interface(removed_cell)
	field.configure_valid_cells([retained_cell])
	_expect_false(field.has_item(removed_cell), "Policy tightening should remove newly invalid ground state.")
	_expect_false(removed_block.is_claimed(), "Policy tightening should release removed block ownership.")
	_expect_true(field.get_cell_interface(removed_cell) == null, "Invalidated cell should no longer expose a field interface.")
	_expect_equal(
		old_interface.put_item(STANDARD_BLOCK_SCRIPT.create()).status,
		ITEM_TRANSFER_RESULT_SCRIPT.Status.INVALID_TARGET,
		"Previously issued interface must respect the tightened field policy."
	)


func _test_reset_releases_ownership() -> void:
	var field := GROUND_BLOCK_FIELD_SCRIPT.new()
	var cell_a := Vector2i(2, 2)
	var cell_b := Vector2i(3, 2)
	field.configure_valid_cells([cell_a, cell_b])
	var a := STANDARD_BLOCK_SCRIPT.create()
	var b := STANDARD_BLOCK_SCRIPT.create()
	_expect_true(field.put_item(cell_a, a).is_success(), "Reset fixture should place block A.")
	_expect_true(field.put_item(cell_b, b).is_success(), "Reset fixture should place block B.")
	field.reset()
	_expect_equal(field.get_occupied_cells().size(), 0, "Reset should clear all occupied ground cells.")
	_expect_false(a.is_claimed(), "Reset should release block A ownership.")
	_expect_false(b.is_claimed(), "Reset should release block B ownership.")


func _test_cell_interface_is_stable_and_weak() -> void:
	var field = GROUND_BLOCK_FIELD_SCRIPT.new()
	var cell := Vector2i(5, 1)
	field.configure_valid_cells([cell])
	var first_interface = field.get_cell_interface(cell)
	var second_interface = field.get_cell_interface(cell)
	_expect_true(first_interface != null, "Ground cell interface should be created.")
	_expect_true(first_interface == second_interface, "Ground cell interface identity should be stable per cell.")
	if first_interface == null:
		return
	_expect_equal(first_interface.get_interaction_cells(), [cell], "Ground interface should expose exactly one interaction cell.")
	_expect_equal(first_interface.get_capacity(), 1, "Ground interface capacity should be one.")
	_expect_false(first_interface.can_take_item(), "Empty ground interface should not be a Grab source.")

	var block := STANDARD_BLOCK_SCRIPT.create()
	_expect_true(first_interface.put_item(block).is_success(), "Ground interface should delegate Drop to field.")
	_expect_true(first_interface.can_take_item(), "Occupied ground interface should become a Grab source.")
	var taken = first_interface.take_item()
	_expect_true(taken.is_success() and taken.item == block, "Ground interface Grab should return exact block.")

	var field_ref: WeakRef = weakref(field)
	field = null
	_expect_true(field_ref.get_ref() == null, "Cell interface must not keep GroundBlockField alive through a strong cycle.")
	var invalid_put = first_interface.put_item(STANDARD_BLOCK_SCRIPT.create())
	_expect_equal(invalid_put.status, ITEM_TRANSFER_RESULT_SCRIPT.Status.INVALID_TARGET, "Orphan cell interface should reject after field lifetime ends.")


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
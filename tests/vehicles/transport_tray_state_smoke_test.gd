extends SceneTree

const TRAY_STATE_SCRIPT := preload("res://scripts/vehicles/transport_tray_state.gd")
const STANDARD_BLOCK_SCRIPT := preload("res://scripts/objects/standard_block.gd")
const STANDARD_BOX_SCRIPT := preload("res://scripts/objects/standard_box.gd")
const TRANSFER_RESULT_SCRIPT := preload("res://scripts/objects/item_transfer_result.gd")

var failures: int = 0
var count_events: Array[Vector2i] = []


func _init() -> void:
	_test_configuration_boundaries()
	_test_configuration_and_inventory_contract()
	_test_full_empty_and_type_rejection()
	_test_cross_receiver_ownership()
	_test_reset_releases_items()

	if failures == 0:
		print("Transport tray state smoke tests passed.")
		quit(0)
		return
	push_error("Transport tray state smoke tests failed: %d failure(s)." % failures)
	quit(1)


func _test_configuration_boundaries() -> void:
	for invalid_capacity in [0, -1]:
		var invalid_tray := TRAY_STATE_SCRIPT.new()
		var configured := bool(_quiet(Callable(invalid_tray, "configure").bind(invalid_capacity)))
		_expect_false(configured, "Tray should reject capacity %d." % invalid_capacity)
		_expect_false(invalid_tray.is_configured(), "Rejected capacity should leave tray unconfigured.")
		_expect_equal(invalid_tray.get_capacity(), 0, "Rejected capacity should preserve default capacity.")

	var tray := TRAY_STATE_SCRIPT.new()
	_expect_true(tray.configure(8), "Tray should accept its first valid configuration.")
	var second_configure := bool(_quiet(Callable(tray, "configure").bind(4)))
	_expect_false(second_configure, "Tray configuration should be immutable after success.")
	_expect_equal(tray.get_capacity(), 8, "Rejected reconfiguration should preserve original capacity.")


func _test_configuration_and_inventory_contract() -> void:
	var tray := TRAY_STATE_SCRIPT.new()
	_expect_true(tray.configure(8), "Tray should configure with capacity eight.")
	_expect_equal(tray.get_capacity(), 8, "Tray capacity should be eight.")
	_expect_equal(tray.get_current_count(), 0, "Tray should start empty.")
	_expect_true(tray.accepts_item_type(STANDARD_BLOCK_SCRIPT.TYPE_ID), "Tray should accept standard blocks.")

	count_events.clear()
	tray.count_changed.connect(_on_count_changed)
	var block := STANDARD_BLOCK_SCRIPT.create()
	var put_result = tray.put_item(block)
	_expect_equal(put_result.status, TRANSFER_RESULT_SCRIPT.Status.ACCEPTED, "Putting a standard block should succeed.")
	_expect_true(tray.contains_item(block), "Tray should own the inserted block.")
	_expect_true(block.is_claimed_by(tray), "Inserted block should be claimed by tray.")
	_expect_equal(tray.get_current_count(), 1, "Successful put should increment count.")
	_expect_equal(count_events, [Vector2i(0, 1)], "Successful put should emit one count event.")

	var take_result = tray.take_item()
	_expect_equal(take_result.status, TRANSFER_RESULT_SCRIPT.Status.ACCEPTED, "Taking from a non-empty tray should succeed.")
	_expect_true(take_result.item == block, "Take should return the inserted block instance.")
	_expect_false(block.is_claimed(), "Taken block should be released from tray ownership.")
	_expect_equal(tray.get_current_count(), 0, "Successful take should decrement count.")
	_expect_equal(count_events, [Vector2i(0, 1), Vector2i(1, 0)], "Successful take should emit the inverse count event.")


func _test_full_empty_and_type_rejection() -> void:
	var tray := TRAY_STATE_SCRIPT.new()
	_expect_true(tray.configure(2), "Small tray should configure.")
	count_events.clear()
	tray.count_changed.connect(_on_count_changed)
	_expect_equal(tray.take_item().status, TRANSFER_RESULT_SCRIPT.Status.EMPTY, "Empty tray should reject take.")
	_expect_true(count_events.is_empty(), "Rejected empty take should emit no count event.")
	_expect_equal(tray.put_item("invalid").status, TRANSFER_RESULT_SCRIPT.Status.TYPE_MISMATCH, "Tray should reject non-standard-block values.")
	_expect_true(count_events.is_empty(), "Rejected wrong type should emit no count event.")
	var first := STANDARD_BLOCK_SCRIPT.create()
	var second := STANDARD_BLOCK_SCRIPT.create()
	var overflow := STANDARD_BLOCK_SCRIPT.create()
	_expect_true(tray.put_item(first).is_success(), "First block should fit.")
	_expect_true(tray.put_item(second).is_success(), "Second block should fit.")
	_expect_equal(tray.get_current_count(), 2, "Tray should reach capacity.")
	var events_before_overflow := count_events.duplicate()
	_expect_equal(tray.put_item(overflow).status, TRANSFER_RESULT_SCRIPT.Status.FULL, "Full tray should reject another block.")
	_expect_equal(tray.get_current_count(), 2, "Rejected overflow should not mutate tray count.")
	_expect_false(overflow.is_claimed(), "Rejected overflow block should remain unclaimed.")
	_expect_equal(count_events, events_before_overflow, "Rejected overflow should emit no count event.")


func _test_cross_receiver_ownership() -> void:
	var tray := TRAY_STATE_SCRIPT.new()
	_expect_true(tray.configure(8), "Tray should configure for ownership test.")
	var box := STANDARD_BOX_SCRIPT.new()
	box.capacity = 8
	box.initial_count = 0
	box.reset()
	var block := STANDARD_BLOCK_SCRIPT.create()
	_expect_true(box.put_item(block).is_success(), "Box should claim the block first.")
	count_events.clear()
	tray.count_changed.connect(_on_count_changed)
	_expect_equal(tray.put_item(block).status, TRANSFER_RESULT_SCRIPT.Status.ALREADY_CONTAINED, "Tray should reject a block already owned by another receiver.")
	_expect_equal(tray.get_current_count(), 0, "Cross-receiver rejection should be atomic.")
	_expect_true(box.contains_item(block), "Original receiver should retain ownership.")
	_expect_true(count_events.is_empty(), "Cross-receiver rejection should emit no count event.")


func _test_reset_releases_items() -> void:
	var tray := TRAY_STATE_SCRIPT.new()
	_expect_true(tray.configure(8), "Tray should configure for reset test.")
	var first := STANDARD_BLOCK_SCRIPT.create()
	var second := STANDARD_BLOCK_SCRIPT.create()
	tray.put_item(first)
	tray.put_item(second)
	count_events.clear()
	tray.count_changed.connect(_on_count_changed)
	tray.reset()
	_expect_equal(tray.get_current_count(), 0, "Reset should clear tray inventory.")
	_expect_false(first.is_claimed(), "Reset should release first block ownership.")
	_expect_false(second.is_claimed(), "Reset should release second block ownership.")
	_expect_equal(count_events, [Vector2i(2, 0)], "Reset should emit one aggregate count event.")
	count_events.clear()
	tray.reset()
	_expect_true(count_events.is_empty(), "Resetting an empty tray should be an event-free no-op.")


func _quiet(callback: Callable) -> Variant:
	var previous_print_error_messages := Engine.print_error_messages
	Engine.print_error_messages = false
	var result: Variant = callback.call()
	Engine.print_error_messages = previous_print_error_messages
	return result


func _on_count_changed(previous_count: int, current_count: int) -> void:
	count_events.append(Vector2i(previous_count, current_count))


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

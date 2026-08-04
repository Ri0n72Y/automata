extends SceneTree

var failures: int = 0


func _init() -> void:
	_test_standard_block_identity()
	_test_infinite_pile_contract()
	_test_standard_box_contract()
	_test_box_reset_and_signals()

	if failures == 0:
		print("Object domain smoke tests passed.")
		quit(0)
		return
	push_error("Object domain smoke tests failed: %d failure(s)." % failures)
	quit(1)


func _test_standard_block_identity() -> void:
	var first := StandardBlock.create()
	var second := StandardBlock.create()
	_expect_true(first.is_valid(), "Created standard block should be valid.")
	_expect_true(second.is_valid(), "Second standard block should be valid.")
	_expect_true(first.block_id != second.block_id, "Each standard block should have a distinct id.")
	_expect_equal(first.item_type, StandardBlock.TYPE_ID, "Standard block type should be stable.")


func _test_infinite_pile_contract() -> void:
	var pile := InfiniteBlockPile.new()
	var first := pile.take_item()
	var second := pile.take_item()
	_expect_true(first.is_success(), "Infinite pile should provide a block.")
	_expect_true(second.is_success(), "Infinite pile should remain available.")
	_expect_true(first.item != second.item, "Infinite pile should produce distinct instances.")
	_expect_equal(pile.produced_count, 2, "Pile should expose produced count for observation.")
	var rejected := pile.put_item(first.item)
	_expect_equal(rejected.status, ItemTransferResult.Status.INVALID_TARGET, "Pile should reject put operations.")
	pile.reset()
	_expect_equal(pile.produced_count, 0, "Pile reset should clear produced count without creating stock.")
	_expect_true(pile.take_item().is_success(), "Pile should still produce after reset.")


func _test_standard_box_contract() -> void:
	var box := StandardBox.new()
	_expect_equal(box.get_capacity(), 8, "Standard box capacity should be eight.")
	_expect_equal(box.get_current_count(), 3, "Standard box should start at three items.")
	var block := StandardBlock.create()
	_expect_true(box.put_item(block).is_success(), "Box should accept a standard block.")
	_expect_equal(box.get_current_count(), 4, "Accepted put should increment count.")
	_expect_equal(
		box.put_item(block).status,
		ItemTransferResult.Status.ALREADY_CONTAINED,
		"Box should reject the same block instance twice."
	)
	_expect_equal(box.get_current_count(), 4, "Rejected duplicate should preserve count.")
	_expect_equal(
		box.put_item(Node.new()).status,
		ItemTransferResult.Status.TYPE_MISMATCH,
		"Box should reject non-standard items."
	)
	while not box.is_full():
		_expect_true(box.put_item(StandardBlock.create()).is_success(), "Box should accept until full.")
	_expect_equal(box.get_current_count(), 8, "Box count should never exceed capacity.")
	_expect_equal(
		box.put_item(StandardBlock.create()).status,
		ItemTransferResult.Status.FULL,
		"Full box should reject additional blocks."
	)
	var taken := box.take_item()
	_expect_true(taken.is_success(), "Non-empty box should provide an item.")
	_expect_true(taken.item is StandardBlock, "Taken item should retain standard block type.")


func _test_box_reset_and_signals() -> void:
	var box := StandardBox.new()
	var transitions: Array[Vector2i] = []
	box.count_changed.connect(func(previous_count: int, current_count: int) -> void:
		transitions.append(Vector2i(previous_count, current_count))
	)
	var block := StandardBlock.create()
	box.put_item(block)
	box.put_item(block)
	box.reset()
	_expect_equal(transitions.size(), 2, "Only successful mutation and changing reset should emit.")
	_expect_equal(transitions[0], Vector2i(3, 4), "Put signal should expose previous and current count.")
	_expect_equal(transitions[1], Vector2i(4, 3), "Reset signal should restore initial count.")
	_expect_equal(box.get_current_count(), 3, "Reset should restore three of eight.")


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

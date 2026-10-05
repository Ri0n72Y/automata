extends SceneTree

var failures: int = 0


func _init() -> void:
	_test_standard_block_identity()
	_test_source_interface_contract()
	_test_standard_box_contract()
	_test_cross_receiver_ownership()
	_test_receiver_lifetime_releases_ownership()
	_test_box_reset_and_signals()

	if failures == 0:
		print("Object domain smoke tests passed.")
		quit(0)
		return
	push_error("Object domain smoke tests failed: %d failure(s)." % failures)
	quit(1)


func _test_standard_block_identity() -> void:
	var invalid := StandardBlock.new()
	var first := StandardBlock.create()
	var second := StandardBlock.create()
	_expect_false(invalid.is_valid(), "Directly constructed standard block should remain invalid.")
	_expect_true(first.is_valid() and second.is_valid(), "Created standard blocks should be valid.")
	_expect_true(first.get_block_id() != second.get_block_id(), "Each standard block should have a distinct id.")
	_expect_equal(first.get_item_type(), StandardBlock.TYPE_ID, "Standard block type should be stable.")
	_expect_false(first.is_claimed(), "Newly created block should not have an owner.")


func _test_source_interface_contract() -> void:
	var source: ItemSourceInterface = InfiniteBlockPile.new()
	var cells: Array[Vector2i] = [Vector2i(1, 2), Vector2i(2, 2)]
	source.set_interaction_cells(cells)
	cells.clear()
	_expect_equal(source.get_output_item_type(), StandardBlock.TYPE_ID, "Pile exposes the standard block type.")
	_expect_true(source.is_infinite() and source.is_available(), "Pile is an available infinite source.")
	_expect_equal(source.get_interaction_cells().size(), 2, "Source retains a defensive copy of interaction cells.")
	var first := source.take_item()
	var second := source.take_item()
	_expect_true(first.is_success() and second.is_success(), "Infinite pile should keep producing blocks.")
	_expect_true(first.item != second.item, "Infinite pile should produce distinct instances.")
	_expect_equal(
		(source as InfiniteBlockPile).put_item(first.item).status,
		ItemTransferResult.Status.INVALID_TARGET,
		"Pile should reject put operations."
	)
	source.reset()
	_expect_true(source.take_item().is_success(), "Pile should still produce after Reset.")


func _test_standard_box_contract() -> void:
	var receiver: ItemReceiverInterface = StandardBox.new()
	var box := receiver as StandardBox
	var transitions: Array[Vector2i] = []
	box.count_changed.connect(func(previous_count: int, current_count: int) -> void:
		transitions.append(Vector2i(previous_count, current_count))
	)
	var cells: Array[Vector2i] = [Vector2i(8, 4)]
	receiver.set_interaction_cells(cells)
	cells.clear()
	_expect_true(receiver.get_accepted_item_types().has(StandardBlock.TYPE_ID), "Standard box advertises its item type.")
	_expect_equal(receiver.get_interaction_cells().size(), 1, "Receiver retains interaction cells.")
	_expect_equal(receiver.get_capacity(), 8, "Standard box capacity should be eight.")
	_expect_equal(receiver.get_current_count(), 3, "Standard box should start at three items.")
	_expect_equal(receiver.put_item(StandardBlock.new()).status, ItemTransferResult.Status.TYPE_MISMATCH, "Invalid block is rejected.")
	_expect_equal(receiver.put_item({"type": "other"}).status, ItemTransferResult.Status.TYPE_MISMATCH, "Wrong type is rejected.")
	_expect_equal(transitions.size(), 0, "Type rejection should not emit count changes.")

	var block := StandardBlock.create()
	_expect_true(receiver.put_item(block).is_success(), "Box should accept a standard block.")
	_expect_true(block.is_claimed(), "Accepted block should be claimed by the receiver.")
	_expect_equal(receiver.get_current_count(), 4, "Accepted put should increment count.")
	_expect_equal(receiver.put_item(block).status, ItemTransferResult.Status.ALREADY_CONTAINED, "Box rejects duplicate block instance.")
	_expect_equal(transitions.size(), 1, "Duplicate rejection should not emit.")

	while receiver.get_current_count() < receiver.get_capacity():
		_expect_true(receiver.put_item(StandardBlock.create()).is_success(), "Box should accept until full.")
	var transitions_at_full := transitions.size()
	_expect_equal(receiver.put_item(StandardBlock.create()).status, ItemTransferResult.Status.FULL, "Full box rejects additional blocks.")
	_expect_equal(receiver.get_current_count(), 8, "Full rejection preserves capacity.")
	_expect_equal(transitions.size(), transitions_at_full, "Full rejection should not emit.")

	while receiver.get_current_count() > 0:
		var taken := receiver.take_item()
		_expect_true(taken.is_success(), "Non-empty box should provide an item.")
		_expect_false(taken.item.is_claimed(), "Taken item should be released from receiver ownership.")
	var transitions_at_empty := transitions.size()
	_expect_equal(receiver.take_item().status, ItemTransferResult.Status.EMPTY, "Empty box rejects take.")
	_expect_equal(transitions.size(), transitions_at_empty, "Empty rejection should not emit.")


func _test_cross_receiver_ownership() -> void:
	var first_box := StandardBox.new()
	var second_box := StandardBox.new()
	var block := StandardBlock.create()
	_expect_true(first_box.put_item(block).is_success(), "First receiver should claim the block.")
	_expect_equal(second_box.put_item(block).status, ItemTransferResult.Status.ALREADY_CONTAINED, "Second receiver rejects claimed block.")
	var taken := first_box.take_item()
	_expect_true(taken.is_success() and taken.item == block, "First receiver releases the same block on take.")
	_expect_true(second_box.put_item(block).is_success(), "Released block should be transferable.")


func _test_receiver_lifetime_releases_ownership() -> void:
	var block := StandardBlock.create()
	var receiver: StandardBox = StandardBox.new()
	_expect_true(receiver.put_item(block).is_success(), "Receiver should initially claim the block.")
	var receiver_ref: WeakRef = weakref(receiver)
	receiver = null
	_expect_true(receiver_ref.get_ref() == null, "Receiver should be released with no strong references.")
	_expect_false(block.is_claimed(), "Destroyed receiver should not leave a stale claim.")
	_expect_true(StandardBox.new().put_item(block).is_success(), "Block should be reusable after receiver destruction.")


func _test_box_reset_and_signals() -> void:
	var box := StandardBox.new()
	var transitions: Array[Vector2i] = []
	box.count_changed.connect(func(previous_count: int, current_count: int) -> void:
		transitions.append(Vector2i(previous_count, current_count))
	)
	var block := StandardBlock.create()
	box.put_item(block)
	box.reset()
	_expect_equal(transitions, [Vector2i(3, 4), Vector2i(4, 3)], "Put and changing Reset should emit once each.")
	_expect_equal(box.get_current_count(), 3, "Reset should restore three of eight.")
	_expect_false(block.is_claimed(), "Reset should release discarded item ownership.")
	box.reset()
	_expect_equal(transitions.size(), 2, "Reset at initial count should be a no-op.")


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

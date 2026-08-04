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
	_expect_true(first.is_valid(), "Created standard block should be valid.")
	_expect_true(second.is_valid(), "Second standard block should be valid.")
	_expect_true(
		first.get_block_id() != second.get_block_id(),
		"Each standard block should have a distinct id."
	)
	_expect_equal(
		first.get_item_type(),
		StandardBlock.TYPE_ID,
		"Standard block type should be stable."
	)
	_expect_false(first.is_claimed(), "Newly created block should not have an owner.")


func _test_source_interface_contract() -> void:
	var source: ItemSourceInterface = InfiniteBlockPile.new()
	var pile := source as InfiniteBlockPile
	var transitions: Array[Vector2i] = []
	pile.produced_count_changed.connect(func(previous_count: int, current_count: int) -> void:
		transitions.append(Vector2i(previous_count, current_count))
	)
	var cells: Array[Vector2i] = [Vector2i(1, 2), Vector2i(2, 2)]
	source.set_interaction_cells(cells)
	cells.clear()
	_expect_equal(
		source.get_output_item_type(),
		StandardBlock.TYPE_ID,
		"Pile source should expose the standard block type."
	)
	_expect_true(source.is_infinite(), "Pile source should identify itself as infinite.")
	_expect_equal(
		source.get_interaction_cells().size(),
		2,
		"Source should retain a defensive copy of interaction cells."
	)
	var first := source.take_item()
	var second := source.take_item()
	_expect_true(first.is_success(), "Infinite pile should provide a block.")
	_expect_true(second.is_success(), "Infinite pile should remain available.")
	_expect_true(first.item != second.item, "Infinite pile should produce distinct instances.")
	_expect_equal(pile.get_produced_count(), 2, "Pile should expose produced count for observation.")
	_expect_equal(transitions.size(), 2, "Each successful take should emit once.")
	_expect_equal(transitions[0], Vector2i(0, 1), "First take transition should be 0 to 1.")
	_expect_equal(transitions[1], Vector2i(1, 2), "Second take transition should be 1 to 2.")
	var rejected := pile.put_item(first.item)
	_expect_equal(
		rejected.status,
		ItemTransferResult.Status.INVALID_TARGET,
		"Pile should reject put operations."
	)
	_expect_equal(transitions.size(), 2, "Rejected put should not emit a production event.")
	source.reset()
	_expect_equal(pile.get_produced_count(), 0, "Pile reset should clear produced count.")
	_expect_equal(transitions.size(), 3, "Changing reset should emit once.")
	_expect_equal(transitions[2], Vector2i(2, 0), "Pile reset transition should be 2 to 0.")
	source.reset()
	_expect_equal(transitions.size(), 3, "No-op reset should not emit.")
	_expect_true(source.take_item().is_success(), "Pile should still produce after reset.")


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
	_expect_true(
		receiver.get_accepted_item_types().has(StandardBlock.TYPE_ID),
		"Standard box should advertise the accepted item type."
	)
	_expect_equal(receiver.get_interaction_cells().size(), 1, "Receiver should retain interaction cells.")
	_expect_equal(receiver.get_capacity(), 8, "Standard box capacity should be eight.")
	_expect_equal(receiver.get_current_count(), 3, "Standard box should start at three items.")
	_expect_equal(
		receiver.put_item(StandardBlock.new()).status,
		ItemTransferResult.Status.TYPE_MISMATCH,
		"Receiver should reject an invalid standard block."
	)
	_expect_equal(
		receiver.put_item({"type": "other"}).status,
		ItemTransferResult.Status.TYPE_MISMATCH,
		"Receiver should reject non-standard items."
	)
	_expect_equal(transitions.size(), 0, "Type rejection should not emit count changes.")

	var block := StandardBlock.create()
	_expect_true(receiver.put_item(block).is_success(), "Box should accept a standard block.")
	_expect_true(block.is_claimed(), "Accepted block should be claimed by the receiver.")
	_expect_equal(receiver.get_current_count(), 4, "Accepted put should increment count.")
	_expect_equal(
		receiver.put_item(block).status,
		ItemTransferResult.Status.ALREADY_CONTAINED,
		"Box should reject the same block instance twice."
	)
	_expect_equal(transitions.size(), 1, "Duplicate rejection should not emit.")

	while receiver.get_current_count() < receiver.get_capacity():
		_expect_true(
			receiver.put_item(StandardBlock.create()).is_success(),
			"Box should accept until full."
		)
	var transitions_at_full := transitions.size()
	_expect_equal(receiver.get_current_count(), 8, "Box count should never exceed capacity.")
	_expect_equal(
		receiver.put_item(StandardBlock.create()).status,
		ItemTransferResult.Status.FULL,
		"Full box should reject additional blocks."
	)
	_expect_equal(receiver.get_current_count(), 8, "Full rejection should preserve count.")
	_expect_equal(transitions.size(), transitions_at_full, "Full rejection should not emit.")

	while receiver.get_current_count() > 0:
		var taken := receiver.take_item()
		_expect_true(taken.is_success(), "Non-empty box should provide an item.")
		_expect_false(taken.item.is_claimed(), "Taken item should be released from receiver ownership.")
	var transitions_at_empty := transitions.size()
	_expect_equal(
		receiver.take_item().status,
		ItemTransferResult.Status.EMPTY,
		"Empty box should reject take operations."
	)
	_expect_equal(receiver.get_current_count(), 0, "Empty rejection should preserve count.")
	_expect_equal(transitions.size(), transitions_at_empty, "Empty rejection should not emit.")


func _test_cross_receiver_ownership() -> void:
	var first_box := StandardBox.new()
	var second_box := StandardBox.new()
	var block := StandardBlock.create()
	_expect_true(first_box.put_item(block).is_success(), "First receiver should claim the block.")
	_expect_equal(
		second_box.put_item(block).status,
		ItemTransferResult.Status.ALREADY_CONTAINED,
		"A second receiver should reject an already claimed block."
	)
	var taken := first_box.take_item()
	_expect_true(taken.is_success(), "First receiver should release the claimed block on take.")
	_expect_true(taken.item == block, "The appended block should be the first item taken back.")
	_expect_true(second_box.put_item(block).is_success(), "Released block should be transferable.")


func _test_receiver_lifetime_releases_ownership() -> void:
	var block := StandardBlock.create()
	var receiver: StandardBox = StandardBox.new()
	_expect_true(receiver.put_item(block).is_success(), "Receiver should initially claim the block.")
	var receiver_ref: WeakRef = weakref(receiver)
	receiver = null
	_expect_true(receiver_ref.get_ref() == null, "Receiver should be released with no strong references.")
	_expect_false(block.is_claimed(), "A destroyed receiver should not leave a stale claim.")
	var replacement := StandardBox.new()
	_expect_true(replacement.put_item(block).is_success(), "Block should be reusable after receiver destruction.")


func _test_box_reset_and_signals() -> void:
	var box := StandardBox.new()
	var other_box := StandardBox.new()
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
	_expect_false(block.is_claimed(), "Reset should release ownership of discarded items.")
	_expect_true(other_box.put_item(block).is_success(), "Released pre-reset block should be reusable.")
	box.reset()
	_expect_equal(transitions.size(), 2, "Reset at the initial count should not emit a count change.")


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

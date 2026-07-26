extends SceneTree

const VEHICLE_DEFINITION_SCRIPT := preload("res://scripts/vehicles/vehicle_definition.gd")
const VEHICLE_RUNTIME_STATE_SCRIPT := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const VEHICLE_ACTOR_SCRIPT := preload("res://scripts/vehicles/vehicle_actor.gd")

var failures: int = 0


func _init() -> void:
	_test_arm_vehicle_definition_and_runtime()
	_test_transport_vehicle_definition_and_runtime()
	_test_runtime_reset_and_command_queue()
	_test_unconfigured_definition_is_rejected()
	_test_actor_definition_mismatch_is_rejected()

	if failures == 0:
		print("Vehicle model smoke tests passed.")
		quit(0)
		return
	push_error("Vehicle model smoke tests failed: %d failure(s)." % failures)
	quit(1)


func _test_arm_vehicle_definition_and_runtime() -> void:
	var definition := _create_arm_definition()
	_expect_true(definition != null, "Arm vehicle definition should configure.")
	if definition == null:
		return
	_expect_equal(definition.footprint, Vector2i(2, 2), "Arm vehicle should occupy 2x2 cells.")
	_expect_true(definition.can_move(), "Arm vehicle should expose can_move.")
	_expect_true(
		definition.has_capability(VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_GRAB),
		"Arm vehicle should expose can_grab."
	)
	_expect_float_approx(definition.total_weight, 18.0, "Arm preset weight should be stable.")

	var runtime := VEHICLE_RUNTIME_STATE_SCRIPT.new()
	_expect_true(
		runtime.configure(
			definition,
			Vector2i(2, 2),
			VEHICLE_RUNTIME_STATE_SCRIPT.Facing.EAST
		),
		"Arm runtime should configure."
	)
	_expect_true(runtime.definition == definition, "Runtime should retain its configured definition.")
	_expect_true(runtime.set_arm_has_item(true), "Arm runtime should accept carried-item state.")
	_expect_true(runtime.arm_has_item, "Arm runtime should record carried-item state.")
	_expect_float_approx(
		runtime.get_effective_speed(),
		definition.base_speed * 0.25,
		"Arm carrying speed should use the Scene 01 quarter-speed rule."
	)
	_expect_false(runtime.set_tray_count(1), "Arm vehicle should reject tray state updates.")
	_expect_equal(runtime.tray_count, 0, "Rejected tray updates should not mutate arm runtime state.")


func _test_transport_vehicle_definition_and_runtime() -> void:
	var definition := _create_transport_definition()
	_expect_true(definition != null, "Transport vehicle definition should configure.")
	if definition == null:
		return
	_expect_equal(definition.footprint, Vector2i(2, 2), "Transport vehicle should occupy 2x2 cells.")
	_expect_true(definition.can_move(), "Transport vehicle should expose can_move.")
	_expect_true(
		definition.has_capability(VEHICLE_DEFINITION_SCRIPT.CAPABILITY_HAS_TRAY),
		"Transport vehicle should expose has_tray."
	)
	_expect_equal(definition.tray_capacity, 8, "Transport tray capacity should be eight.")

	var runtime := VEHICLE_RUNTIME_STATE_SCRIPT.new()
	_expect_true(
		runtime.configure(
			definition,
			Vector2i(7, 4),
			VEHICLE_RUNTIME_STATE_SCRIPT.Facing.WEST
		),
		"Transport runtime should configure."
	)
	_expect_true(runtime.set_tray_count(5), "Transport runtime should accept valid tray counts.")
	_expect_equal(runtime.tray_count, 5, "Transport runtime should record tray count.")
	_expect_false(runtime.set_tray_count(9), "Transport runtime should reject counts above capacity.")
	_expect_equal(runtime.tray_count, 5, "Rejected tray updates should preserve the previous value.")
	_expect_false(runtime.set_arm_has_item(true), "Transport vehicle should reject arm state updates.")
	_expect_false(runtime.arm_has_item, "Rejected arm updates should not mutate transport runtime state.")


func _test_runtime_reset_and_command_queue() -> void:
	var definition := _create_arm_definition()
	if definition == null:
		failures += 1
		return
	var runtime := VEHICLE_RUNTIME_STATE_SCRIPT.new()
	if not runtime.configure(definition, Vector2i(3, 3)):
		failures += 1
		return

	runtime.anchor_cell = Vector2i(5, 4)
	runtime.motion_state = VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.MOVING
	runtime.set_arm_has_item(true)
	runtime.enqueue_command({"type": "MoveTo", "target": Vector2i(5, 4)})
	_expect_equal(runtime.command_queue.size(), 1, "Runtime should store queued commands.")

	runtime.reset()
	_expect_equal(runtime.anchor_cell, Vector2i(3, 3), "Reset should restore the initial anchor cell.")
	_expect_equal(
		runtime.motion_state,
		VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.WAITING,
		"Reset should restore Waiting state."
	)
	_expect_false(runtime.arm_has_item, "Reset should clear carried items.")
	_expect_equal(runtime.tray_count, 0, "Reset should clear tray state.")
	_expect_equal(runtime.command_queue.size(), 0, "Reset should clear queued commands.")


func _test_unconfigured_definition_is_rejected() -> void:
	var definition := VEHICLE_DEFINITION_SCRIPT.new()
	var runtime := VEHICLE_RUNTIME_STATE_SCRIPT.new()
	_expect_false(
		runtime.configure(definition, Vector2i.ZERO),
		"Runtime should reject an unconfigured definition."
	)
	_expect_true(runtime.definition == null, "Rejected configuration should not bind a definition.")


func _test_actor_definition_mismatch_is_rejected() -> void:
	var arm_definition := _create_arm_definition()
	var transport_definition := _create_transport_definition()
	if arm_definition == null or transport_definition == null:
		failures += 1
		return

	var runtime := VEHICLE_RUNTIME_STATE_SCRIPT.new()
	if not runtime.configure(arm_definition, Vector2i.ZERO):
		failures += 1
		return

	var actor := VEHICLE_ACTOR_SCRIPT.new()
	var controller_stub := Node.new()
	_expect_false(
		actor.configure(transport_definition, runtime, controller_stub, 1.0),
		"Actor should reject a runtime bound to another definition."
	)
	actor.free()
	controller_stub.free()


func _create_arm_definition():
	var definition := VEHICLE_DEFINITION_SCRIPT.new()
	if not definition.configure(
		&"arm_vehicle",
		"Arm Vehicle",
		VEHICLE_DEFINITION_SCRIPT.VehicleKind.ARM,
		Vector2i(2, 2),
		2.0,
		18.0,
		20.0,
		30.0,
		PackedStringArray([
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_MOVE,
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_GRAB,
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_CARRY,
		]),
		0.25,
		0
	):
		return null
	return definition


func _create_transport_definition():
	var definition := VEHICLE_DEFINITION_SCRIPT.new()
	if not definition.configure(
		&"transport_vehicle",
		"Transport Vehicle",
		VEHICLE_DEFINITION_SCRIPT.VehicleKind.TRANSPORT,
		Vector2i(2, 2),
		2.4,
		16.0,
		24.0,
		36.0,
		PackedStringArray([
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_MOVE,
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_CARRY,
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_HAS_TRAY,
		]),
		1.0,
		8
	):
		return null
	return definition


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	failures += 1
	push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])


func _expect_float_approx(actual: float, expected: float, message: String) -> void:
	if is_equal_approx(actual, expected):
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

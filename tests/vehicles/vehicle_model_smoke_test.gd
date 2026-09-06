extends SceneTree

const VEHICLE_DEFINITION_SCRIPT := preload("res://scripts/vehicles/vehicle_definition.gd")
const VEHICLE_RUNTIME_STATE_SCRIPT := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const VEHICLE_ACTOR_SCRIPT := preload("res://scripts/vehicles/vehicle_actor.gd")
const STANDARD_BLOCK_SCRIPT := preload("res://scripts/objects/standard_block.gd")

var failures: int = 0


func _init() -> void:
	_test_arm_vehicle_definition_and_runtime()
	_test_transport_vehicle_definition_and_runtime()
	_test_runtime_reset()
	_test_unconfigured_definition_is_rejected()
	_test_actor_definition_mismatch_is_rejected()

	if failures == 0:
		print("Vehicle model smoke tests passed.")
		quit(0)
		return
	push_error("Vehicle model smoke tests failed: %d failure(s)." % failures)
	quit(1)


func _test_arm_vehicle_definition_and_runtime() -> void:
	var definition: VehicleDefinition = _create_arm_definition()
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
		runtime.configure(definition, Vector2i(2, 2), VEHICLE_RUNTIME_STATE_SCRIPT.Facing.EAST),
		"Arm runtime should configure."
	)
	var block := STANDARD_BLOCK_SCRIPT.create()
	_expect_true(runtime.claim_carried_item(block), "Arm runtime should claim a real carried block.")
	_expect_true(runtime.arm_has_item and runtime.carried_item == block, "Arm should expose the claimed block.")
	_expect_float_approx(
		runtime.get_effective_speed(),
		definition.base_speed * 0.25,
		"Arm carrying speed should use the Scene 01 quarter-speed rule."
	)
	_expect_true(runtime.tray_state == null and runtime.tray_count == 0, "Arm should not own tray state.")


func _test_transport_vehicle_definition_and_runtime() -> void:
	var definition: VehicleDefinition = _create_transport_definition()
	_expect_true(definition != null, "Transport vehicle definition should configure.")
	if definition == null:
		return
	_expect_equal(definition.footprint, Vector2i(2, 2), "Transport vehicle should occupy 2x2 cells.")
	_expect_true(definition.can_move(), "Transport vehicle should expose can_move.")
	_expect_true(
		definition.has_capability(VEHICLE_DEFINITION_SCRIPT.CAPABILITY_HAS_TRAY),
		"Transport vehicle should expose has_tray."
	)

	var runtime := VEHICLE_RUNTIME_STATE_SCRIPT.new()
	_expect_true(
		runtime.configure(definition, Vector2i(7, 4), VEHICLE_RUNTIME_STATE_SCRIPT.Facing.WEST),
		"Transport runtime should configure."
	)
	_expect_true(runtime.tray_state != null, "Transport runtime should own tray state.")
	if runtime.tray_state != null:
		for _index in range(5):
			_expect_true(
				runtime.tray_state.put_item(STANDARD_BLOCK_SCRIPT.create()).is_success(),
				"Transport tray should accept real blocks."
			)
	_expect_equal(runtime.tray_count, 5, "Transport tray_count should derive from real inventory.")
	_expect_false(
		runtime.claim_carried_item(STANDARD_BLOCK_SCRIPT.create()),
		"Transport vehicle should reject arm cargo."
	)


func _test_runtime_reset() -> void:
	var definition: VehicleDefinition = _create_arm_definition()
	if definition == null:
		failures += 1
		return
	var runtime := VEHICLE_RUNTIME_STATE_SCRIPT.new()
	if not runtime.configure(definition, Vector2i(3, 3)):
		failures += 1
		return

	var block := STANDARD_BLOCK_SCRIPT.create()
	runtime.anchor_cell = Vector2i(5, 4)
	runtime.motion_state = VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.BLOCKED
	_expect_true(runtime.claim_carried_item(block), "Reset fixture should carry one block.")
	runtime.reset()
	_expect_equal(runtime.anchor_cell, Vector2i(3, 3), "Reset should restore the initial anchor cell.")
	_expect_equal(runtime.motion_state, VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.WAITING, "Reset should restore Waiting state.")
	_expect_false(runtime.arm_has_item, "Reset should clear carried items.")
	_expect_false(block.is_claimed(), "Reset should release carried block ownership.")


func _test_unconfigured_definition_is_rejected() -> void:
	var definition := VEHICLE_DEFINITION_SCRIPT.new()
	var runtime := VEHICLE_RUNTIME_STATE_SCRIPT.new()
	var configured := bool(_call_with_expected_errors_suppressed(
		Callable(runtime, "configure").bind(definition, Vector2i.ZERO)
	))
	_expect_false(configured, "Runtime should reject an unconfigured definition.")
	_expect_true(runtime.definition == null, "Rejected configuration should not bind a definition.")


func _test_actor_definition_mismatch_is_rejected() -> void:
	var arm_definition: VehicleDefinition = _create_arm_definition()
	var transport_definition: VehicleDefinition = _create_transport_definition()
	if arm_definition == null or transport_definition == null:
		failures += 1
		return
	var runtime := VEHICLE_RUNTIME_STATE_SCRIPT.new()
	if not runtime.configure(arm_definition, Vector2i.ZERO):
		failures += 1
		return
	var actor := VEHICLE_ACTOR_SCRIPT.new()
	var controller_stub := Node.new()
	var configured := bool(_call_with_expected_errors_suppressed(
		Callable(actor, "configure").bind(transport_definition, runtime, controller_stub, 1.0)
	))
	_expect_false(configured, "Actor should reject a runtime bound to another definition.")
	actor.free()
	controller_stub.free()


func _create_arm_definition() -> VehicleDefinition:
	var definition := VEHICLE_DEFINITION_SCRIPT.new()
	if not definition.configure(
		&"arm_vehicle", "Arm Vehicle", VEHICLE_DEFINITION_SCRIPT.VehicleKind.ARM,
		Vector2i(2, 2), 2.0, 18.0, 20.0, 30.0,
		PackedStringArray([
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_MOVE,
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_GRAB,
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_CARRY,
		]),
		0.25, 0
	):
		return null
	return definition


func _create_transport_definition() -> VehicleDefinition:
	var definition := VEHICLE_DEFINITION_SCRIPT.new()
	if not definition.configure(
		&"transport_vehicle", "Transport Vehicle", VEHICLE_DEFINITION_SCRIPT.VehicleKind.TRANSPORT,
		Vector2i(2, 2), 2.4, 16.0, 24.0, 36.0,
		PackedStringArray([
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_MOVE,
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_CARRY,
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_HAS_TRAY,
		]),
		1.0, 8
	):
		return null
	return definition


func _call_with_expected_errors_suppressed(callback: Callable) -> Variant:
	var previous_print_error_messages := Engine.print_error_messages
	Engine.print_error_messages = false
	var result: Variant = callback.call()
	Engine.print_error_messages = previous_print_error_messages
	return result


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

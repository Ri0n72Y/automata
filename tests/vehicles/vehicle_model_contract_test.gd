extends SceneTree

const DEFINITION := preload("res://scripts/vehicles/vehicle_definition.gd")
const RUNTIME := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const ACTOR := preload("res://scripts/vehicles/vehicle_actor.gd")
const CONTRACT := preload("res://tests/support/contract_test.gd")

var test := CONTRACT.new()


func _init() -> void:
	_test_preset_matrix()
	_test_runtime_capability_matrix()
	_test_runtime_reset_contract()
	_test_invalid_configuration_boundaries()
	test.finish(self, "Vehicle model contract tests")


func _test_preset_matrix() -> void:
	var cases: Array[Dictionary] = [
		{
			"name": "arm",
			"definition": _arm_definition(),
			"kind": DEFINITION.VehicleKind.ARM,
			"footprint": Vector2i(2, 2),
			"speed": 2.0,
			"weight": 18.0,
			"tray_capacity": 0,
			"required": [DEFINITION.CAPABILITY_CAN_MOVE, DEFINITION.CAPABILITY_CAN_GRAB, DEFINITION.CAPABILITY_CAN_CARRY],
			"forbidden": [DEFINITION.CAPABILITY_HAS_TRAY],
		},
		{
			"name": "transport",
			"definition": _transport_definition(),
			"kind": DEFINITION.VehicleKind.TRANSPORT,
			"footprint": Vector2i(2, 2),
			"speed": 2.4,
			"weight": 16.0,
			"tray_capacity": 8,
			"required": [DEFINITION.CAPABILITY_CAN_MOVE, DEFINITION.CAPABILITY_CAN_CARRY, DEFINITION.CAPABILITY_HAS_TRAY],
			"forbidden": [DEFINITION.CAPABILITY_CAN_GRAB],
		},
	]
	for case in cases:
		var definition = case["definition"]
		test.expect_true(definition != null, "%s definition should configure." % case["name"])
		if definition == null:
			continue
		test.expect_equal(definition.vehicle_kind, case["kind"], "%s kind." % case["name"])
		test.expect_equal(definition.footprint, case["footprint"], "%s footprint." % case["name"])
		test.expect_float_approx(definition.base_speed, case["speed"], "%s speed." % case["name"])
		test.expect_float_approx(definition.total_weight, case["weight"], "%s weight." % case["name"])
		test.expect_equal(definition.tray_capacity, case["tray_capacity"], "%s tray capacity." % case["name"])
		for capability in case["required"]:
			test.expect_true(definition.has_capability(capability), "%s should expose %s." % [case["name"], capability])
		for capability in case["forbidden"]:
			test.expect_false(definition.has_capability(capability), "%s should not expose %s." % [case["name"], capability])


func _test_runtime_capability_matrix() -> void:
	var arm_definition = _arm_definition()
	var transport_definition = _transport_definition()
	var arm := RUNTIME.new()
	var transport := RUNTIME.new()
	test.expect_true(arm.configure(arm_definition, Vector2i(2, 2), RUNTIME.Facing.EAST), "Arm runtime should configure.")
	test.expect_true(transport.configure(transport_definition, Vector2i(7, 4), RUNTIME.Facing.WEST), "Transport runtime should configure.")

	test.expect_true(arm.set_arm_has_item(true), "Arm should accept carried-item state.")
	test.expect_true(arm.arm_has_item, "Arm should retain carried-item state.")
	test.expect_float_approx(arm.get_effective_speed(), arm_definition.base_speed * 0.25, "Arm carrying speed multiplier.")
	test.expect_false(arm.set_tray_count(1), "Arm should reject tray state.")
	test.expect_equal(arm.tray_count, 0, "Rejected arm tray mutation should be atomic.")

	var tray_cases := [
		{"value": 0, "accepted": true},
		{"value": 5, "accepted": true},
		{"value": 8, "accepted": true},
		{"value": -1, "accepted": false},
		{"value": 9, "accepted": false},
	]
	for case in tray_cases:
		var before := transport.tray_count
		var accepted: bool = transport.set_tray_count(case["value"])
		test.expect_equal(accepted, case["accepted"], "Transport tray boundary %d." % case["value"])
		if accepted:
			test.expect_equal(transport.tray_count, case["value"], "Accepted tray mutation should apply.")
		else:
			test.expect_equal(transport.tray_count, before, "Rejected tray mutation should preserve state.")
	test.expect_false(transport.set_arm_has_item(true), "Transport should reject arm state.")
	test.expect_false(transport.arm_has_item, "Rejected arm mutation should preserve false.")


func _test_runtime_reset_contract() -> void:
	var definition = _arm_definition()
	var runtime := RUNTIME.new()
	test.expect_true(runtime.configure(definition, Vector2i(3, 3), RUNTIME.Facing.SOUTH), "Reset runtime should configure.")
	runtime.anchor_cell = Vector2i(5, 4)
	runtime.facing = RUNTIME.Facing.WEST
	runtime.motion_state = RUNTIME.MotionState.MOVING
	runtime.set_arm_has_item(true)
	runtime.enqueue_command({"type": "MoveTo", "target": Vector2i(5, 4)})
	runtime.reset()
	test.expect_equal(runtime.anchor_cell, Vector2i(3, 3), "Reset restores initial anchor.")
	test.expect_equal(runtime.facing, RUNTIME.Facing.SOUTH, "Reset restores initial facing.")
	test.expect_equal(runtime.motion_state, RUNTIME.MotionState.WAITING, "Reset restores Waiting.")
	test.expect_false(runtime.arm_has_item, "Reset clears carried item.")
	test.expect_equal(runtime.tray_count, 0, "Reset clears tray state.")
	test.expect_true(runtime.active_move_command == null, "Reset clears active command.")
	test.expect_true(runtime.command_queue.is_empty(), "Reset clears queued commands.")


func _test_invalid_configuration_boundaries() -> void:
	var definition_cases: Array[Dictionary] = [
		{"name": "empty id", "id": &"", "footprint": Vector2i.ONE, "speed": 1.0, "weight": 0.0, "recommended": 0.0, "maximum": 0.0, "multiplier": 1.0, "tray": 0},
		{"name": "zero footprint", "id": &"x", "footprint": Vector2i.ZERO, "speed": 1.0, "weight": 0.0, "recommended": 0.0, "maximum": 0.0, "multiplier": 1.0, "tray": 0},
		{"name": "zero speed", "id": &"x", "footprint": Vector2i.ONE, "speed": 0.0, "weight": 0.0, "recommended": 0.0, "maximum": 0.0, "multiplier": 1.0, "tray": 0},
		{"name": "negative weight", "id": &"x", "footprint": Vector2i.ONE, "speed": 1.0, "weight": -1.0, "recommended": 0.0, "maximum": 0.0, "multiplier": 1.0, "tray": 0},
		{"name": "payload inversion", "id": &"x", "footprint": Vector2i.ONE, "speed": 1.0, "weight": 0.0, "recommended": 2.0, "maximum": 1.0, "multiplier": 1.0, "tray": 0},
		{"name": "zero carrying multiplier", "id": &"x", "footprint": Vector2i.ONE, "speed": 1.0, "weight": 0.0, "recommended": 0.0, "maximum": 0.0, "multiplier": 0.0, "tray": 0},
		{"name": "negative tray capacity", "id": &"x", "footprint": Vector2i.ONE, "speed": 1.0, "weight": 0.0, "recommended": 0.0, "maximum": 0.0, "multiplier": 1.0, "tray": -1},
	]
	for case in definition_cases:
		var definition := DEFINITION.new()
		var configured := bool(_quiet(Callable(definition, "configure").bind(
			case["id"], "Invalid", DEFINITION.VehicleKind.ARM, case["footprint"], case["speed"],
			case["weight"], case["recommended"], case["maximum"], PackedStringArray(), case["multiplier"], case["tray"]
		)))
		test.expect_false(configured, "%s should be rejected." % case["name"])
		test.expect_false(definition.is_configured(), "%s should leave definition unconfigured." % case["name"])

	var valid = _arm_definition()
	var second_configure := bool(_quiet(Callable(valid, "configure").bind(
		&"other", "Other", DEFINITION.VehicleKind.ARM, Vector2i.ONE, 1.0, 0.0, 0.0, 0.0, PackedStringArray(), 1.0, 0
	)))
	test.expect_false(second_configure, "Configured definitions should be immutable.")

	var runtime := RUNTIME.new()
	test.expect_false(bool(_quiet(Callable(runtime, "configure").bind(DEFINITION.new(), Vector2i.ZERO))), "Runtime should reject unconfigured definitions.")
	test.expect_true(runtime.definition == null, "Rejected runtime configuration should bind nothing.")

	var arm_definition = _arm_definition()
	var transport_definition = _transport_definition()
	var bound_runtime := RUNTIME.new()
	test.expect_true(bound_runtime.configure(arm_definition, Vector2i.ZERO), "Mismatch runtime should configure with arm definition.")
	var actor := ACTOR.new()
	var controller := Node.new()
	test.expect_false(bool(_quiet(Callable(actor, "configure").bind(transport_definition, bound_runtime, controller, 1.0))), "Actor should reject a runtime bound to another definition.")
	actor.free()
	controller.free()


func _arm_definition():
	return _definition(
		&"arm_vehicle", "Arm Vehicle", DEFINITION.VehicleKind.ARM, 2.0, 18.0, 20.0, 30.0,
		PackedStringArray([DEFINITION.CAPABILITY_CAN_MOVE, DEFINITION.CAPABILITY_CAN_GRAB, DEFINITION.CAPABILITY_CAN_CARRY]), 0.25, 0
	)


func _transport_definition():
	return _definition(
		&"transport_vehicle", "Transport Vehicle", DEFINITION.VehicleKind.TRANSPORT, 2.4, 16.0, 24.0, 36.0,
		PackedStringArray([DEFINITION.CAPABILITY_CAN_MOVE, DEFINITION.CAPABILITY_CAN_CARRY, DEFINITION.CAPABILITY_HAS_TRAY]), 1.0, 8
	)


func _definition(id: StringName, display: String, kind: int, speed: float, weight: float, recommended: float, maximum: float, tags: PackedStringArray, multiplier: float, tray: int):
	var definition := DEFINITION.new()
	if not definition.configure(id, display, kind, Vector2i(2, 2), speed, weight, recommended, maximum, tags, multiplier, tray):
		return null
	return definition


func _quiet(callback: Callable) -> Variant:
	var previous := Engine.print_error_messages
	Engine.print_error_messages = false
	var result: Variant = callback.call()
	Engine.print_error_messages = previous
	return result

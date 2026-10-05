extends SceneTree

const VehicleDefinitionScript := preload("res://scripts/vehicles/vehicle_definition.gd")
const VehicleRuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const ContractTestScript := preload("res://tests/support/contract_test.gd")


var test = ContractTestScript.new()


func _init() -> void:
	_test_reset_restores_stationary_tray_interaction_metadata()
	test.finish(self, "Vehicle runtime reset stability tests")


func _test_reset_restores_stationary_tray_interaction_metadata() -> void:
	var definition := VehicleDefinitionScript.new()
	test.expect_true(
		definition.configure(
			&"transport_vehicle",
			"Transport Vehicle",
			VehicleDefinitionScript.VehicleKind.TRANSPORT,
			Vector2i(2, 2),
			2.4,
			16.0,
			24.0,
			36.0,
			PackedStringArray([
				VehicleDefinitionScript.CAPABILITY_CAN_MOVE,
				VehicleDefinitionScript.CAPABILITY_CAN_CARRY,
				VehicleDefinitionScript.CAPABILITY_HAS_TRAY,
			]),
			1.0,
			8
		),
		"Transport definition should configure for reset stability coverage."
	)
	if not definition.is_configured():
		return

	var initial_anchor := Vector2i(7, 4)
	var runtime := VehicleRuntimeStateScript.new()
	test.expect_true(
		runtime.configure(
			definition,
			initial_anchor,
			VehicleRuntimeStateScript.Facing.WEST
		),
		"Transport runtime should configure."
	)
	if runtime.definition == null or runtime.tray_state == null:
		return

	var tray = runtime.tray_state
	var expected_cells := _footprint_cells(initial_anchor, definition.footprint)
	test.expect_equal(
		tray.get_interaction_cells(),
		expected_cells,
		"Configured stationary runtime should publish tray interaction cells."
	)
	test.expect_true(
		runtime.get_item_interaction_interfaces_readonly().has(tray),
		"Configured stationary runtime should expose its tray interface."
	)

	test.expect_true(
		runtime.begin_move_planning(),
		"Move planning should enter the mutable state that hides stationary interaction metadata."
	)
	test.expect_equal(
		tray.get_interaction_cells(),
		[],
		"Planning should clear tray interaction cells."
	)
	test.expect_equal(
		runtime.get_item_interaction_interfaces_readonly(),
		[],
		"Planning should hide the tray interaction interface."
	)

	runtime.anchor_cell = Vector2i(9, 6)
	runtime.reset()
	test.expect_equal(
		runtime.anchor_cell,
		initial_anchor,
		"Reset should restore the initial anchor before republishing metadata."
	)
	test.expect_equal(
		runtime.motion_state,
		VehicleRuntimeStateScript.MotionState.WAITING,
		"Reset should restore stationary motion state."
	)
	test.expect_equal(
		tray.get_interaction_cells(),
		expected_cells,
		"Reset should republish stationary tray interaction cells from authoritative runtime state."
	)
	test.expect_true(
		runtime.get_item_interaction_interfaces_readonly().has(tray),
		"Reset should re-expose the tray interaction interface."
	)

	runtime.reset()
	test.expect_equal(
		tray.get_interaction_cells(),
		expected_cells,
		"Repeated reset should keep stationary tray metadata deterministic."
	)


func _footprint_cells(anchor: Vector2i, footprint: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for offset_y in range(footprint.y):
		for offset_x in range(footprint.x):
			cells.append(anchor + Vector2i(offset_x, offset_y))
	return cells

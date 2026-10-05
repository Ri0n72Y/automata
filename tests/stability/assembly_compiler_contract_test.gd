extends SceneTree

const CAPABILITIES_SCRIPT = preload("res://scripts/assembly/assembly_capabilities.gd")
const INTERFACE_SCRIPT = preload("res://scripts/assembly/assembly_interaction_interface.gd")
const COMPONENT_SCRIPT = preload("res://scripts/assembly/assembly_component_definition.gd")
const DEFINITION_SCRIPT = preload("res://scripts/assembly/assembly_definition.gd")
const REQUEST_SCRIPT = preload("res://scripts/assembly/assembly_compile_request.gd")
const COMPILER_SCRIPT = preload("res://scripts/assembly/assembly_compiler.gd")
const CONTRACT_TEST_SCRIPT = preload("res://tests/support/contract_test.gd")
const MIN_INT32: int = -2147483648
const MAX_INT32: int = 2147483647
const MAX_INT64: int = 9223372036854775807

var test = CONTRACT_TEST_SCRIPT.new()


func _init() -> void:
	_test_compile_runtime_description()
	_test_overlap_fails_without_partial_runtime_state()
	_test_same_revision_reuses_cached_result()
	_test_same_revision_rejects_changed_structure()
	_test_revision_change_invalidates_cache_key()
	_test_invalidation_isolated_by_assembly_id()
	_test_interface_coordinate_space_contract()
	_test_invalid_component_entry_is_rejected()
	_test_invalid_interface_entry_is_rejected()
	_test_non_finite_mass_is_rejected()
	_test_aggregate_metric_overflow_is_rejected()
	_test_coordinate_overflow_is_rejected()
	_test_invalid_interface_metadata_is_rejected()
	_test_result_collections_are_snapshots()
	_test_request_captures_revision_snapshot()
	test.finish(self, "Assembly compiler contract tests")


func _test_compile_runtime_description() -> void:
	var compiler = COMPILER_SCRIPT.new()
	var result = _compile(compiler, _make_full_assembly(1))
	test.expect_true(result.is_success(), "A valid assembly should compile.")
	test.expect_true(result.has_capability(CAPABILITIES_SCRIPT.CAN_MOVE), "Drive module should publish can_move.")
	test.expect_true(result.has_capability(CAPABILITIES_SCRIPT.GRAB_DROP), "Arm module should publish grab_drop.")
	var envelope = result.get_simulation_envelope()
	test.expect_equal(envelope.size(), 3, "Compiled envelope should aggregate occupied cells.")
	test.expect_true(envelope.contains_cell(Vector2i(0, 0)), "Envelope should include the drive origin cell.")
	test.expect_true(envelope.contains_cell(Vector2i(1, 0)), "Envelope should include the drive footprint.")
	test.expect_true(envelope.contains_cell(Vector2i(0, 1)), "Envelope should include the arm footprint.")
	var metrics = result.get_metrics()
	test.expect_equal(metrics.get_cost(), 35, "Assembly cost should aggregate component costs.")
	test.expect_equal(metrics.get_mass(), 7.5, "Assembly mass should aggregate component mass.")
	var interfaces = result.get_interaction_interfaces()
	test.expect_equal(interfaces.size(), 1, "Arm module should publish one interaction interface.")
	if interfaces.size() == 1:
		test.expect_equal(interfaces[0].kind, &"grab_drop", "Compiled interaction interface should preserve its kind.")
		test.expect_equal(interfaces[0].owner_component_id, &"arm", "Compiled interface should retain its owner component.")
		test.expect_true(interfaces[0].is_assembly_local(), "Compiled interface cells should be explicitly assembly-local.")
		test.expect_equal(interfaces[0].cells, [Vector2i(0, 2)], "Component orientation should rotate interface cells before translation.")


func _test_overlap_fails_without_partial_runtime_state() -> void:
	var compiler = COMPILER_SCRIPT.new()
	var first = COMPONENT_SCRIPT.new(
		&"first", &"module", Vector2i.ZERO, 0, [Vector2i.ZERO], [CAPABILITIES_SCRIPT.CAN_MOVE]
	)
	var second = COMPONENT_SCRIPT.new(
		&"second", &"module", Vector2i.ZERO, 0, [Vector2i.ZERO], [CAPABILITIES_SCRIPT.GRAB_DROP]
	)
	var result = _compile(compiler, DEFINITION_SCRIPT.new(&"overlap", 1, [first, second]))
	test.expect_false(result.is_success(), "Overlapping components should fail compilation.")
	test.expect_true(_has_diagnostic(result, COMPILER_SCRIPT.DIAGNOSTIC_OCCUPANCY_OVERLAP), "Overlap failure should have a stable diagnostic code.")
	test.expect_equal(result.get_capabilities().size(), 0, "Failed compile should not expose partial capabilities.")
	test.expect_equal(result.get_simulation_envelope().size(), 0, "Failed compile should not expose a partial envelope.")
	test.expect_equal(result.get_metrics().get_cost(), 0, "Failed compile should not expose partial metrics.")


func _test_same_revision_reuses_cached_result() -> void:
	var compiler = COMPILER_SCRIPT.new()
	var request = REQUEST_SCRIPT.new(_make_full_assembly(7))
	var first = compiler.compile(request)
	var second = compiler.compile(request)
	test.expect_true(first == second, "The same assembly revision and structure should reuse the cached result instance.")
	test.expect_equal(compiler.get_cache_size(), 1, "One revision should occupy one cache entry.")


func _test_same_revision_rejects_changed_structure() -> void:
	var compiler = COMPILER_SCRIPT.new()
	var original_request = REQUEST_SCRIPT.new(_make_drive_only_assembly(&"revision_guard", 5, 10))
	var original = compiler.compile(original_request)
	test.expect_true(original.is_success(), "Initial revision should compile before mismatch validation.")
	var changed = _compile(
		compiler,
		_make_drive_only_assembly(&"revision_guard", 5, 11)
	)
	test.expect_false(changed.is_success(), "Changing structure without advancing revision should be rejected.")
	test.expect_true(
		_has_diagnostic(changed, COMPILER_SCRIPT.DIAGNOSTIC_REVISION_CONTENT_MISMATCH),
		"Revision/content mismatch should have a stable diagnostic code."
	)
	test.expect_equal(compiler.get_cache_size(), 1, "Revision mismatch should not overwrite the existing cache entry.")
	test.expect_true(
		compiler.compile(original_request) == original,
		"The original revision snapshot should remain reusable after a mismatch attempt."
	)


func _test_revision_change_invalidates_cache_key() -> void:
	var compiler = COMPILER_SCRIPT.new()
	var first = _compile(compiler, _make_full_assembly(3))
	var second = _compile(compiler, _make_full_assembly(4))
	test.expect_false(first == second, "Changing revision should produce a fresh compile result.")
	test.expect_equal(second.get_revision().get_value(), 4, "Compile result should preserve the new revision.")
	test.expect_equal(compiler.get_cache_size(), 2, "Distinct revisions should use distinct cache entries.")
	compiler.invalidate(&"scene01_vehicle")
	test.expect_equal(compiler.get_cache_size(), 0, "Explicit assembly invalidation should remove all revisions for that assembly.")


func _test_invalidation_isolated_by_assembly_id() -> void:
	var compiler = COMPILER_SCRIPT.new()
	var first_request = REQUEST_SCRIPT.new(_make_drive_only_assembly(&"foo", 1, 10))
	var nested_request = REQUEST_SCRIPT.new(_make_drive_only_assembly(&"foo@bar", 1, 10))
	compiler.compile(first_request)
	var nested_result = compiler.compile(nested_request)
	test.expect_equal(compiler.get_cache_size(), 2, "Two assembly ids should occupy two cache entries.")
	compiler.invalidate(&"foo")
	test.expect_equal(compiler.get_cache_size(), 1, "Invalidation should only remove the exact assembly id.")
	test.expect_true(
		compiler.compile(nested_request) == nested_result,
		"Assembly ids containing separators should remain independently cacheable."
	)


func _test_interface_coordinate_space_contract() -> void:
	var compiler = COMPILER_SCRIPT.new()
	var invalid_interface = INTERFACE_SCRIPT.new(
		&"grab_drop",
		[Vector2i.RIGHT],
		{},
		&"",
		INTERFACE_SCRIPT.CoordinateSpace.ASSEMBLY_LOCAL
	)
	var component = COMPONENT_SCRIPT.new(
		&"arm",
		&"arm_module",
		Vector2i.ZERO,
		0,
		[Vector2i.ZERO],
		[CAPABILITIES_SCRIPT.GRAB_DROP],
		[invalid_interface]
	)
	var result = _compile(compiler, DEFINITION_SCRIPT.new(&"bad_interface_space", 1, [component]))
	test.expect_false(result.is_success(), "Compile inputs should reject already-transformed interaction cells.")
	test.expect_true(
		_has_diagnostic(result, COMPILER_SCRIPT.DIAGNOSTIC_INTERFACE_COORDINATE_SPACE_INVALID),
		"Invalid interface coordinate space should have a stable diagnostic code."
	)


func _test_invalid_component_entry_is_rejected() -> void:
	var compiler = COMPILER_SCRIPT.new()
	var valid_definition = _make_drive_only_assembly(&"malformed_component", 1, 10)
	var cached_result = _compile(compiler, valid_definition)
	test.expect_true(cached_result.is_success(), "Valid structure should compile before malformed cache masking is tested.")
	var valid_component = valid_definition.get_components()[0]
	var malformed_definition = DEFINITION_SCRIPT.new(&"malformed_component", 1, [valid_component, "invalid"])
	var result = _compile(compiler, malformed_definition)
	test.expect_false(result.is_success(), "Invalid component entries must not be silently discarded.")
	test.expect_true(
		_has_diagnostic(result, COMPILER_SCRIPT.DIAGNOSTIC_COMPONENT_ENTRY_INVALID),
		"Invalid component entries should have a stable diagnostic code."
	)
	test.expect_equal(compiler.get_cache_size(), 1, "Malformed input must not replace or add to the existing cache entry.")


func _test_invalid_interface_entry_is_rejected() -> void:
	var compiler = COMPILER_SCRIPT.new()
	var valid_component = COMPONENT_SCRIPT.new(
		&"arm",
		&"arm_module",
		Vector2i.ZERO,
		0,
		[Vector2i.ZERO],
		[CAPABILITIES_SCRIPT.GRAB_DROP]
	)
	var cached_result = _compile(
		compiler,
		DEFINITION_SCRIPT.new(&"malformed_interface", 1, [valid_component])
	)
	test.expect_true(cached_result.is_success(), "Valid structure should compile before malformed interface cache masking is tested.")
	var malformed_component = COMPONENT_SCRIPT.new(
		&"arm",
		&"arm_module",
		Vector2i.ZERO,
		0,
		[Vector2i.ZERO],
		[CAPABILITIES_SCRIPT.GRAB_DROP],
		["invalid"]
	)
	var result = _compile(compiler, DEFINITION_SCRIPT.new(&"malformed_interface", 1, [malformed_component]))
	test.expect_false(result.is_success(), "Invalid interface entries must not be silently discarded.")
	test.expect_true(
		_has_diagnostic(result, COMPILER_SCRIPT.DIAGNOSTIC_INTERFACE_ENTRY_INVALID),
		"Invalid interface entries should have a stable diagnostic code."
	)
	test.expect_equal(compiler.get_cache_size(), 1, "Malformed interface input must not replace or add to the existing cache entry.")


func _test_non_finite_mass_is_rejected() -> void:
	for invalid_mass in [NAN, INF, -INF]:
		var compiler = COMPILER_SCRIPT.new()
		var component = COMPONENT_SCRIPT.new(
			&"drive",
			&"drive_module",
			Vector2i.ZERO,
			0,
			[Vector2i.ZERO],
			[CAPABILITIES_SCRIPT.CAN_MOVE],
			[],
			10,
			invalid_mass
		)
		var definition = DEFINITION_SCRIPT.new(&"non_finite_mass", 1, [component])
		var first = _compile(compiler, definition)
		var second = _compile(compiler, definition)
		test.expect_false(first.is_success(), "Non-finite component mass must fail compilation.")
		test.expect_false(second.is_success(), "Repeated non-finite mass input must remain a validation failure.")
		test.expect_true(
			_has_diagnostic(first, COMPILER_SCRIPT.DIAGNOSTIC_MASS_INVALID),
			"Non-finite component mass should use the mass_invalid diagnostic."
		)
		test.expect_true(
			_has_diagnostic(second, COMPILER_SCRIPT.DIAGNOSTIC_MASS_INVALID),
			"Repeated non-finite mass input must not degrade into a revision mismatch."
		)
		test.expect_false(
			_has_diagnostic(second, COMPILER_SCRIPT.DIAGNOSTIC_REVISION_CONTENT_MISMATCH),
			"Non-finite mass must be rejected before revision cache comparison."
		)
		test.expect_equal(compiler.get_cache_size(), 0, "Non-finite mass must not create a cache entry.")


func _test_aggregate_metric_overflow_is_rejected() -> void:
	var max_cost_component = COMPONENT_SCRIPT.new(
		&"cost_a", &"module", Vector2i.ZERO, 0, [Vector2i.ZERO], [], [], MAX_INT64, 0.0
	)
	var overflow_cost_component = COMPONENT_SCRIPT.new(
		&"cost_b", &"module", Vector2i.RIGHT, 0, [Vector2i.ZERO], [], [], 1, 0.0
	)
	var cost_result = _compile(
		COMPILER_SCRIPT.new(),
		DEFINITION_SCRIPT.new(&"cost_overflow", 1, [max_cost_component, overflow_cost_component])
	)
	test.expect_false(cost_result.is_success(), "Aggregate cost overflow must fail compilation.")
	test.expect_true(
		_has_diagnostic(cost_result, COMPILER_SCRIPT.DIAGNOSTIC_COST_INVALID),
		"Aggregate cost overflow should use the cost_invalid diagnostic."
	)
	test.expect_equal(cost_result.get_metrics().get_cost(), 0, "Failed cost aggregation must not publish partial metrics.")

	var huge_mass_a = COMPONENT_SCRIPT.new(
		&"mass_a", &"module", Vector2i.ZERO, 0, [Vector2i.ZERO], [], [], 0, 1.0e308
	)
	var huge_mass_b = COMPONENT_SCRIPT.new(
		&"mass_b", &"module", Vector2i.RIGHT, 0, [Vector2i.ZERO], [], [], 0, 1.0e308
	)
	var mass_result = _compile(
		COMPILER_SCRIPT.new(),
		DEFINITION_SCRIPT.new(&"mass_overflow", 1, [huge_mass_a, huge_mass_b])
	)
	test.expect_false(mass_result.is_success(), "Aggregate finite mass overflow must fail compilation.")
	test.expect_true(
		_has_diagnostic(mass_result, COMPILER_SCRIPT.DIAGNOSTIC_MASS_INVALID),
		"Aggregate mass overflow should use the mass_invalid diagnostic."
	)
	test.expect_equal(mass_result.get_metrics().get_mass(), 0.0, "Failed mass aggregation must not publish partial metrics.")


func _test_coordinate_overflow_is_rejected() -> void:
	var rotation_component = COMPONENT_SCRIPT.new(
		&"rotation_overflow",
		&"module",
		Vector2i.ZERO,
		2,
		[Vector2i(MIN_INT32, 0)]
	)
	var rotation_result = _compile(
		COMPILER_SCRIPT.new(),
		DEFINITION_SCRIPT.new(&"rotation_overflow", 1, [rotation_component])
	)
	test.expect_false(rotation_result.is_success(), "Rotation beyond Vector2i range must fail compilation.")
	test.expect_true(
		_has_diagnostic(rotation_result, COMPILER_SCRIPT.DIAGNOSTIC_COORDINATE_OVERFLOW),
		"Rotation overflow should use the coordinate_overflow diagnostic."
	)
	test.expect_equal(rotation_result.get_simulation_envelope().size(), 0, "Rotation overflow must not publish geometry.")

	var translation_component = COMPONENT_SCRIPT.new(
		&"translation_overflow",
		&"module",
		Vector2i(MAX_INT32, 0),
		0,
		[Vector2i.RIGHT]
	)
	var translation_result = _compile(
		COMPILER_SCRIPT.new(),
		DEFINITION_SCRIPT.new(&"translation_overflow", 1, [translation_component])
	)
	test.expect_false(translation_result.is_success(), "Translation beyond Vector2i range must fail compilation.")
	test.expect_true(
		_has_diagnostic(translation_result, COMPILER_SCRIPT.DIAGNOSTIC_COORDINATE_OVERFLOW),
		"Translation overflow should use the coordinate_overflow diagnostic."
	)

	var overflowing_interface = INTERFACE_SCRIPT.new(&"grab_drop", [Vector2i.RIGHT])
	var interface_component = COMPONENT_SCRIPT.new(
		&"interface_overflow",
		&"module",
		Vector2i(MAX_INT32, 0),
		0,
		[Vector2i.ZERO],
		[CAPABILITIES_SCRIPT.GRAB_DROP],
		[overflowing_interface]
	)
	var interface_result = _compile(
		COMPILER_SCRIPT.new(),
		DEFINITION_SCRIPT.new(&"interface_overflow", 1, [interface_component])
	)
	test.expect_false(interface_result.is_success(), "Interaction geometry overflow must fail compilation.")
	test.expect_true(
		_has_diagnostic(interface_result, COMPILER_SCRIPT.DIAGNOSTIC_COORDINATE_OVERFLOW),
		"Interaction overflow should use the coordinate_overflow diagnostic."
	)
	test.expect_equal(interface_result.get_interaction_interfaces().size(), 0, "Interaction overflow must not publish partial interfaces.")


func _test_invalid_interface_metadata_is_rejected() -> void:
	var invalid_metadata_cases: Array[Dictionary] = [
		{"nested_array": []},
		{"nested_dictionary": {}},
		{"object": INTERFACE_SCRIPT.new()},
		{"non_finite": NAN},
	]
	for invalid_metadata in invalid_metadata_cases:
		var compiler = COMPILER_SCRIPT.new()
		var interface_value = INTERFACE_SCRIPT.new(
			&"grab_drop",
			[Vector2i.RIGHT],
			invalid_metadata
		)
		var component = COMPONENT_SCRIPT.new(
			&"arm",
			&"arm_module",
			Vector2i.ZERO,
			0,
			[Vector2i.ZERO],
			[CAPABILITIES_SCRIPT.GRAB_DROP],
			[interface_value]
		)
		var definition = DEFINITION_SCRIPT.new(&"invalid_metadata", 1, [component])
		var first = _compile(compiler, definition)
		var second = _compile(compiler, definition)
		test.expect_false(first.is_success(), "Nested containers, Objects, and non-finite metadata must fail compilation.")
		test.expect_true(
			_has_diagnostic(first, COMPILER_SCRIPT.DIAGNOSTIC_INTERFACE_METADATA_INVALID),
			"Invalid metadata should have a stable diagnostic code."
		)
		test.expect_true(
			_has_diagnostic(second, COMPILER_SCRIPT.DIAGNOSTIC_INTERFACE_METADATA_INVALID),
			"Repeated invalid metadata must remain a metadata validation failure."
		)
		test.expect_equal(compiler.get_cache_size(), 0, "Invalid metadata must not create a cache entry.")


func _test_result_collections_are_snapshots() -> void:
	var result = _compile(COMPILER_SCRIPT.new(), _make_full_assembly(9))
	var capabilities = result.get_capabilities()
	capabilities.append(&"mutated")
	test.expect_false(result.has_capability(&"mutated"), "Capability queries should return collection snapshots.")
	var envelope = result.get_simulation_envelope()
	var occupied_cells = envelope.get_occupied_cells()
	occupied_cells.append(Vector2i(99, 99))
	test.expect_false(result.get_simulation_envelope().contains_cell(Vector2i(99, 99)), "Envelope queries should return collection snapshots.")
	var interfaces = result.get_interaction_interfaces()
	interfaces[0].cells.append(Vector2i(88, 88))
	var fresh_interfaces = result.get_interaction_interfaces()
	test.expect_false(fresh_interfaces[0].cells.has(Vector2i(88, 88)), "Interaction interface queries should return descriptor snapshots.")


func _test_request_captures_revision_snapshot() -> void:
	var definition = _make_full_assembly(11)
	var request = REQUEST_SCRIPT.new(definition)
	definition.assembly_id = &"mutated_after_request"
	definition.revision = 12
	var result = COMPILER_SCRIPT.new().compile(request)
	test.expect_equal(result.get_assembly_id(), &"scene01_vehicle", "Compile request should capture assembly identity at construction.")
	test.expect_equal(result.get_revision().get_value(), 11, "Compile request should capture revision at construction.")


func _compile(compiler, definition):
	return compiler.compile(REQUEST_SCRIPT.new(definition))


func _make_drive_only_assembly(assembly_id: StringName, revision: int, cost: int):
	var drive = COMPONENT_SCRIPT.new(
		&"drive",
		&"drive_module",
		Vector2i.ZERO,
		0,
		[Vector2i.ZERO],
		[CAPABILITIES_SCRIPT.CAN_MOVE],
		[],
		cost,
		4.0
	)
	return DEFINITION_SCRIPT.new(assembly_id, revision, [drive])


func _make_full_assembly(revision: int):
	var drive = COMPONENT_SCRIPT.new(
		&"drive",
		&"drive_module",
		Vector2i.ZERO,
		0,
		[Vector2i(0, 0), Vector2i(1, 0)],
		[CAPABILITIES_SCRIPT.CAN_MOVE],
		[],
		10,
		4.0
	)
	var arm_interface = INTERFACE_SCRIPT.new(&"grab_drop", [Vector2i(1, 0)], {"range": 1})
	var arm = COMPONENT_SCRIPT.new(
		&"arm",
		&"arm_module",
		Vector2i(0, 1),
		1,
		[Vector2i.ZERO],
		[CAPABILITIES_SCRIPT.GRAB_DROP],
		[arm_interface],
		25,
		3.5
	)
	return DEFINITION_SCRIPT.new(&"scene01_vehicle", revision, [drive, arm])


func _has_diagnostic(result, code: StringName) -> bool:
	for diagnostic in result.get_diagnostics():
		if diagnostic.code == code:
			return true
	return false

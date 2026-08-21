extends SceneTree

const CAPABILITIES_SCRIPT := preload("res://scripts/assembly/assembly_capabilities.gd")
const INTERFACE_SCRIPT := preload("res://scripts/assembly/assembly_interaction_interface.gd")
const COMPONENT_SCRIPT := preload("res://scripts/assembly/assembly_component_definition.gd")
const DEFINITION_SCRIPT := preload("res://scripts/assembly/assembly_definition.gd")
const REQUEST_SCRIPT := preload("res://scripts/assembly/assembly_compile_request.gd")
const COMPILER_SCRIPT := preload("res://scripts/assembly/assembly_compiler.gd")
const CONTRACT_TEST_SCRIPT := preload("res://tests/support/contract_test.gd")

var test := CONTRACT_TEST_SCRIPT.new()


func _init() -> void:
	_test_compile_runtime_description()
	_test_overlap_fails_without_partial_runtime_state()
	_test_same_revision_reuses_cached_result()
	_test_revision_change_invalidates_cache_key()
	_test_result_collections_are_snapshots()
	_test_request_captures_revision_snapshot()
	test.finish(self, "Assembly compiler contract tests")


func _test_compile_runtime_description() -> void:
	var compiler := COMPILER_SCRIPT.new()
	var result := _compile(compiler, _make_full_assembly(1))
	test.expect_true(result.is_success(), "A valid assembly should compile.")
	test.expect_true(result.has_capability(CAPABILITIES_SCRIPT.CAN_MOVE), "Drive module should publish can_move.")
	test.expect_true(result.has_capability(CAPABILITIES_SCRIPT.GRAB_DROP), "Arm module should publish grab_drop.")
	var envelope := result.get_simulation_envelope()
	test.expect_equal(envelope.size(), 3, "Compiled envelope should aggregate occupied cells.")
	test.expect_true(envelope.contains_cell(Vector2i(0, 0)), "Envelope should include the drive origin cell.")
	test.expect_true(envelope.contains_cell(Vector2i(1, 0)), "Envelope should include the drive footprint.")
	test.expect_true(envelope.contains_cell(Vector2i(0, 1)), "Envelope should include the arm footprint.")
	var metrics := result.get_metrics()
	test.expect_equal(metrics.get_cost(), 35, "Assembly cost should aggregate component costs.")
	test.expect_equal(metrics.get_mass(), 7.5, "Assembly mass should aggregate component mass.")
	var interface_set := result.get_interaction_interface_set()
	test.expect_equal(interface_set.size(), 1, "Arm module should publish one interaction interface.")
	var interfaces := interface_set.get_by_kind(&"grab_drop")
	test.expect_equal(interfaces.size(), 1, "Compiled interaction set should support kind queries.")
	if interfaces.size() == 1:
		test.expect_equal(interfaces[0].owner_component_id, &"arm", "Compiled interface should retain its owner component.")
		test.expect_equal(interfaces[0].cells, [Vector2i(0, 2)], "Component orientation should rotate interface cells before translation.")


func _test_overlap_fails_without_partial_runtime_state() -> void:
	var compiler := COMPILER_SCRIPT.new()
	var first := COMPONENT_SCRIPT.new(
		&"first", &"module", Vector2i.ZERO, 0, [Vector2i.ZERO], [CAPABILITIES_SCRIPT.CAN_MOVE]
	)
	var second := COMPONENT_SCRIPT.new(
		&"second", &"module", Vector2i.ZERO, 0, [Vector2i.ZERO], [CAPABILITIES_SCRIPT.GRAB_DROP]
	)
	var result := _compile(compiler, DEFINITION_SCRIPT.new(&"overlap", 1, [first, second]))
	test.expect_false(result.is_success(), "Overlapping components should fail compilation.")
	test.expect_true(_has_diagnostic(result, COMPILER_SCRIPT.DIAGNOSTIC_OCCUPANCY_OVERLAP), "Overlap failure should have a stable diagnostic code.")
	test.expect_equal(result.get_capabilities().size(), 0, "Failed compile should not expose partial capabilities.")
	test.expect_equal(result.get_simulation_envelope().size(), 0, "Failed compile should not expose a partial envelope.")
	test.expect_equal(result.get_metrics().get_cost(), 0, "Failed compile should not expose partial metrics.")


func _test_same_revision_reuses_cached_result() -> void:
	var compiler := COMPILER_SCRIPT.new()
	var request := REQUEST_SCRIPT.new(_make_full_assembly(7))
	var first := compiler.compile(request)
	var second := compiler.compile(request)
	test.expect_true(first == second, "The same assembly revision should reuse the cached result instance.")
	test.expect_equal(compiler.get_cache_size(), 1, "One revision should occupy one cache entry.")


func _test_revision_change_invalidates_cache_key() -> void:
	var compiler := COMPILER_SCRIPT.new()
	var first := _compile(compiler, _make_full_assembly(3))
	var second := _compile(compiler, _make_full_assembly(4))
	test.expect_false(first == second, "Changing revision should produce a fresh compile result.")
	test.expect_equal(second.get_revision().get_value(), 4, "Compile result should preserve the new revision.")
	test.expect_equal(compiler.get_cache_size(), 2, "Distinct revisions should use distinct cache entries.")
	compiler.invalidate(&"scene01_vehicle")
	test.expect_equal(compiler.get_cache_size(), 0, "Explicit assembly invalidation should remove all revisions for that assembly.")


func _test_result_collections_are_snapshots() -> void:
	var result := _compile(COMPILER_SCRIPT.new(), _make_full_assembly(9))
	var envelope := result.get_simulation_envelope()
	var occupied_cells := envelope.get_occupied_cells()
	occupied_cells.append(Vector2i(99, 99))
	test.expect_false(result.get_simulation_envelope().contains_cell(Vector2i(99, 99)), "Envelope queries should return collection snapshots.")
	var interfaces := result.get_interaction_interfaces()
	interfaces[0].cells.append(Vector2i(88, 88))
	var fresh_interfaces := result.get_interaction_interfaces()
	test.expect_false(fresh_interfaces[0].cells.has(Vector2i(88, 88)), "Interaction interface queries should return descriptor snapshots.")


func _test_request_captures_revision_snapshot() -> void:
	var definition := _make_full_assembly(11)
	var request := REQUEST_SCRIPT.new(definition)
	definition.assembly_id = &"mutated_after_request"
	definition.revision = 12
	var result := COMPILER_SCRIPT.new().compile(request)
	test.expect_equal(result.get_assembly_id(), &"scene01_vehicle", "Compile request should capture assembly identity at construction.")
	test.expect_equal(result.get_revision().get_value(), 11, "Compile request should capture revision at construction.")


func _compile(compiler, definition):
	return compiler.compile(REQUEST_SCRIPT.new(definition))


func _make_full_assembly(revision: int):
	var drive := COMPONENT_SCRIPT.new(
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
	var arm_interface := INTERFACE_SCRIPT.new(&"grab_drop", [Vector2i(1, 0)], {"range": 1})
	var arm := COMPONENT_SCRIPT.new(
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

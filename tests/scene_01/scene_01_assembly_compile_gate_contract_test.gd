extends SceneTree

const ASSEMBLY_CAPABILITIES_SCRIPT := preload("res://scripts/assembly/assembly_capabilities.gd")
const ASSEMBLY_COMPILER_SCRIPT := preload("res://scripts/assembly/assembly_compiler.gd")
const GATE_SCRIPT := preload("res://scripts/scene_01/scene_01_assembly_compile_gate.gd")
const VEHICLE_ACTOR_SCRIPT := preload("res://scripts/vehicles/vehicle_actor.gd")
const VEHICLE_DEFINITION_SCRIPT := preload("res://scripts/vehicles/vehicle_definition.gd")
const CONTRACT_TEST_SCRIPT := preload("res://tests/support/contract_test.gd")

class FakeVehicleManager extends Node:
	var vehicles: Array[Node3D] = []

	func get_vehicles() -> Array[Node3D]:
		return vehicles.duplicate()

var test := CONTRACT_TEST_SCRIPT.new()


func _init() -> void:
	_test_successful_prepare_publishes_all_results_and_reuses_cache()
	_test_capability_failure_publishes_no_partial_runtime_state()
	_test_requirement_changes_invalidate_publication_but_preserve_cache()
	_test_missing_required_vehicle_rejects_and_clears_publication()
	_test_empty_capability_requirement_does_not_require_missing_vehicle()
	_test_unconfigured_vehicle_definition_is_rejected_as_invalid()
	_test_reconfigure_clears_runtime_state_but_preserves_cache()
	_test_invalidate_vehicle_clears_published_batch_but_preserves_other_cache()
	_test_same_revision_changed_structure_is_rejected_until_invalidated()
	test.finish(self, "Scene 01 assembly compile gate contract tests")


func _test_successful_prepare_publishes_all_results_and_reuses_cache() -> void:
	var manager := FakeVehicleManager.new()
	manager.vehicles = [
		_make_actor(_make_arm_definition()),
		_make_actor(_make_transport_definition()),
	]
	var gate := GATE_SCRIPT.new()
	gate.configure(manager)
	test.expect_true(gate.prepare_scene_run(), "Configured Scene 01 presets should pass run preparation.")
	var first_arm_result = gate.get_compile_result(&"arm_vehicle")
	var first_transport_result = gate.get_compile_result(&"transport_vehicle")
	test.expect_true(first_arm_result != null, "Successful preparation should publish arm compile result.")
	test.expect_true(first_transport_result != null, "Successful preparation should publish transport compile result.")
	test.expect_true(gate.has_vehicle_capability(&"arm_vehicle", ASSEMBLY_CAPABILITIES_SCRIPT.GRAB_DROP), "Published arm result should expose GrabDrop.")
	test.expect_false(gate.has_vehicle_capability(&"transport_vehicle", ASSEMBLY_CAPABILITIES_SCRIPT.GRAB_DROP), "Published transport result should not expose GrabDrop.")
	test.expect_equal(gate.get_compile_cache_size(), 2, "Two stable preset revisions should occupy two cache entries.")

	test.expect_true(gate.prepare_scene_run(), "Repeated preparation with unchanged presets should succeed.")
	test.expect_true(gate.get_compile_result(&"arm_vehicle") == first_arm_result, "Repeated preparation should reuse cached arm compile result.")
	test.expect_true(gate.get_compile_result(&"transport_vehicle") == first_transport_result, "Repeated preparation should reuse cached transport compile result.")
	test.expect_equal(gate.get_compile_cache_size(), 2, "Repeated preparation should not create duplicate cache entries.")


func _test_capability_failure_publishes_no_partial_runtime_state() -> void:
	var manager := FakeVehicleManager.new()
	manager.vehicles = [
		_make_actor(_make_arm_definition()),
		_make_actor(_make_transport_definition()),
	]
	var gate := GATE_SCRIPT.new()
	gate.configure(manager)
	gate.set_required_capabilities(
		&"transport_vehicle",
		[ASSEMBLY_CAPABILITIES_SCRIPT.GRAB_DROP]
	)
	test.expect_false(gate.prepare_scene_run(), "Missing required capability should reject run preparation.")
	test.expect_equal(gate.get_last_failed_vehicle_id(), &"transport_vehicle", "Capability failure should identify the rejected assembly.")
	test.expect_true(gate.get_compile_result(&"arm_vehicle") == null, "Failed batch preparation should not publish an already-compiled arm result.")
	test.expect_true(gate.get_compile_result(&"transport_vehicle") == null, "Failed batch preparation should not publish transport result.")
	var diagnostics := gate.get_last_diagnostics()
	test.expect_equal(diagnostics.size(), 1, "Missing capability should return one validation diagnostic.")

	gate.set_required_capabilities(&"transport_vehicle", [])
	test.expect_true(gate.prepare_scene_run(), "Removing unsupported program requirement should allow preparation.")
	test.expect_true(gate.get_compile_result(&"arm_vehicle") != null, "Successful retry should publish the full batch.")
	test.expect_true(gate.get_compile_result(&"transport_vehicle") != null, "Successful retry should publish transport result.")


func _test_requirement_changes_invalidate_publication_but_preserve_cache() -> void:
	var manager := FakeVehicleManager.new()
	manager.vehicles = [
		_make_actor(_make_arm_definition()),
		_make_actor(_make_transport_definition()),
	]
	var gate := GATE_SCRIPT.new()
	gate.configure(manager)
	test.expect_true(gate.prepare_scene_run(), "Initial valid batch should publish before requirements change.")
	gate.set_required_capabilities(
		&"transport_vehicle",
		[ASSEMBLY_CAPABILITIES_SCRIPT.GRAB_DROP]
	)
	test.expect_true(
		gate.get_compile_result(&"arm_vehicle") == null
		and gate.get_compile_result(&"transport_vehicle") == null,
		"Changing program requirements must invalidate the published batch."
	)
	test.expect_equal(gate.get_compile_cache_size(), 2, "Requirement changes must preserve compiler cache entries.")
	test.expect_false(gate.prepare_scene_run(), "Unsupported changed requirement should fail the next preparation.")
	gate.clear_required_capabilities()
	test.expect_equal(gate.get_last_diagnostics().size(), 0, "Clearing requirements should clear stale requirement diagnostics.")
	test.expect_equal(gate.get_compile_cache_size(), 2, "Clearing requirements must preserve compiler cache entries.")


func _test_missing_required_vehicle_rejects_and_clears_publication() -> void:
	var manager := FakeVehicleManager.new()
	manager.vehicles = [
		_make_actor(_make_arm_definition()),
		_make_actor(_make_transport_definition()),
	]
	var gate := GATE_SCRIPT.new()
	gate.configure(manager)
	test.expect_true(gate.prepare_scene_run(), "Initial valid batch should publish runtime results.")
	gate.set_required_capabilities(
		&"missing_vehicle",
		[ASSEMBLY_CAPABILITIES_SCRIPT.CAN_MOVE]
	)
	test.expect_false(gate.prepare_scene_run(), "Program requirements for a non-participating vehicle should reject run preparation.")
	test.expect_equal(gate.get_last_failed_vehicle_id(), &"missing_vehicle", "Missing required vehicle should be identified by id.")
	test.expect_true(_has_diagnostic(gate.get_last_diagnostics(), GATE_SCRIPT.DIAGNOSTIC_REQUIRED_VEHICLE_MISSING), "Missing required vehicle should surface an explicit diagnostic.")
	test.expect_true(gate.get_compile_result(&"arm_vehicle") == null, "Requirement failure should clear the previously published arm result.")
	test.expect_true(gate.get_compile_result(&"transport_vehicle") == null, "Requirement failure should clear the previously published transport result.")


func _test_empty_capability_requirement_does_not_require_missing_vehicle() -> void:
	var manager := FakeVehicleManager.new()
	manager.vehicles = [
		_make_actor(_make_arm_definition()),
		_make_actor(_make_transport_definition()),
	]
	var gate := GATE_SCRIPT.new()
	gate.configure(manager)
	gate.set_required_capabilities(&"missing_vehicle", [&"", &""])
	gate.set_required_capabilities(
		&"transport_vehicle",
		[
			ASSEMBLY_CAPABILITIES_SCRIPT.CAN_MOVE,
			ASSEMBLY_CAPABILITIES_SCRIPT.CAN_MOVE,
			&"",
		]
	)
	test.expect_true(
		gate.prepare_scene_run(),
		"Empty requirements should be ignored and duplicate supported requirements should be normalized."
	)
	test.expect_equal(gate.get_last_failed_vehicle_id(), &"", "Normalized no-op requirements should not identify a failed vehicle.")
	test.expect_equal(gate.get_last_diagnostics().size(), 0, "Normalized no-op requirements should not publish diagnostics.")
	test.expect_true(gate.get_compile_result(&"arm_vehicle") != null, "Normalized requirements should preserve full batch publication.")
	test.expect_true(gate.get_compile_result(&"transport_vehicle") != null, "Supported normalized requirements should allow transport publication.")


func _test_unconfigured_vehicle_definition_is_rejected_as_invalid() -> void:
	var manager := FakeVehicleManager.new()
	manager.vehicles = [_make_actor(VEHICLE_DEFINITION_SCRIPT.new())]
	var gate := GATE_SCRIPT.new()
	gate.configure(manager)
	test.expect_false(gate.prepare_scene_run(), "Unconfigured vehicle definitions must reject run preparation.")
	var diagnostics := gate.get_last_diagnostics()
	test.expect_true(
		_has_diagnostic(diagnostics, GATE_SCRIPT.DIAGNOSTIC_VEHICLE_DEFINITION_INVALID),
		"Unconfigured vehicle definitions should use the vehicle_definition_invalid diagnostic."
	)
	test.expect_false(
		_has_diagnostic(diagnostics, GATE_SCRIPT.DIAGNOSTIC_DUPLICATE_VEHICLE_ID),
		"An unconfigured definition must not be misreported as a duplicate vehicle id."
	)
	test.expect_equal(gate.get_compile_cache_size(), 0, "Invalid vehicle definitions must fail before compilation.")


func _test_reconfigure_clears_runtime_state_but_preserves_cache() -> void:
	var first_manager := FakeVehicleManager.new()
	first_manager.vehicles = [
		_make_actor(_make_arm_definition()),
		_make_actor(_make_transport_definition()),
	]
	var second_manager := FakeVehicleManager.new()
	second_manager.vehicles = [
		_make_actor(_make_arm_definition()),
		_make_actor(_make_transport_definition()),
	]
	var third_manager := FakeVehicleManager.new()
	third_manager.vehicles = second_manager.vehicles.duplicate()

	var gate := GATE_SCRIPT.new()
	gate.configure(first_manager)
	test.expect_true(gate.prepare_scene_run(), "Initial manager should publish a complete batch.")
	test.expect_equal(gate.get_compile_cache_size(), 2, "Initial preparation should populate both compile cache entries.")

	gate.configure(second_manager)
	test.expect_true(gate.get_compile_result(&"arm_vehicle") == null, "Changing manager must clear arm publication from the previous manager.")
	test.expect_true(gate.get_compile_result(&"transport_vehicle") == null, "Changing manager must clear transport publication from the previous manager.")
	test.expect_equal(gate.get_compile_cache_size(), 2, "Changing manager must preserve compiler cache entries.")
	test.expect_equal(gate.get_last_diagnostics().size(), 0, "Changing manager should leave no stale diagnostics.")
	test.expect_equal(gate.get_last_failed_vehicle_id(), &"", "Changing manager should leave no stale failed vehicle id.")

	gate.set_required_capabilities(&"transport_vehicle", [ASSEMBLY_CAPABILITIES_SCRIPT.GRAB_DROP])
	test.expect_false(gate.prepare_scene_run(), "Unsupported requirement should create a failure state for reconfigure cleanup.")
	test.expect_true(gate.get_last_diagnostics().size() > 0, "Failed preparation should publish diagnostics before reconfigure.")
	gate.configure(third_manager)
	test.expect_equal(gate.get_last_diagnostics().size(), 0, "Reconfigure must clear diagnostics tied to the previous manager.")
	test.expect_equal(gate.get_last_failed_vehicle_id(), &"", "Reconfigure must clear the previous failed vehicle id.")
	test.expect_equal(gate.get_compile_cache_size(), 2, "Diagnostic cleanup on reconfigure must not clear compiler cache.")


func _test_invalidate_vehicle_clears_published_batch_but_preserves_other_cache() -> void:
	var manager := FakeVehicleManager.new()
	manager.vehicles = [
		_make_actor(_make_arm_definition()),
		_make_actor(_make_transport_definition()),
	]
	var gate := GATE_SCRIPT.new()
	gate.configure(manager)
	test.expect_true(gate.prepare_scene_run(), "Initial batch should compile before invalidation.")
	var first_transport_result = gate.get_compile_result(&"transport_vehicle")
	test.expect_equal(gate.get_compile_cache_size(), 2, "Initial batch should create two cache entries.")

	gate.invalidate_vehicle(&"arm_vehicle")
	test.expect_true(gate.get_compile_result(&"arm_vehicle") == null, "Invalidating one vehicle should invalidate the published batch.")
	test.expect_true(gate.get_compile_result(&"transport_vehicle") == null, "Published results must remain atomic after one vehicle is invalidated.")
	test.expect_equal(gate.get_compile_cache_size(), 1, "Only the invalidated vehicle cache entry should be removed.")

	test.expect_true(gate.prepare_scene_run(), "Next preparation should rebuild the invalidated vehicle and republish the batch.")
	test.expect_equal(gate.get_compile_cache_size(), 2, "Repreparation should restore the invalidated cache entry.")
	test.expect_true(gate.get_compile_result(&"transport_vehicle") == first_transport_result, "Unchanged transport vehicle should reuse its preserved cache result.")


func _test_same_revision_changed_structure_is_rejected_until_invalidated() -> void:
	var arm_actor = _make_actor(_make_arm_definition())
	var manager := FakeVehicleManager.new()
	manager.vehicles = [arm_actor]
	var gate := GATE_SCRIPT.new()
	gate.configure(manager)
	test.expect_true(gate.prepare_scene_run(), "Initial arm preset should compile.")

	arm_actor.definition = _make_modified_arm_definition()
	test.expect_false(gate.prepare_scene_run(), "Changed preset structure with the same revision should be rejected.")
	var diagnostics := gate.get_last_diagnostics()
	test.expect_true(_has_diagnostic(diagnostics, ASSEMBLY_COMPILER_SCRIPT.DIAGNOSTIC_REVISION_CONTENT_MISMATCH), "Revision/content mismatch should surface the compiler diagnostic.")
	test.expect_true(gate.get_compile_result(&"arm_vehicle") == null, "Mismatch failure should clear published runtime results.")

	gate.invalidate_vehicle(&"arm_vehicle")
	test.expect_equal(gate.get_last_diagnostics().size(), 0, "Invalidation should clear stale compile diagnostics.")
	test.expect_equal(gate.get_last_failed_vehicle_id(), &"", "Invalidation should clear the stale failed vehicle id.")
	test.expect_true(gate.prepare_scene_run(), "Explicit invalidation should allow a changed fixed preset to compile again.")
	test.expect_equal(gate.get_compile_cache_size(), 1, "Recompiled preset should occupy one cache entry after invalidation.")


func _has_diagnostic(diagnostics: Array, code: StringName) -> bool:
	for diagnostic in diagnostics:
		if diagnostic.code == code:
			return true
	return false


func _make_actor(definition):
	var actor := VEHICLE_ACTOR_SCRIPT.new()
	actor.definition = definition
	return actor


func _make_arm_definition():
	return _configure_vehicle_definition(
		&"arm_vehicle",
		VEHICLE_DEFINITION_SCRIPT.VehicleKind.ARM,
		Vector2i(2, 2),
		18.0,
		PackedStringArray([
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_MOVE,
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_GRAB,
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_CARRY,
		])
	)


func _make_modified_arm_definition():
	return _configure_vehicle_definition(
		&"arm_vehicle",
		VEHICLE_DEFINITION_SCRIPT.VehicleKind.ARM,
		Vector2i(1, 2),
		17.0,
		PackedStringArray([
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_MOVE,
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_GRAB,
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_CARRY,
		])
	)


func _make_transport_definition():
	return _configure_vehicle_definition(
		&"transport_vehicle",
		VEHICLE_DEFINITION_SCRIPT.VehicleKind.TRANSPORT,
		Vector2i(2, 2),
		16.0,
		PackedStringArray([
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_MOVE,
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_CARRY,
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_HAS_TRAY,
		])
	)


func _configure_vehicle_definition(
	assembly_id: StringName,
	vehicle_kind: int,
	footprint: Vector2i,
	total_weight: float,
	capabilities: PackedStringArray
):
	var definition := VEHICLE_DEFINITION_SCRIPT.new()
	var carrying_multiplier := 0.25 if vehicle_kind == VEHICLE_DEFINITION_SCRIPT.VehicleKind.ARM else 1.0
	var tray_capacity := 0 if vehicle_kind == VEHICLE_DEFINITION_SCRIPT.VehicleKind.ARM else 8
	test.expect_true(definition.configure(
		assembly_id,
		String(assembly_id),
		vehicle_kind,
		footprint,
		2.0,
		total_weight,
		20.0,
		30.0,
		capabilities,
		carrying_multiplier,
		tray_capacity
	), "Vehicle fixture should configure.")
	return definition
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

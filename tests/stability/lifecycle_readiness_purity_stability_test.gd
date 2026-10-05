extends SceneTree

const LifecycleControllerScript := preload("res://scripts/scene_01/scene_01_lifecycle_controller.gd")
const LifecycleStateScript := preload("res://scripts/scene_01/scene_01_lifecycle_state.gd")
const AvailabilityScript := preload("res://scripts/input/vehicle_command_availability.gd")
const ContractTestScript := preload("res://tests/support/contract_test.gd")


class ProbeGate:
	extends Node

	var can_prepare_count: int = 0
	var prepare_count: int = 0
	var can_prepare_result: bool = true
	var prepare_result: bool = true

	func can_prepare_scene_run() -> bool:
		can_prepare_count += 1
		return can_prepare_result

	func prepare_scene_run() -> bool:
		prepare_count += 1
		return prepare_result


var test = ContractTestScript.new()


func _init() -> void:
	_test_readiness_query_does_not_prepare_or_start()
	_test_rejected_readiness_probe_fails_closed_without_preparation()
	test.finish(self, "Lifecycle readiness purity stability tests")


func _test_readiness_query_does_not_prepare_or_start() -> void:
	var gate := ProbeGate.new()
	var controller = _make_ready_controller(gate)

	test.expect_equal(
		controller.get_lifecycle_state(),
		LifecycleStateScript.State.READY,
		"Readiness fixture should start READY."
	)
	test.expect_equal(
		controller.get_gameplay_command_availability(),
		AvailabilityScript.AVAILABLE,
		"READY lifecycle should report AVAILABLE when the probe gate accepts."
	)
	test.expect_equal(
		gate.can_prepare_count,
		1,
		"Availability should probe can_prepare_scene_run exactly once."
	)
	test.expect_equal(
		gate.prepare_count,
		0,
		"Availability query must not execute prepare_scene_run."
	)
	test.expect_equal(
		controller.get_lifecycle_state(),
		LifecycleStateScript.State.READY,
		"Availability query must not start the lifecycle."
	)

	test.expect_true(
		controller.can_execute_gameplay_command(),
		"Boolean readiness helper should project the same availability truth."
	)
	test.expect_equal(
		gate.can_prepare_count,
		2,
		"Repeated readiness query should remain a probe."
	)
	test.expect_equal(
		gate.prepare_count,
		0,
		"Repeated readiness query must remain side-effect free."
	)

	test.expect_true(
		controller.ensure_gameplay_running(),
		"Explicit gameplay start should cross the preparation boundary."
	)
	test.expect_equal(
		gate.prepare_count,
		1,
		"Explicit start should execute preparation exactly once."
	)
	test.expect_equal(
		controller.get_lifecycle_state(),
		LifecycleStateScript.State.RUNNING,
		"Successful preparation should transition READY to RUNNING."
	)

	controller.free()


func _test_rejected_readiness_probe_fails_closed_without_preparation() -> void:
	var gate := ProbeGate.new()
	gate.can_prepare_result = false
	var controller = _make_ready_controller(gate)

	test.expect_equal(
		controller.get_gameplay_command_availability(),
		AvailabilityScript.PREPARATION_REJECTED,
		"Rejected readiness probe should fail closed."
	)
	test.expect_equal(
		gate.can_prepare_count,
		1,
		"Rejected availability should still use only the probe boundary."
	)
	test.expect_equal(
		gate.prepare_count,
		0,
		"Rejected readiness query must not execute preparation."
	)
	test.expect_equal(
		controller.get_lifecycle_state(),
		LifecycleStateScript.State.READY,
		"Rejected readiness query must leave lifecycle state unchanged."
	)

	controller.free()


func _make_ready_controller(gate: ProbeGate):
	var controller := LifecycleControllerScript.new()
	gate.name = "ProbeGate"
	controller.add_child(gate)
	controller.run_preparation_gate_path = NodePath("ProbeGate")
	controller.set("_scene_initialized", true)
	return controller

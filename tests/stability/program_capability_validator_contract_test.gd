extends SceneTree

const CAPABILITIES_SCRIPT = preload("res://scripts/assembly/assembly_capabilities.gd")
const COMPONENT_SCRIPT = preload("res://scripts/assembly/assembly_component_definition.gd")
const DEFINITION_SCRIPT = preload("res://scripts/assembly/assembly_definition.gd")
const REQUEST_SCRIPT = preload("res://scripts/assembly/assembly_compile_request.gd")
const COMPILER_SCRIPT = preload("res://scripts/assembly/assembly_compiler.gd")
const VALIDATOR_SCRIPT = preload("res://scripts/assembly/program_capability_validator.gd")
const CONTRACT_TEST_SCRIPT = preload("res://tests/support/contract_test.gd")

var test = CONTRACT_TEST_SCRIPT.new()


func _init() -> void:
	_test_missing_capability_is_program_validation_failure()
	_test_supported_capabilities_pass_validation()
	test.finish(self, "Program capability validator contract tests")


func _test_missing_capability_is_program_validation_failure() -> void:
	var move_only = COMPONENT_SCRIPT.new(
		&"drive",
		&"drive_module",
		Vector2i.ZERO,
		0,
		[Vector2i.ZERO],
		[CAPABILITIES_SCRIPT.CAN_MOVE],
		[],
		10,
		4.0
	)
	var compile_result = _compile(DEFINITION_SCRIPT.new(&"move_only", 1, [move_only]))
	test.expect_true(compile_result.is_success(), "Missing GrabDrop capability should not make the assembly invalid.")
	test.expect_equal(compile_result.get_simulation_envelope().size(), 1, "Move-only assembly should still publish collision geometry.")
	var diagnostics = VALIDATOR_SCRIPT.new().validate(
		compile_result,
		[CAPABILITIES_SCRIPT.CAN_MOVE, CAPABILITIES_SCRIPT.GRAB_DROP]
	)
	test.expect_equal(diagnostics.size(), 1, "Only the missing program capability should be reported.")
	if diagnostics.size() == 1:
		test.expect_equal(diagnostics[0].code, VALIDATOR_SCRIPT.DIAGNOSTIC_MISSING_CAPABILITY, "Missing capability should use a stable diagnostic code.")


func _test_supported_capabilities_pass_validation() -> void:
	var drive = COMPONENT_SCRIPT.new(
		&"drive",
		&"drive_module",
		Vector2i.ZERO,
		0,
		[Vector2i.ZERO],
		[CAPABILITIES_SCRIPT.CAN_MOVE, CAPABILITIES_SCRIPT.GRAB_DROP]
	)
	var compile_result = _compile(DEFINITION_SCRIPT.new(&"capable", 1, [drive]))
	var diagnostics = VALIDATOR_SCRIPT.new().validate(
		compile_result,
		[CAPABILITIES_SCRIPT.CAN_MOVE, CAPABILITIES_SCRIPT.GRAB_DROP, CAPABILITIES_SCRIPT.GRAB_DROP]
	)
	test.expect_equal(diagnostics.size(), 0, "Supported capabilities and duplicate requirements should validate cleanly.")


func _compile(definition):
	return COMPILER_SCRIPT.new().compile(REQUEST_SCRIPT.new(definition))

extends SceneTree

const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const SourceScript := preload("res://scripts/scene_01/scene_01_program_source.gd")
const ValidatorScript := preload("res://scripts/scene_01/scene_01_program_validator.gd")
const AssemblyCapabilitiesScript := preload("res://scripts/assembly/assembly_capabilities.gd")

var failures := 0


func _init() -> void:
	_test_source_builds_linear_statements()
	_test_source_diagnostic_physical_line()
	_test_requirements_follow_command_vehicle()
	if failures == 0:
		print("scene_01_program_source_test: PASS")
	quit(failures)


func _test_source_builds_linear_statements() -> void:
	var source := """automata_scene01_program 2
[arm_vehicle:moveTo] 1 3
[arm_vehicle:grabDrop]
[transport_vehicle:moveTo] 2 3
repeat 2 1
"""
	var parsed := SourceScript.new().parse(source)
	_expect_true(parsed["diagnostics"].is_empty(), "Valid v2 source should parse without diagnostics.")
	var program := parsed["program"] as Scene01Program
	_expect_true(program != null, "Valid source should produce a runtime program snapshot.")
	if program == null:
		return
	_expect_equal(program.get_statement_count(), 4, "Source should map one-to-one to four linear statements.")
	var first := program.get_statement(0)
	var third := program.get_statement(2)
	var repeat := program.get_statement(3)
	_expect_equal(int(first.get("type", -1)), ProgramScript.StatementType.MOVE_TO, "First statement should be MoveTo.")
	_expect_equal(StringName(first.get("vehicle_id", &"")), &"arm_vehicle", "First statement should bind Arm explicitly.")
	_expect_equal(StringName(third.get("vehicle_id", &"")), &"transport_vehicle", "Third statement should bind Transport explicitly.")
	_expect_equal(int(repeat.get("repeat_target_index", -1)), 0, "repeat target #1 should resolve to statement index 0.")
	_expect_true(ValidatorScript.new().validate(program, Vector2i(16, 10)).is_empty(), "Parsed source should be structurally valid.")


func _test_source_diagnostic_physical_line() -> void:
	var source := "automata_scene01_program 2\n\n# comment\n\n[arm_vehicle:moveTo] x 3\n"
	var parsed := SourceScript.new().parse(source)
	var diagnostics: Array = parsed["diagnostics"]
	_expect_equal(diagnostics.size(), 1, "Invalid MoveTo should produce one source diagnostic.")
	if not diagnostics.is_empty():
		_expect_equal(int(diagnostics[0].get("line", 0)), 5, "Diagnostic should preserve physical source line numbers.")
		_expect_equal(StringName(diagnostics[0].get("code", &"")), &"move_to_syntax", "Diagnostic should expose a stable code.")


func _test_requirements_follow_command_vehicle() -> void:
	var program := ProgramScript.new()
	var arm_move := program.append_statement(ProgramScript.StatementType.MOVE_TO)
	program.set_statement_vehicle(arm_move, &"arm_vehicle")
	program.set_move_target(arm_move, Vector2i(1, 3))
	var transport_move := program.append_statement(ProgramScript.StatementType.MOVE_TO)
	program.set_statement_vehicle(transport_move, &"transport_vehicle")
	program.set_move_target(transport_move, Vector2i(2, 3))
	var arm_grab := program.append_statement(ProgramScript.StatementType.GRAB_DROP)
	program.set_statement_vehicle(arm_grab, &"arm_vehicle")
	var repeat_index := program.append_statement(ProgramScript.StatementType.REPEAT)
	program.set_repeat(repeat_index, 2, arm_move)

	var validator := ValidatorScript.new()
	_expect_true(validator.validate(program, Vector2i(16, 10)).is_empty(), "Multi-vehicle program should validate structurally.")
	var requirements := validator.required_capabilities_by_vehicle(program)
	_expect_true(requirements.has(&"arm_vehicle"), "Arm requirements should be published.")
	_expect_true(requirements.has(&"transport_vehicle"), "Transport requirements should be published.")
	_expect_true(requirements[&"arm_vehicle"].has(AssemblyCapabilitiesScript.CAN_MOVE), "Arm should require Move capability.")
	_expect_true(requirements[&"arm_vehicle"].has(AssemblyCapabilitiesScript.GRAB_DROP), "Arm should require GrabDrop capability.")
	_expect_true(requirements[&"transport_vehicle"].has(AssemblyCapabilitiesScript.CAN_MOVE), "Transport should require Move capability.")
	_expect_false(requirements[&"transport_vehicle"].has(AssemblyCapabilitiesScript.GRAB_DROP), "Transport should not inherit Arm GrabDrop requirements.")


func _expect_true(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func _expect_false(value: bool, message: String) -> void:
	_expect_true(not value, message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures += 1
		push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])

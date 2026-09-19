extends SceneTree

const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const SourceScript := preload("res://scripts/scene_01/scene_01_program_source.gd")
const ValidatorScript := preload("res://scripts/scene_01/scene_01_program_validator.gd")
const AssemblyCapabilitiesScript := preload("res://scripts/assembly/assembly_capabilities.gd")

var failures := 0

func _init() -> void:
	_test_source_builds_linear_statements()
	_test_source_diagnostic_and_statement_lines()
	_test_repeat_range_rejects_repeat()
	_test_execution_budget()
	_test_requirements_follow_command_vehicle()
	if failures == 0:
		print("scene_01_program_source_test: PASS")
	quit(failures)

func _test_source_builds_linear_statements() -> void:
	var source := """automata_scene01_program 2
[arm_vehicle:moveTo] 1 3
[arm_vehicle:face] west
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
	_expect_equal(program.get_statement_count(), 5, "Source should map one-to-one to five linear statements.")
	_expect_equal(StringName(program.get_statement(0).get("vehicle_id", &"")), &"arm_vehicle", "First statement should bind Arm explicitly.")
	_expect_equal(int(program.get_statement(1).get("type", -1)), ProgramScript.StatementType.FACE, "Second statement should be Face.")
	_expect_equal(int(program.get_statement(1).get("facing", -1)), 3, "Face west should map to the canonical WEST facing value.")
	_expect_equal(StringName(program.get_statement(3).get("vehicle_id", &"")), &"transport_vehicle", "Fourth statement should bind Transport explicitly.")
	_expect_equal(int(program.get_statement(4).get("repeat_target_index", -1)), 0, "repeat target #1 should resolve to statement index 0.")
	_expect_true(ValidatorScript.new().validate(program, Vector2i(16, 10)).is_empty(), "Parsed source should be structurally valid.")

func _test_source_diagnostic_and_statement_lines() -> void:
	var invalid := SourceScript.new().parse("automata_scene01_program 2\n\n# comment\n\n[arm_vehicle:moveTo] x 3\n")
	var diagnostics: Array = invalid["diagnostics"]
	_expect_equal(diagnostics.size(), 1, "Invalid MoveTo should produce one source diagnostic.")
	if not diagnostics.is_empty():
		_expect_equal(int(diagnostics[0].get("line", 0)), 5, "Syntax diagnostic should preserve physical source line numbers.")
	var invalid_face := SourceScript.new().parse("automata_scene01_program 2\n[arm_vehicle:face] diagonal\n")
	_expect_equal(StringName(invalid_face["diagnostics"][0].get("code", &"")), &"face_syntax", "Invalid Face direction should be rejected by the source codec.")
	var mapped := SourceScript.new().parse("automata_scene01_program 2\n\n# comment\n[arm_vehicle:moveTo] 1 3\n\nrepeat 2 1\n")
	_expect_equal(mapped.get("statement_lines", []), [4, 6], "Parser should preserve physical line for every runtime statement.")

func _test_repeat_range_rejects_repeat() -> void:
	var parsed := SourceScript.new().parse("automata_scene01_program 2\n[arm_vehicle:moveTo] 1 3\nrepeat 100 1\nrepeat 100 1\n")
	var program := parsed.get("program") as Scene01Program
	_expect_true(program != null, "Nested Repeat fixture should be syntactically valid.")
	if program == null:
		return
	var diagnostics := ValidatorScript.new().validate(program, Vector2i(16, 10))
	_expect_true(_has_diagnostic(diagnostics, &"nested_repeat_unsupported"), "DSL v2 must reject Repeat ranges containing another Repeat before runtime.")

func _test_execution_budget() -> void:
	var validator := ValidatorScript.new()
	var at_limit := _build_budget_program(99, 100)
	_expect_true(validator.validate(at_limit, Vector2i(16, 10)).is_empty(), "Exactly 10,000 expanded steps should remain valid.")
	var over_limit := _build_budget_program(100, 100)
	var diagnostics := validator.validate(over_limit, Vector2i(16, 10))
	_expect_true(_has_diagnostic(diagnostics, &"program_too_large"), "Programs above 10,000 expanded steps must be rejected before runtime.")
	if not diagnostics.is_empty():
		_expect_equal(int(diagnostics[0].get("statement_index", -1)), 100, "Execution budget rejection should identify the Repeat that crosses the limit.")

func _build_budget_program(move_count: int, repeat_count: int) -> Scene01Program:
	var program := ProgramScript.new()
	for _index in range(move_count):
		var move := program.append_statement(ProgramScript.StatementType.MOVE_TO)
		program.set_statement_vehicle(move, &"arm_vehicle")
		program.set_move_target(move, Vector2i(1, 3))
	var repeat := program.append_statement(ProgramScript.StatementType.REPEAT)
	program.set_repeat(repeat, repeat_count, 0)
	return program

func _test_requirements_follow_command_vehicle() -> void:
	var program := ProgramScript.new()
	var arm_move := program.append_statement(ProgramScript.StatementType.MOVE_TO)
	program.set_statement_vehicle(arm_move, &"arm_vehicle")
	program.set_move_target(arm_move, Vector2i(1, 3))
	var transport_move := program.append_statement(ProgramScript.StatementType.MOVE_TO)
	program.set_statement_vehicle(transport_move, &"transport_vehicle")
	program.set_move_target(transport_move, Vector2i(2, 3))
	var arm_face := program.append_statement(ProgramScript.StatementType.FACE)
	program.set_statement_vehicle(arm_face, &"arm_vehicle")
	program.set_facing(arm_face, 3)
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

func _has_diagnostic(diagnostics: Array[Dictionary], code: StringName) -> bool:
	for diagnostic in diagnostics:
		if StringName(diagnostic.get("code", &"")) == code:
			return true
	return false
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

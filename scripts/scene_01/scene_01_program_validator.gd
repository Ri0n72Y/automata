class_name Scene01ProgramValidator
extends RefCounted

const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const AssemblyCapabilitiesScript := preload("res://scripts/assembly/assembly_capabilities.gd")

const MAX_REPEAT_COUNT := 100
const MAX_EXPANDED_STEPS := 10000

func validate(program: Scene01Program, grid_size: Vector2i = Vector2i.ZERO) -> Array[Dictionary]:
	var diagnostics: Array[Dictionary] = []
	if program == null:
		return [_diagnostic(&"program_required", "Program is required.")]
	if program.get_statement_count() == 0:
		return [_diagnostic(&"statements_required", "Program requires at least one statement.")]
	for index in range(program.get_statement_count()):
		_validate_statement(program, index, grid_size, diagnostics)
	if diagnostics.is_empty():
		_validate_execution_budget(program, diagnostics)
	return diagnostics

func required_capabilities(program: Scene01Program) -> Array[StringName]:
	var result: Array[StringName] = []
	for values in required_capabilities_by_vehicle(program).values():
		for value in values:
			var capability := StringName(value)
			if not result.has(capability):
				result.append(capability)
	return result

func required_capabilities_by_vehicle(program: Scene01Program) -> Dictionary:
	var result: Dictionary = {}
	if program == null:
		return result
	for statement in program.get_statements():
		var vehicle_id := StringName(statement.get("vehicle_id", &""))
		match int(statement.get("type", -1)):
			ProgramScript.StatementType.MOVE_TO:
				_append_requirement(result, vehicle_id, AssemblyCapabilitiesScript.CAN_MOVE)
			ProgramScript.StatementType.GRAB_DROP:
				_append_requirement(result, vehicle_id, AssemblyCapabilitiesScript.GRAB_DROP)
	return result

func _validate_statement(
	program: Scene01Program,
	index: int,
	grid_size: Vector2i,
	diagnostics: Array[Dictionary]
) -> void:
	var statement := program.get_statement(index)
	var statement_type := int(statement.get("type", -1))
	if not _is_valid_type(statement_type):
		diagnostics.append(_diagnostic(&"invalid_statement_type", "Statement type is invalid.", index))
		return
	if statement_type == ProgramScript.StatementType.MOVE_TO or statement_type == ProgramScript.StatementType.GRAB_DROP:
		if StringName(statement.get("vehicle_id", &"")) == &"":
			diagnostics.append(_diagnostic(&"command_vehicle_required", "Vehicle command requires a vehicle id.", index))
	if statement_type == ProgramScript.StatementType.MOVE_TO:
		var target: Vector2i = statement.get("target_anchor", Vector2i(-1, -1))
		if target.x < 0 or target.y < 0:
			diagnostics.append(_diagnostic(&"move_target_required", "MoveTo requires a target anchor.", index))
		elif grid_size.x > 0 and grid_size.y > 0 and (target.x >= grid_size.x or target.y >= grid_size.y):
			diagnostics.append(_diagnostic(&"move_target_out_of_bounds", "MoveTo target is outside the grid.", index))
	elif statement_type == ProgramScript.StatementType.REPEAT:
		_validate_repeat(program, statement, index, diagnostics)

func _validate_repeat(
	program: Scene01Program,
	statement: Dictionary,
	index: int,
	diagnostics: Array[Dictionary]
) -> void:
	var repeat_count := int(statement.get("repeat_count", 0))
	if repeat_count < 1 or repeat_count > MAX_REPEAT_COUNT:
		diagnostics.append(_diagnostic(&"invalid_repeat_count", "Repeat count must be between 1 and %d." % MAX_REPEAT_COUNT, index))
	var target_index := int(statement.get("repeat_target_index", ProgramScript.NO_STATEMENT_INDEX))
	if target_index < 0 or target_index >= index:
		diagnostics.append(_diagnostic(&"invalid_repeat_target", "Repeat target must reference an earlier vehicle statement.", index))
		return
	var target_type := int(program.get_statement(target_index).get("type", -1))
	if target_type != ProgramScript.StatementType.MOVE_TO and target_type != ProgramScript.StatementType.GRAB_DROP:
		diagnostics.append(_diagnostic(&"invalid_repeat_target", "Repeat target must reference an earlier vehicle statement.", index))
		return
	for nested_index in range(target_index, index):
		if int(program.get_statement(nested_index).get("type", -1)) == ProgramScript.StatementType.REPEAT:
			diagnostics.append(_diagnostic(&"nested_repeat_unsupported", "Repeat ranges cannot contain another Repeat in DSL v2.", index))
			return

func _validate_execution_budget(program: Scene01Program, diagnostics: Array[Dictionary]) -> void:
	var expanded_steps := program.get_statement_count()
	if expanded_steps > MAX_EXPANDED_STEPS:
		diagnostics.append(_diagnostic(&"program_too_large", "Expanded Program exceeds %d execution steps." % MAX_EXPANDED_STEPS, MAX_EXPANDED_STEPS))
		return
	for index in range(program.get_statement_count()):
		var statement := program.get_statement(index)
		if int(statement.get("type", -1)) != ProgramScript.StatementType.REPEAT:
			continue
		var target_index := int(statement.get("repeat_target_index", ProgramScript.NO_STATEMENT_INDEX))
		var repeat_count := int(statement.get("repeat_count", 1))
		expanded_steps += (repeat_count - 1) * (index - target_index + 1)
		if expanded_steps > MAX_EXPANDED_STEPS:
			diagnostics.append(_diagnostic(&"program_too_large", "Expanded Program exceeds %d execution steps." % MAX_EXPANDED_STEPS, index))
			return

func _append_requirement(result: Dictionary, vehicle_id: StringName, capability: StringName) -> void:
	if vehicle_id == &"":
		return
	var capabilities: Array[StringName] = []
	if result.has(vehicle_id):
		for value in result[vehicle_id]:
			capabilities.append(StringName(value))
	if not capabilities.has(capability):
		capabilities.append(capability)
	result[vehicle_id] = capabilities

func _is_valid_type(statement_type: int) -> bool:
	return statement_type in [
		ProgramScript.StatementType.MOVE_TO,
		ProgramScript.StatementType.GRAB_DROP,
		ProgramScript.StatementType.REPEAT,
	]

func _diagnostic(code: StringName, message: String, statement_index: int = -1) -> Dictionary:
	return {"code": code, "message": message, "statement_index": statement_index}

class_name Scene01ProgramValidator
extends RefCounted

const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const AssemblyCapabilitiesScript := preload("res://scripts/assembly/assembly_capabilities.gd")

const MAX_REPEAT_COUNT := 100


func validate(program: Scene01Program, grid_size: Vector2i = Vector2i.ZERO) -> Array[Dictionary]:
	var diagnostics: Array[Dictionary] = []
	if program == null:
		return [_diagnostic(&"program_required", "Program is required.")]
	if program.statements.is_empty():
		return [_diagnostic(&"statements_required", "Program requires at least one statement.")]
	for index in range(program.statements.size()):
		_validate_statement(program.statements[index], index, grid_size, diagnostics)
	return diagnostics


func required_capabilities_by_vehicle(program: Scene01Program) -> Dictionary:
	var result: Dictionary = {}
	if program == null:
		return result
	for statement in program.statements:
		var vehicle_id := StringName(statement.get("vehicle_id", &""))
		match int(statement.get("type", -1)):
			ProgramScript.StatementType.MOVE_TO:
				_append_requirement(result, vehicle_id, AssemblyCapabilitiesScript.CAN_MOVE)
			ProgramScript.StatementType.GRAB_DROP:
				_append_requirement(result, vehicle_id, AssemblyCapabilitiesScript.GRAB_DROP)
	return result


func required_capabilities(program: Scene01Program) -> Array[StringName]:
	var result: Array[StringName] = []
	for values in required_capabilities_by_vehicle(program).values():
		for value in values:
			var capability := StringName(value)
			if not result.has(capability):
				result.append(capability)
	return result


func _validate_statement(statement: Dictionary, index: int, grid_size: Vector2i, diagnostics: Array[Dictionary]) -> void:
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
	if statement_type == ProgramScript.StatementType.REPEAT:
		var count := int(statement.get("repeat_count", 0))
		var target := int(statement.get("repeat_target_index", -1))
		if count < 1 or count > MAX_REPEAT_COUNT:
			diagnostics.append(_diagnostic(&"invalid_repeat_count", "Repeat count is invalid.", index))
		if target < 0 or target >= index:
			diagnostics.append(_diagnostic(&"invalid_repeat_target", "Repeat target must reference an earlier statement.", index))


func _append_requirement(result: Dictionary, vehicle_id: StringName, capability: StringName) -> void:
	if vehicle_id == &"":
		return
	if not result.has(vehicle_id):
		result[vehicle_id] = []
	var values: Array[StringName] = result[vehicle_id]
	if not values.has(capability):
		values.append(capability)
	result[vehicle_id] = values


func _is_valid_type(statement_type: int) -> bool:
	return statement_type in [
		ProgramScript.StatementType.MOVE_TO,
		ProgramScript.StatementType.GRAB_DROP,
		ProgramScript.StatementType.REPEAT,
	]


func _diagnostic(code: StringName, message: String, index: int = -1) -> Dictionary:
	return {"code": code, "message": message, "statement_index": index}

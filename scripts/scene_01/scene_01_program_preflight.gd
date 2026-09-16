class_name Scene01ProgramPreflight
extends RefCounted

const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const ValidatorScript := preload("res://scripts/scene_01/scene_01_program_validator.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const CompileGateScript := preload("res://scripts/scene_01/scene_01_assembly_compile_gate.gd")
const MissionControllerScript := preload("res://scripts/scene_01/scene_01_mission_controller.gd")

var _validator := ValidatorScript.new()


func prepare(
	program: Scene01Program,
	scene_controller: MissionControllerScript,
	vehicle_manager: VehicleManagerScript,
	compile_gate: CompileGateScript
) -> Dictionary:
	var diagnostics := _validator.validate(program, scene_controller.get_grid_size())
	if not diagnostics.is_empty():
		var first: Dictionary = diagnostics[0]
		return _failure(
			StringName(first.get("code", &"program_invalid")),
			int(first.get("statement_index", ProgramScript.NO_STATEMENT_INDEX))
		)

	var requirement_vehicle_ids: Array[StringName] = []
	var requirements := _validator.required_capabilities_by_vehicle(program)
	for vehicle_value in requirements.keys():
		var vehicle_id := StringName(vehicle_value)
		var vehicle := vehicle_manager.get_vehicle_by_id(vehicle_id)
		if vehicle == null or vehicle.definition == null or vehicle.runtime_state == null:
			_clear_requirements(compile_gate, requirement_vehicle_ids)
			return _failure(&"program_vehicle_missing")
		var required: Array[StringName] = []
		for capability_value in requirements[vehicle_value]:
			required.append(StringName(capability_value))
		compile_gate.set_required_capabilities(vehicle_id, required)
		requirement_vehicle_ids.append(vehicle_id)

	for index in range(program.get_statement_count()):
		var statement := program.get_statement(index)
		if int(statement.get("type", -1)) != ProgramScript.StatementType.MOVE_TO:
			continue
		var vehicle_id := StringName(statement.get("vehicle_id", &""))
		var vehicle := vehicle_manager.get_vehicle_by_id(vehicle_id)
		if vehicle == null or vehicle.definition == null or vehicle.runtime_state == null:
			_clear_requirements(compile_gate, requirement_vehicle_ids)
			return _failure(&"program_vehicle_missing", index)
		var target: Vector2i = statement.get("target_anchor", Vector2i(-1, -1))
		if not scene_controller.is_grid_footprint_walkable(target, vehicle.definition.footprint):
			_clear_requirements(compile_gate, requirement_vehicle_ids)
			return _failure(&"move_target_not_walkable", index)

	if not compile_gate.prepare_scene_run():
		_clear_requirements(compile_gate, requirement_vehicle_ids)
		return _failure(&"program_capability_rejected")
	return {
		"ok": true,
		"reason": &"",
		"statement_index": ProgramScript.NO_STATEMENT_INDEX,
		"requirement_vehicle_ids": requirement_vehicle_ids,
	}


func _clear_requirements(
	compile_gate: CompileGateScript,
	vehicle_ids: Array[StringName]
) -> void:
	for vehicle_id in vehicle_ids:
		var empty: Array[StringName] = []
		compile_gate.set_required_capabilities(vehicle_id, empty)


func _failure(
	reason: StringName,
	statement_index: int = ProgramScript.NO_STATEMENT_INDEX
) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"statement_index": statement_index,
		"requirement_vehicle_ids": [],
	}

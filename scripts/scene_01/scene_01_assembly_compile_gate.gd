class_name Scene01AssemblyCompileGate
extends Node

signal assembly_compile_prepared()
signal assembly_compile_failed(vehicle_id: StringName, diagnostics: Array)

const AssemblyCompileDiagnosticScript := preload("res://scripts/assembly/assembly_compile_diagnostic.gd")
const AssemblyCompileRequestScript := preload("res://scripts/assembly/assembly_compile_request.gd")
const AssemblyCompilerScript := preload("res://scripts/assembly/assembly_compiler.gd")
const ProgramCapabilityValidatorScript := preload("res://scripts/assembly/program_capability_validator.gd")
const Scene01AssemblyDefinitionAdapterScript := preload("res://scripts/scene_01/scene_01_assembly_definition_adapter.gd")
const VehicleActorScript := preload("res://scripts/vehicles/vehicle_actor.gd")

const DIAGNOSTIC_VEHICLE_MANAGER_REQUIRED: StringName = &"vehicle_manager_required"
const DIAGNOSTIC_VEHICLES_REQUIRED: StringName = &"vehicles_required"
const DIAGNOSTIC_VEHICLE_DEFINITION_INVALID: StringName = &"vehicle_definition_invalid"
const DIAGNOSTIC_DUPLICATE_VEHICLE_ID: StringName = &"duplicate_vehicle_id"

@export var vehicle_manager_path: NodePath = NodePath()

var _vehicle_manager: Node
var _adapter := Scene01AssemblyDefinitionAdapterScript.new()
var _compiler := AssemblyCompilerScript.new()
var _capability_validator := ProgramCapabilityValidatorScript.new()
var _required_capabilities: Dictionary = {}
var _compiled_results: Dictionary = {}
var _last_diagnostics: Array = []
var _last_failed_vehicle_id: StringName = &""


func _ready() -> void:
	if not vehicle_manager_path.is_empty():
		configure(get_node_or_null(vehicle_manager_path))


func configure(vehicle_manager: Node) -> void:
	_vehicle_manager = vehicle_manager


func prepare_scene_run() -> bool:
	if _vehicle_manager == null or not is_instance_valid(_vehicle_manager):
		return _fail(&"", [
			AssemblyCompileDiagnosticScript.new(
				DIAGNOSTIC_VEHICLE_MANAGER_REQUIRED,
				"Scene 01 assembly compile requires a vehicle manager."
			)
		])
	if not _vehicle_manager.has_method("get_vehicles"):
		return _fail(&"", [
			AssemblyCompileDiagnosticScript.new(
				DIAGNOSTIC_VEHICLE_MANAGER_REQUIRED,
				"Scene 01 vehicle manager must expose get_vehicles()."
			)
		])

	var vehicle_nodes: Array = _vehicle_manager.call("get_vehicles")
	if vehicle_nodes.is_empty():
		return _fail(&"", [
			AssemblyCompileDiagnosticScript.new(
				DIAGNOSTIC_VEHICLES_REQUIRED,
				"Scene 01 assembly compile requires at least one participating vehicle."
			)
		])

	var candidate_results: Dictionary = {}
	for vehicle_node in vehicle_nodes:
		var vehicle := vehicle_node as VehicleActorScript
		if vehicle == null or vehicle.definition == null:
			return _fail(&"", [
				AssemblyCompileDiagnosticScript.new(
					DIAGNOSTIC_VEHICLE_DEFINITION_INVALID,
					"Participating vehicle is missing a configured definition."
				)
			])
		var vehicle_id := vehicle.get_vehicle_id()
		if vehicle_id == &"" or candidate_results.has(vehicle_id):
			return _fail(vehicle_id, [
				AssemblyCompileDiagnosticScript.new(
					DIAGNOSTIC_DUPLICATE_VEHICLE_ID,
					"Participating vehicle ids must be unique."
				)
			])

		var assembly_definition = _adapter.build_definition(vehicle)
		if assembly_definition == null:
			return _fail(vehicle_id, [
				AssemblyCompileDiagnosticScript.new(
					DIAGNOSTIC_VEHICLE_DEFINITION_INVALID,
					"Vehicle definition cannot be adapted for assembly compilation."
				)
			])
		var compile_result = _compiler.compile(
			AssemblyCompileRequestScript.new(assembly_definition)
		)
		if not compile_result.is_success():
			return _fail(vehicle_id, compile_result.get_diagnostics())

		var required: Array[StringName] = _requirements_for(vehicle_id)
		var capability_diagnostics := _capability_validator.validate(
			compile_result,
			required
		)
		if not capability_diagnostics.is_empty():
			return _fail(vehicle_id, capability_diagnostics)
		candidate_results[vehicle_id] = compile_result

	_compiled_results = candidate_results
	_last_diagnostics.clear()
	_last_failed_vehicle_id = &""
	assembly_compile_prepared.emit()
	return true


func set_required_capabilities(
	vehicle_id: StringName,
	capabilities: Array[StringName]
) -> void:
	if capabilities.is_empty():
		_required_capabilities.erase(vehicle_id)
		return
	_required_capabilities[vehicle_id] = capabilities.duplicate()


func clear_required_capabilities() -> void:
	_required_capabilities.clear()


func get_compile_result(vehicle_id: StringName):
	return _compiled_results.get(vehicle_id)


func has_vehicle_capability(vehicle_id: StringName, capability: StringName) -> bool:
	var result = get_compile_result(vehicle_id)
	return result != null and result.is_success() and result.has_capability(capability)


func get_last_diagnostics() -> Array:
	var result: Array = []
	for diagnostic in _last_diagnostics:
		if diagnostic != null and diagnostic.has_method("duplicate_diagnostic"):
			result.append(diagnostic.duplicate_diagnostic())
	return result


func get_last_failed_vehicle_id() -> StringName:
	return _last_failed_vehicle_id


func get_compile_cache_size() -> int:
	return _compiler.get_cache_size()


func invalidate_vehicle(vehicle_id: StringName) -> void:
	_compiler.invalidate(vehicle_id)
	_compiled_results.erase(vehicle_id)


func clear_runtime_results() -> void:
	_compiled_results.clear()
	_last_diagnostics.clear()
	_last_failed_vehicle_id = &""


func _requirements_for(vehicle_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	var stored: Variant = _required_capabilities.get(vehicle_id)
	if stored is Array:
		for capability in stored:
			result.append(StringName(capability))
	return result


func _fail(vehicle_id: StringName, diagnostics: Array) -> bool:
	_compiled_results.clear()
	_last_failed_vehicle_id = vehicle_id
	_last_diagnostics.clear()
	for diagnostic in diagnostics:
		if diagnostic != null and diagnostic.has_method("duplicate_diagnostic"):
			_last_diagnostics.append(diagnostic.duplicate_diagnostic())
	assembly_compile_failed.emit(vehicle_id, get_last_diagnostics())
	return false

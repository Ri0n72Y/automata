class_name AssemblyCompileResult
extends RefCounted

var assembly_id: StringName = &""
var revision: int = -1
var success: bool = false
var capabilities: AssemblyCapabilitySet
var simulation_envelope: AssemblySimulationEnvelope
var metrics: AssemblyMetrics
var _interaction_interfaces: Array[AssemblyInteractionInterface] = []
var _diagnostics: Array[AssemblyCompileDiagnostic] = []


func _init(
	result_assembly_id: StringName = &"",
	result_revision: int = -1,
	result_success: bool = false,
	result_capabilities: AssemblyCapabilitySet = null,
	result_interfaces: Array = [],
	result_envelope: AssemblySimulationEnvelope = null,
	result_metrics: AssemblyMetrics = null,
	result_diagnostics: Array = []
) -> void:
	assembly_id = result_assembly_id
	revision = result_revision
	success = result_success
	capabilities = result_capabilities if result_capabilities != null else AssemblyCapabilitySet.new()
	simulation_envelope = result_envelope if result_envelope != null else AssemblySimulationEnvelope.new()
	metrics = result_metrics if result_metrics != null else AssemblyMetrics.new()
	_interaction_interfaces = []
	for interface_value in result_interfaces:
		if interface_value is AssemblyInteractionInterface:
			_interaction_interfaces.append(interface_value.duplicate_descriptor())
	_diagnostics = []
	for diagnostic in result_diagnostics:
		if diagnostic is AssemblyCompileDiagnostic:
			_diagnostics.append(diagnostic.duplicate_diagnostic())


func has_capability(capability: StringName) -> bool:
	return capabilities.has(capability)


func get_interaction_interfaces() -> Array[AssemblyInteractionInterface]:
	var result: Array[AssemblyInteractionInterface] = []
	for interface_value in _interaction_interfaces:
		result.append(interface_value.duplicate_descriptor())
	return result


func get_diagnostics() -> Array[AssemblyCompileDiagnostic]:
	var result: Array[AssemblyCompileDiagnostic] = []
	for diagnostic in _diagnostics:
		result.append(diagnostic.duplicate_diagnostic())
	return result

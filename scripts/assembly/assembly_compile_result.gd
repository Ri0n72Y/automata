class_name AssemblyCompileResult
extends RefCounted

var _assembly_id: StringName = &""
var _revision: AssemblyRevision = AssemblyRevision.new()
var _success: bool = false
var _capabilities: AssemblyCapabilitySet = AssemblyCapabilitySet.new()
var _simulation_envelope: AssemblySimulationEnvelope = AssemblySimulationEnvelope.new()
var _metrics: AssemblyMetrics = AssemblyMetrics.new()
var _interaction_interfaces: Array[AssemblyInteractionInterface] = []
var _diagnostics: Array[AssemblyCompileDiagnostic] = []


func _init(
	result_revision: AssemblyRevision = null,
	result_success: bool = false,
	result_capabilities: AssemblyCapabilitySet = null,
	result_interfaces: Array = [],
	result_envelope: AssemblySimulationEnvelope = null,
	result_metrics: AssemblyMetrics = null,
	result_diagnostics: Array = []
) -> void:
	_revision = result_revision.duplicate_revision() if result_revision != null else AssemblyRevision.new()
	_assembly_id = _revision.get_assembly_id()
	_success = result_success
	_capabilities = result_capabilities if result_capabilities != null else AssemblyCapabilitySet.new()
	_simulation_envelope = result_envelope if result_envelope != null else AssemblySimulationEnvelope.new()
	_metrics = result_metrics.duplicate_metrics() if result_metrics != null else AssemblyMetrics.new()
	_interaction_interfaces = []
	for interface_value in result_interfaces:
		if interface_value is AssemblyInteractionInterface:
			_interaction_interfaces.append(interface_value.duplicate_descriptor())
	_diagnostics = []
	for diagnostic in result_diagnostics:
		if diagnostic is AssemblyCompileDiagnostic:
			_diagnostics.append(diagnostic.duplicate_diagnostic())


func is_success() -> bool:
	return _success


func get_assembly_id() -> StringName:
	return _assembly_id


func get_revision() -> AssemblyRevision:
	return _revision.duplicate_revision()


func has_capability(capability: StringName) -> bool:
	return _capabilities.has(capability)


func get_capabilities() -> Array[StringName]:
	return _capabilities.to_array()


func get_simulation_envelope() -> AssemblySimulationEnvelope:
	return AssemblySimulationEnvelope.new(_simulation_envelope.get_occupied_cells())


func get_metrics() -> AssemblyMetrics:
	return _metrics.duplicate_metrics()


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

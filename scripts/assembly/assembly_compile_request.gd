class_name AssemblyCompileRequest
extends RefCounted

var _definition: AssemblyDefinition
var _revision: AssemblyRevision
var _structure_signature: Array = []


func _init(definition: AssemblyDefinition = null) -> void:
	if definition == null:
		_definition = null
		_revision = AssemblyRevision.new()
		return
	_definition = definition.snapshot()
	_revision = AssemblyRevision.new(_definition.assembly_id, _definition.revision)
	_structure_signature = _compute_structure_signature(_definition)


func has_definition() -> bool:
	return _definition != null


func get_definition() -> AssemblyDefinition:
	if _definition == null:
		return null
	return _definition.snapshot()


func get_revision() -> AssemblyRevision:
	return _revision.duplicate_revision()


func get_structure_signature() -> Array:
	return _structure_signature.duplicate(true)


func is_cacheable() -> bool:
	return _revision.is_cacheable()


func _compute_structure_signature(definition: AssemblyDefinition) -> Array:
	var signature: Array = [definition.assembly_id, definition.revision]
	for component in definition.get_components():
		var interface_data: Array = []
		for interface_value in component.interaction_interfaces:
			interface_data.append([
				interface_value.kind,
				interface_value.cells.duplicate(),
				interface_value.metadata.duplicate(true),
				interface_value.coordinate_space,
			])
		signature.append([
			component.component_id,
			component.component_type,
			component.origin,
			component.orientation_quarters,
			component.occupied_cells.duplicate(),
			component.capabilities.duplicate(),
			interface_data,
			component.cost,
			component.mass,
		])
	return signature

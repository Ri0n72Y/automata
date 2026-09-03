class_name AssemblyDefinition
extends RefCounted

var assembly_id: StringName = &""
var revision: int = 0
var _components: Array[AssemblyComponentDefinition] = []
var _invalid_component_entry_count: int = 0


func _init(id: StringName = &"", assembly_revision: int = 0, components: Array = []) -> void:
	assembly_id = id
	revision = assembly_revision
	_components = []
	_invalid_component_entry_count = 0
	for component in components:
		if component is AssemblyComponentDefinition:
			_components.append(component.snapshot())
		else:
			_invalid_component_entry_count += 1


func get_components() -> Array[AssemblyComponentDefinition]:
	var result: Array[AssemblyComponentDefinition] = []
	for component in _components:
		result.append(component.snapshot())
	return result


func get_invalid_component_entry_count() -> int:
	return _invalid_component_entry_count


func snapshot() -> AssemblyDefinition:
	var result := AssemblyDefinition.new(assembly_id, revision, _components)
	result._invalid_component_entry_count = _invalid_component_entry_count
	return result

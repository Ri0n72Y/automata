class_name AssemblyDefinition
extends RefCounted

var assembly_id: StringName = &""
var revision: int = 0
var _components: Array[AssemblyComponentDefinition] = []


func _init(id: StringName = &"", assembly_revision: int = 0, components: Array = []) -> void:
	assembly_id = id
	revision = assembly_revision
	_components = []
	for component in components:
		if component is AssemblyComponentDefinition:
			_components.append(component.snapshot())


func get_components() -> Array[AssemblyComponentDefinition]:
	var result: Array[AssemblyComponentDefinition] = []
	for component in _components:
		result.append(component.snapshot())
	return result


func get_revision() -> AssemblyRevision:
	return AssemblyRevision.new(assembly_id, revision)


func snapshot() -> AssemblyDefinition:
	return AssemblyDefinition.new(assembly_id, revision, _components)

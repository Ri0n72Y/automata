class_name AssemblyCompileRequest
extends RefCounted

var _definition: AssemblyDefinition
var _revision: AssemblyRevision


func _init(definition: AssemblyDefinition = null) -> void:
	if definition == null:
		_definition = null
		_revision = AssemblyRevision.new()
		return
	_definition = definition.snapshot()
	_revision = AssemblyRevision.new(_definition.assembly_id, _definition.revision)


func has_definition() -> bool:
	return _definition != null


func get_definition() -> AssemblyDefinition:
	if _definition == null:
		return null
	return _definition.snapshot()


func get_revision() -> AssemblyRevision:
	return _revision.duplicate_revision()


func is_cacheable() -> bool:
	return _revision.is_cacheable()


func cache_key() -> String:
	return _revision.cache_key()

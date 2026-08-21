class_name AssemblyRevision
extends RefCounted

var _assembly_id: StringName = &""
var _value: int = -1


func _init(assembly_id: StringName = &"", value: int = -1) -> void:
	_assembly_id = assembly_id
	_value = value


func get_assembly_id() -> StringName:
	return _assembly_id


func get_value() -> int:
	return _value


func is_cacheable() -> bool:
	return _assembly_id != &"" and _value >= 0


func cache_key() -> String:
	return "%s@%d" % [String(_assembly_id), _value]


func duplicate_revision() -> AssemblyRevision:
	return AssemblyRevision.new(_assembly_id, _value)

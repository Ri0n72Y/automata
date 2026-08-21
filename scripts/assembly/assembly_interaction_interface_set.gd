class_name AssemblyInteractionInterfaceSet
extends RefCounted

var _interfaces: Array[AssemblyInteractionInterface] = []


func _init(interfaces: Array = []) -> void:
	_interfaces = []
	for interface_value in interfaces:
		if interface_value is AssemblyInteractionInterface:
			_interfaces.append(interface_value.duplicate_descriptor())


func size() -> int:
	return _interfaces.size()


func to_array() -> Array[AssemblyInteractionInterface]:
	var result: Array[AssemblyInteractionInterface] = []
	for interface_value in _interfaces:
		result.append(interface_value.duplicate_descriptor())
	return result


func get_by_kind(kind: StringName) -> Array[AssemblyInteractionInterface]:
	var result: Array[AssemblyInteractionInterface] = []
	for interface_value in _interfaces:
		if interface_value.kind == kind:
			result.append(interface_value.duplicate_descriptor())
	return result

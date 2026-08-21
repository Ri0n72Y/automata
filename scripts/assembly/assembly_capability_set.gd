class_name AssemblyCapabilitySet
extends RefCounted

var _values: Dictionary = {}


func _init(capability_names: Array[StringName] = []) -> void:
	_values = {}
	for capability in capability_names:
		if capability != &"":
			_values[capability] = true


func has(capability: StringName) -> bool:
	return _values.has(capability)


func size() -> int:
	return _values.size()


func to_array() -> Array[StringName]:
	var result: Array[StringName] = []
	for capability in _values.keys():
		result.append(capability)
	return result

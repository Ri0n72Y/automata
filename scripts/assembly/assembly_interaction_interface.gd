class_name AssemblyInteractionInterface
extends RefCounted

enum CoordinateSpace {
	COMPONENT_LOCAL,
	ASSEMBLY_LOCAL,
}

var owner_component_id: StringName = &""
var kind: StringName = &""
var cells: Array[Vector2i] = []
## Metadata is compile-time data only. Keys must be String/StringName and values
## may be nil, bool, int, finite float, String, or StringName. Nested containers
## and Objects/Resources are rejected by AssemblyCompiler.
var metadata: Dictionary = {}
var coordinate_space: int = CoordinateSpace.COMPONENT_LOCAL
var _metadata_is_valid: bool = true


func _init(
	interface_kind: StringName = &"",
	interface_cells: Array[Vector2i] = [],
	interface_metadata: Dictionary = {},
	component_id: StringName = &"",
	interface_coordinate_space: int = CoordinateSpace.COMPONENT_LOCAL
) -> void:
	owner_component_id = component_id
	kind = interface_kind
	cells = interface_cells.duplicate()
	_metadata_is_valid = _is_metadata_valid(interface_metadata)
	metadata = interface_metadata.duplicate() if _metadata_is_valid else {}
	coordinate_space = interface_coordinate_space


func is_component_local() -> bool:
	return coordinate_space == CoordinateSpace.COMPONENT_LOCAL


func is_assembly_local() -> bool:
	return coordinate_space == CoordinateSpace.ASSEMBLY_LOCAL


func is_metadata_valid() -> bool:
	return _metadata_is_valid


func duplicate_descriptor() -> AssemblyInteractionInterface:
	var result := AssemblyInteractionInterface.new(
		kind,
		cells,
		metadata,
		owner_component_id,
		coordinate_space
	)
	result._metadata_is_valid = _metadata_is_valid and result._metadata_is_valid
	return result


func _is_metadata_valid(value: Dictionary) -> bool:
	for key in value.keys():
		var key_type := typeof(key)
		if key_type != TYPE_STRING and key_type != TYPE_STRING_NAME:
			return false
		var metadata_value: Variant = value[key]
		var value_type := typeof(metadata_value)
		if (
			value_type == TYPE_NIL
			or value_type == TYPE_BOOL
			or value_type == TYPE_INT
			or value_type == TYPE_STRING
			or value_type == TYPE_STRING_NAME
		):
			continue
		if value_type == TYPE_FLOAT and is_finite(float(metadata_value)):
			continue
		return false
	return true

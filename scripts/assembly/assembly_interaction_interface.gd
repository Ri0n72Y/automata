class_name AssemblyInteractionInterface
extends RefCounted

enum CoordinateSpace {
	COMPONENT_LOCAL,
	ASSEMBLY_LOCAL,
}

var owner_component_id: StringName = &""
var kind: StringName = &""
var cells: Array[Vector2i] = []
var metadata: Dictionary = {}
var coordinate_space: int = CoordinateSpace.COMPONENT_LOCAL


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
	metadata = interface_metadata.duplicate(true)
	coordinate_space = interface_coordinate_space


func is_component_local() -> bool:
	return coordinate_space == CoordinateSpace.COMPONENT_LOCAL


func is_assembly_local() -> bool:
	return coordinate_space == CoordinateSpace.ASSEMBLY_LOCAL


func duplicate_descriptor() -> AssemblyInteractionInterface:
	return AssemblyInteractionInterface.new(
		kind,
		cells,
		metadata,
		owner_component_id,
		coordinate_space
	)

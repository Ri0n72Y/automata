class_name AssemblyInteractionInterface
extends RefCounted

var owner_component_id: StringName = &""
var kind: StringName = &""
var cells: Array[Vector2i] = []
var metadata: Dictionary = {}


func _init(
	interface_kind: StringName = &"",
	interface_cells: Array[Vector2i] = [],
	interface_metadata: Dictionary = {},
	component_id: StringName = &""
) -> void:
	owner_component_id = component_id
	kind = interface_kind
	cells = interface_cells.duplicate()
	metadata = interface_metadata.duplicate(true)


func duplicate_descriptor() -> AssemblyInteractionInterface:
	return AssemblyInteractionInterface.new(kind, cells, metadata, owner_component_id)

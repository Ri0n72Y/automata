class_name AssemblyComponentDefinition
extends RefCounted

var component_id: StringName = &""
var component_type: StringName = &""
var origin: Vector2i = Vector2i.ZERO
var orientation_quarters: int = 0
var occupied_cells: Array[Vector2i] = []
var capabilities: Array[StringName] = []
var interaction_interfaces: Array[AssemblyInteractionInterface] = []
var cost: int = 0
var mass: float = 0.0


func _init(
	id: StringName = &"",
	type_name: StringName = &"",
	component_origin: Vector2i = Vector2i.ZERO,
	component_orientation_quarters: int = 0,
	component_occupied_cells: Array[Vector2i] = [],
	provided_capabilities: Array[StringName] = [],
	interfaces: Array = [],
	component_cost: int = 0,
	component_mass: float = 0.0
) -> void:
	component_id = id
	component_type = type_name
	origin = component_origin
	orientation_quarters = component_orientation_quarters
	occupied_cells = component_occupied_cells.duplicate()
	capabilities = provided_capabilities.duplicate()
	interaction_interfaces = []
	for interface_value in interfaces:
		if interface_value is AssemblyInteractionInterface:
			interaction_interfaces.append(interface_value.duplicate_descriptor())
	cost = component_cost
	mass = component_mass


func snapshot() -> AssemblyComponentDefinition:
	return AssemblyComponentDefinition.new(
		component_id,
		component_type,
		origin,
		orientation_quarters,
		occupied_cells,
		capabilities,
		interaction_interfaces,
		cost,
		mass
	)

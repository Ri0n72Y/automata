class_name Scene01AssemblyDefinitionAdapter
extends RefCounted

const AssemblyCapabilitiesScript := preload("res://scripts/assembly/assembly_capabilities.gd")
const AssemblyComponentDefinitionScript := preload("res://scripts/assembly/assembly_component_definition.gd")
const AssemblyDefinitionScript := preload("res://scripts/assembly/assembly_definition.gd")
const AssemblyInteractionInterfaceScript := preload("res://scripts/assembly/assembly_interaction_interface.gd")
const VehicleActorScript := preload("res://scripts/vehicles/vehicle_actor.gd")
const VehicleDefinitionScript := preload("res://scripts/vehicles/vehicle_definition.gd")

const PRESET_REVISION := 1
const ROOT_COMPONENT_ID: StringName = &"vehicle"
const GRAB_DROP_INTERFACE_KIND: StringName = &"grab_drop"


func build_definition(vehicle: VehicleActorScript) -> AssemblyDefinitionScript:
	if vehicle == null or vehicle.definition == null:
		return null
	var vehicle_definition: VehicleDefinitionScript = vehicle.definition
	if not vehicle_definition.is_configured():
		return null

	var occupied_cells: Array[Vector2i] = []
	for offset_y in range(vehicle_definition.footprint.y):
		for offset_x in range(vehicle_definition.footprint.x):
			occupied_cells.append(Vector2i(offset_x, offset_y))

	var capabilities: Array[StringName] = []
	if vehicle_definition.can_move():
		capabilities.append(AssemblyCapabilitiesScript.CAN_MOVE)
	if vehicle_definition.has_capability(VehicleDefinitionScript.CAPABILITY_CAN_GRAB):
		capabilities.append(AssemblyCapabilitiesScript.GRAB_DROP)

	var interfaces: Array = []
	if vehicle_definition.has_capability(VehicleDefinitionScript.CAPABILITY_CAN_GRAB):
		var forward_cells: Array[Vector2i] = []
		for offset_y in range(vehicle_definition.footprint.y):
			forward_cells.append(Vector2i(vehicle_definition.footprint.x, offset_y))
		interfaces.append(AssemblyInteractionInterfaceScript.new(
			GRAB_DROP_INTERFACE_KIND,
			forward_cells,
			{
				"orientation_mode": "vehicle_facing",
				"template_facing": "east",
			},
			ROOT_COMPONENT_ID
		))

	var component_type := _component_type_for(vehicle_definition)
	if component_type == &"":
		return null
	var component := AssemblyComponentDefinitionScript.new(
		ROOT_COMPONENT_ID,
		component_type,
		Vector2i.ZERO,
		0,
		occupied_cells,
		capabilities,
		interfaces,
		0,
		vehicle_definition.total_weight
	)
	return AssemblyDefinitionScript.new(
		vehicle_definition.assembly_id,
		PRESET_REVISION,
		[component]
	)


func _component_type_for(vehicle_definition: VehicleDefinitionScript) -> StringName:
	match vehicle_definition.vehicle_kind:
		VehicleDefinitionScript.VehicleKind.ARM:
			return &"scene01_arm_vehicle_preset"
		VehicleDefinitionScript.VehicleKind.TRANSPORT:
			return &"scene01_transport_vehicle_preset"
	return &""

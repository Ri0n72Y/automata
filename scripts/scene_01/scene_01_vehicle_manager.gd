class_name Scene01VehicleManager
extends Node3D

const VehicleDefinitionScript := preload("res://scripts/vehicles/vehicle_definition.gd")
const VehicleRuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const VehicleActorScript := preload("res://scripts/vehicles/vehicle_actor.gd")

const ARM_VEHICLE_ID := &"arm_vehicle"
const TRANSPORT_VEHICLE_ID := &"transport_vehicle"
const REQUIRED_VEHICLE_COUNT := 2

@export var arm_start_cell: Vector2i = Vector2i(2, 2)
@export var transport_start_cell: Vector2i = Vector2i(7, 4)

var controller: Node
var _vehicles: Array[Node3D] = []


func configure(p_controller: Node, p_cell_size: float) -> bool:
	if not _vehicles.is_empty():
		return _vehicles.size() == REQUIRED_VEHICLE_COUNT
	return _configure_static_scene_children(p_controller, p_cell_size)


func reset_vehicles() -> void:
	for vehicle_node in _vehicles:
		var vehicle := vehicle_node as VehicleActorScript
		if vehicle != null:
			vehicle.reset_actor()


func sync_vehicles_from_state() -> void:
	for vehicle_node in _vehicles:
		var vehicle := vehicle_node as VehicleActorScript
		if vehicle != null:
			vehicle.sync_from_state()


func get_vehicle_count() -> int:
	return _vehicles.size()


func get_vehicle_by_id(vehicle_id: StringName) -> VehicleActorScript:
	for vehicle_node in _vehicles:
		var vehicle := vehicle_node as VehicleActorScript
		if vehicle != null and vehicle.get_vehicle_id() == vehicle_id:
			return vehicle
	return null


func get_vehicles() -> Array[Node3D]:
	return _vehicles.duplicate()


func _configure_static_scene_children(p_controller: Node, p_cell_size: float) -> bool:
	if p_controller == null:
		return false
	var arm_actor := get_node_or_null("ArmVehicle") as VehicleActorScript
	var transport_actor := get_node_or_null("TransportVehicle") as VehicleActorScript
	if arm_actor == null or transport_actor == null:
		return false

	var arm_definition: VehicleDefinitionScript = arm_actor.definition
	var transport_definition: VehicleDefinitionScript = transport_actor.definition
	if not _is_static_definition_valid(arm_definition, ARM_VEHICLE_ID):
		return false
	if not _is_static_definition_valid(transport_definition, TRANSPORT_VEHICLE_ID):
		return false
	if not _is_start_footprint_valid(p_controller, arm_definition, arm_start_cell):
		return false
	if not _is_start_footprint_valid(p_controller, transport_definition, transport_start_cell):
		return false
	if not _configure_actor(
		arm_actor,
		p_controller,
		arm_definition,
		arm_start_cell,
		VehicleRuntimeStateScript.Facing.EAST,
		p_cell_size
	):
		return false
	if not _configure_actor(
		transport_actor,
		p_controller,
		transport_definition,
		transport_start_cell,
		VehicleRuntimeStateScript.Facing.WEST,
		p_cell_size
	):
		return false

	_vehicles.assign([arm_actor, transport_actor])
	controller = p_controller
	return true


func _configure_actor(
	actor: VehicleActorScript,
	p_controller: Node,
	definition: VehicleDefinitionScript,
	anchor_cell: Vector2i,
	facing: int,
	p_cell_size: float
) -> bool:
	var runtime_state := VehicleRuntimeStateScript.new()
	if not runtime_state.configure(definition, anchor_cell, facing):
		return false
	return actor.configure(definition, runtime_state, p_controller, p_cell_size)


func _is_start_footprint_valid(
	p_controller: Node,
	definition: VehicleDefinitionScript,
	anchor_cell: Vector2i
) -> bool:
	if bool(p_controller.call("is_grid_footprint_walkable", anchor_cell, definition.footprint)):
		return true
	push_error(
		"Vehicle %s has an invalid start footprint at %s."
		% [String(definition.assembly_id), str(anchor_cell)]
	)
	return false



func _is_static_definition_valid(
	definition: VehicleDefinitionScript,
	expected_id: StringName
) -> bool:
	if definition == null or not definition.is_configured():
		push_error("Static vehicle scene requires a configured VehicleDefinition resource.")
		return false
	if definition.assembly_id != expected_id:
		push_error(
			"Static vehicle definition id %s does not match expected id %s."
			% [String(definition.assembly_id), String(expected_id)]
		)
		return false
	return true

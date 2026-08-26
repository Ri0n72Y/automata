class_name Scene01VehicleManager
extends Node3D

const VehicleDefinitionScript := preload("res://scripts/vehicles/vehicle_definition.gd")
const VehicleRuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const VehicleActorScript := preload("res://scripts/vehicles/vehicle_actor.gd")
const ArmVehicleScene := preload("res://scenes/scene_01/vehicles/arm_vehicle_placeholder.tscn")
const TransportVehicleScene := preload("res://scenes/scene_01/vehicles/transport_vehicle_placeholder.tscn")

const ARM_VEHICLE_ID := &"arm_vehicle"
const TRANSPORT_VEHICLE_ID := &"transport_vehicle"
const REQUIRED_VEHICLE_COUNT := 2

@export var arm_start_cell: Vector2i = Vector2i(2, 2)
@export var transport_start_cell: Vector2i = Vector2i(7, 4)

var controller: Node
var _vehicles: Array[Node3D] = []


func configure(p_controller: Node, p_cell_size: float) -> bool:
	if _vehicles.is_empty() and _has_any_static_scene_child():
		if not _configure_static_scene_children(p_controller, p_cell_size):
			push_error("Scene 01 static vehicle presets are incomplete or invalid.")
			return false
		return true
	return rebuild_vehicles(p_controller, p_cell_size)


func rebuild_vehicles(p_controller: Node, p_cell_size: float) -> bool:
	var vehicle_batch := _build_vehicle_batch(p_controller, p_cell_size)
	if vehicle_batch.is_empty():
		return false
	if not _is_complete_vehicle_batch(vehicle_batch):
		_free_vehicle_batch(vehicle_batch)
		push_error("Scene 01 vehicle rebuild produced an incomplete preset batch.")
		return false
	_replace_vehicle_batch(vehicle_batch)
	controller = p_controller
	return true


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


func _build_vehicle_batch(
	p_controller: Node,
	p_cell_size: float
) -> Array[Node3D]:
	var vehicle_batch: Array[Node3D] = []
	if p_controller == null:
		push_error("Scene 01 vehicle manager requires a controller.")
		return vehicle_batch

	var arm_definition: VehicleDefinitionScript = _create_arm_definition()
	var transport_definition: VehicleDefinitionScript = _create_transport_definition()
	if arm_definition == null or transport_definition == null:
		return vehicle_batch
	if not _is_start_footprint_valid(p_controller, arm_definition, arm_start_cell):
		return vehicle_batch
	if not _is_start_footprint_valid(
		p_controller,
		transport_definition,
		transport_start_cell
	):
		return vehicle_batch

	var arm_actor: VehicleActorScript = _build_vehicle(
		p_controller,
		arm_definition,
		arm_start_cell,
		VehicleRuntimeStateScript.Facing.EAST,
		p_cell_size
	)
	if arm_actor == null:
		return vehicle_batch
	vehicle_batch.append(arm_actor)

	var transport_actor: VehicleActorScript = _build_vehicle(
		p_controller,
		transport_definition,
		transport_start_cell,
		VehicleRuntimeStateScript.Facing.WEST,
		p_cell_size
	)
	if transport_actor == null:
		_free_vehicle_batch(vehicle_batch)
		return vehicle_batch
	vehicle_batch.append(transport_actor)
	return vehicle_batch


func _has_any_static_scene_child() -> bool:
	return get_node_or_null("ArmVehicle") != null or get_node_or_null("TransportVehicle") != null


func _configure_static_scene_children(p_controller: Node, p_cell_size: float) -> bool:
	if p_controller == null:
		return false
	var arm_actor := get_node_or_null("ArmVehicle") as VehicleActorScript
	var transport_actor := get_node_or_null("TransportVehicle") as VehicleActorScript
	if arm_actor == null or transport_actor == null:
		return false

	var arm_definition: VehicleDefinitionScript = _create_arm_definition()
	var transport_definition: VehicleDefinitionScript = _create_transport_definition()
	if arm_definition == null or transport_definition == null:
		return false
	if not _is_start_footprint_valid(p_controller, arm_definition, arm_start_cell):
		return false
	if not _is_start_footprint_valid(
		p_controller,
		transport_definition,
		transport_start_cell
	):
		return false

	if not _configure_existing_actor(
		arm_actor,
		p_controller,
		arm_definition,
		arm_start_cell,
		VehicleRuntimeStateScript.Facing.EAST,
		p_cell_size
	):
		return false
	if not _configure_existing_actor(
		transport_actor,
		p_controller,
		transport_definition,
		transport_start_cell,
		VehicleRuntimeStateScript.Facing.WEST,
		p_cell_size
	):
		return false

	_vehicles.clear()
	_vehicles.append(arm_actor)
	_vehicles.append(transport_actor)
	controller = p_controller
	return true


func _configure_existing_actor(
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


func _is_complete_vehicle_batch(vehicle_batch: Array[Node3D]) -> bool:
	if vehicle_batch.size() != REQUIRED_VEHICLE_COUNT:
		return false
	var ids: Dictionary = {}
	for vehicle_node in vehicle_batch:
		var vehicle := vehicle_node as VehicleActorScript
		if vehicle == null or not is_instance_valid(vehicle) or vehicle.get_parent() != null:
			return false
		var vehicle_id := vehicle.get_vehicle_id()
		if vehicle_id != ARM_VEHICLE_ID and vehicle_id != TRANSPORT_VEHICLE_ID:
			return false
		if ids.has(vehicle_id):
			return false
		ids[vehicle_id] = true
	return ids.has(ARM_VEHICLE_ID) and ids.has(TRANSPORT_VEHICLE_ID)


func _is_start_footprint_valid(
	p_controller: Node,
	definition: VehicleDefinitionScript,
	anchor_cell: Vector2i
) -> bool:
	if bool(p_controller.call(
		"is_grid_footprint_walkable",
		anchor_cell,
		definition.footprint
	)):
		return true
	push_error(
		"Vehicle %s has an invalid start footprint at %s."
		% [String(definition.assembly_id), str(anchor_cell)]
	)
	return false


func _build_vehicle(
	p_controller: Node,
	definition: VehicleDefinitionScript,
	anchor_cell: Vector2i,
	facing: int,
	p_cell_size: float
) -> VehicleActorScript:
	var runtime_state := VehicleRuntimeStateScript.new()
	if not runtime_state.configure(definition, anchor_cell, facing):
		return null

	var actor_scene: PackedScene
	match definition.assembly_id:
		ARM_VEHICLE_ID:
			actor_scene = ArmVehicleScene
		TRANSPORT_VEHICLE_ID:
			actor_scene = TransportVehicleScene
		_:
			return null
	var actor := actor_scene.instantiate() as VehicleActorScript
	if actor == null:
		return null
	if not actor.configure(definition, runtime_state, p_controller, p_cell_size):
		actor.free()
		return null
	return actor


func _replace_vehicle_batch(pending_vehicles: Array[Node3D]) -> void:
	_clear_vehicles()
	for vehicle_node in pending_vehicles:
		add_child(vehicle_node)
		var vehicle := vehicle_node as VehicleActorScript
		if vehicle != null:
			vehicle.sync_from_state()
	_vehicles = pending_vehicles


func _free_vehicle_batch(vehicle_batch: Array[Node3D]) -> void:
	for vehicle_node in vehicle_batch:
		if vehicle_node != null and is_instance_valid(vehicle_node):
			vehicle_node.free()
	vehicle_batch.clear()


func _clear_vehicles() -> void:
	for vehicle_node in _vehicles:
		if vehicle_node != null and is_instance_valid(vehicle_node):
			if vehicle_node.get_parent() == self:
				remove_child(vehicle_node)
			vehicle_node.queue_free()
	_vehicles.clear()


func _create_arm_definition() -> VehicleDefinitionScript:
	var definition := VehicleDefinitionScript.new()
	if not definition.configure(
		ARM_VEHICLE_ID,
		"Arm Vehicle",
		VehicleDefinitionScript.VehicleKind.ARM,
		Vector2i(2, 2),
		2.0,
		18.0,
		20.0,
		30.0,
		PackedStringArray([
			VehicleDefinitionScript.CAPABILITY_CAN_MOVE,
			VehicleDefinitionScript.CAPABILITY_CAN_GRAB,
			VehicleDefinitionScript.CAPABILITY_CAN_CARRY,
		]),
		0.25,
		0
	):
		return null
	return definition


func _create_transport_definition() -> VehicleDefinitionScript:
	var definition := VehicleDefinitionScript.new()
	if not definition.configure(
		TRANSPORT_VEHICLE_ID,
		"Transport Vehicle",
		VehicleDefinitionScript.VehicleKind.TRANSPORT,
		Vector2i(2, 2),
		2.4,
		16.0,
		24.0,
		36.0,
		PackedStringArray([
			VehicleDefinitionScript.CAPABILITY_CAN_MOVE,
			VehicleDefinitionScript.CAPABILITY_CAN_CARRY,
			VehicleDefinitionScript.CAPABILITY_HAS_TRAY,
		]),
		1.0,
		8
	):
		return null
	return definition

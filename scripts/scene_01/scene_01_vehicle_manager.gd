class_name Scene01VehicleManager
extends Node3D

const VehicleDefinitionScript := preload("res://scripts/vehicles/vehicle_definition.gd")
const VehicleRuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const VehicleActorScript := preload("res://scripts/vehicles/vehicle_actor.gd")
const BlueprintVehicleScene := preload("res://scenes/scene_01/vehicles/blueprint_vehicle_placeholder.tscn")
const ARM_VEHICLE_MESH := preload("res://assets/scene_01/vehicles/arm_vehicle_mesh.res")
const TRANSPORT_VEHICLE_MESH := preload("res://assets/scene_01/vehicles/transport_vehicle_mesh.res")

const ARM_VEHICLE_ID := &"arm_vehicle"
const TRANSPORT_VEHICLE_ID := &"transport_vehicle"
const REQUIRED_VEHICLE_COUNT := 2

@export var arm_start_cell: Vector2i = Vector2i(2, 2)
@export var transport_start_cell: Vector2i = Vector2i(7, 4)

var controller: Node
var _vehicles: Array[Node3D] = []
var _cell_size: float = 1.0


func configure(p_controller: Node, p_cell_size: float) -> bool:
	controller = p_controller
	_cell_size = maxf(p_cell_size, 0.01)
	if not _vehicles.is_empty():
		return true
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
	return actor.configure(definition, runtime_state, p_controller, p_cell_size, true)


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


# ---------------------------------------------------------------------------
# Blueprint deployment
# ---------------------------------------------------------------------------

## Deploy a designed blueprint cart as an extra participant in the scene.
## Returns the actor on success, null on any validation failure (fail-closed).
func deploy_blueprint(blueprint, anchor_cell: Vector2i, facing: int = 0):
	if blueprint == null or controller == null:
		push_error("Blueprint deployment requires a configured vehicle manager.")
		return null
	if not blueprint.is_configured():
		push_error("Blueprint is not configured: %s" % String(blueprint.get_last_error()))
		return null
	var definition: VehicleDefinitionScript = blueprint.to_vehicle_definition()
	if definition == null:
		push_error("Blueprint cannot be projected into a vehicle definition.")
		return null
	if get_vehicle_by_id(definition.assembly_id) != null:
		push_error("A vehicle with id %s is already deployed." % String(definition.assembly_id))
		return null
	if not _is_start_footprint_valid(controller, definition, anchor_cell):
		return null
	if not is_footprint_free_of_vehicles(definition, anchor_cell):
		push_error("Blueprint deployment cell overlaps another vehicle.")
		return null

	var actor := BlueprintVehicleScene.instantiate() as VehicleActorScript
	if actor == null:
		push_error("Blueprint vehicle scene root must use VehicleActor.")
		return null
	var body := actor.get_node_or_null("VisualRoot/BodyMesh") as MeshInstance3D
	if body == null:
		push_error("Blueprint vehicle scene is missing VisualRoot/BodyMesh.")
		actor.queue_free()
		return null
	body.mesh = _visual_mesh_for(definition)
	if not definition.has_capability(VehicleDefinitionScript.CAPABILITY_HAS_TRAY):
		# Blueprint scenes ship one shared tray rig; strip it for non-tray
		# modules so arm carts do not carry eight hidden cargo nodes.
		var tray_slots := actor.get_node_or_null("VisualRoot/TraySlots")
		if tray_slots != null:
			tray_slots.free()
		var tray_label := actor.get_node_or_null("VisualRoot/TrayCountLabel")
		if tray_label != null:
			tray_label.free()
	add_child(actor)
	actor.use_static_scene_visual = true
	if not _configure_actor(
		actor,
		controller,
		definition,
		anchor_cell,
		facing,
		_cell_size
	):
		actor.queue_free()
		return null
	_vehicles.append(actor)
	return actor


## Read-only deployment validation used by the blueprint placement ghost.
func can_deploy_blueprint(blueprint, anchor_cell: Vector2i) -> bool:
	if blueprint == null or controller == null or not blueprint.is_configured():
		return false
	var definition: VehicleDefinitionScript = blueprint.to_vehicle_definition()
	if definition == null:
		return false
	if get_vehicle_by_id(definition.assembly_id) != null:
		return false
	if not bool(controller.call("is_grid_footprint_walkable", anchor_cell, definition.footprint)):
		return false
	return is_footprint_free_of_vehicles(definition, anchor_cell)


func is_footprint_free_of_vehicles(
	definition: VehicleDefinitionScript,
	anchor_cell: Vector2i
) -> bool:
	if definition == null:
		return false
	var candidate_cells := {}
	for offset_y in range(definition.footprint.y):
		for offset_x in range(definition.footprint.x):
			candidate_cells[anchor_cell + Vector2i(offset_x, offset_y)] = true
	for vehicle_node in _vehicles:
		var vehicle := vehicle_node as VehicleActorScript
		if vehicle == null:
			continue
		for occupied_cell in vehicle.get_occupied_cells():
			if candidate_cells.has(occupied_cell):
				return false
	return true


func get_cell_size() -> float:
	return _cell_size


func _visual_mesh_for(definition: VehicleDefinitionScript) -> Mesh:
	if definition.has_capability(VehicleDefinitionScript.CAPABILITY_CAN_GRAB):
		return ARM_VEHICLE_MESH
	return TRANSPORT_VEHICLE_MESH

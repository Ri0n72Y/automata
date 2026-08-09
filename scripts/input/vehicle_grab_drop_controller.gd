class_name VehicleGrabDropController
extends Node3D

signal grab_drop_completed(vehicle_id: StringName, action: int, status: int)
signal facing_changed(vehicle_id: StringName, facing: int)

const VehicleActorScript := preload("res://scripts/vehicles/vehicle_actor.gd")
const VehicleDefinitionScript := preload("res://scripts/vehicles/vehicle_definition.gd")
const VehicleRuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const GrabDropCommandScript := preload("res://scripts/vehicles/grab_drop_command.gd")
const GrabDropResultScript := preload("res://scripts/vehicles/grab_drop_result.gd")
const ItemSourceInterfaceScript := preload("res://scripts/objects/item_source_interface.gd")
const ItemReceiverInterfaceScript := preload("res://scripts/objects/item_receiver_interface.gd")
const VehicleSelectionControllerScript := preload("res://scripts/input/vehicle_selection_controller.gd")
const Scene01VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const Scene01ObjectManagerScript := preload("res://scripts/scene_01/scene_01_object_manager.gd")

const GRAB_DROP_ACTION := &"vehicle_grab_drop"
const ROTATE_COUNTERCLOCKWISE_ACTION := &"vehicle_rotate_counterclockwise"
const ROTATE_CLOCKWISE_ACTION := &"vehicle_rotate_clockwise"

var vehicle_selection_controller: VehicleSelectionControllerScript
var vehicle_manager: Scene01VehicleManagerScript
var object_manager: Scene01ObjectManagerScript
var _command := GrabDropCommandScript.new()


func _ready() -> void:
	configure(
		get_node_or_null("../VehicleSelectionController") as VehicleSelectionControllerScript,
		get_node_or_null("../../RobotRoot/Scene01VehicleManager") as Scene01VehicleManagerScript,
		get_node_or_null("../../ObjectRoot/Scene01ObjectManager") as Scene01ObjectManagerScript
	)


func configure(
	p_vehicle_selection_controller: VehicleSelectionControllerScript,
	p_vehicle_manager: Scene01VehicleManagerScript,
	p_object_manager: Scene01ObjectManagerScript
) -> void:
	vehicle_selection_controller = p_vehicle_selection_controller
	vehicle_manager = p_vehicle_manager
	object_manager = p_object_manager


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.echo or _has_command_modifier(key_event) or _is_text_input_focused():
			return
	if event.is_action_pressed(GRAB_DROP_ACTION):
		request_selected_grab_drop()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(ROTATE_COUNTERCLOCKWISE_ACTION):
		if rotate_selected_arm(-1):
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(ROTATE_CLOCKWISE_ACTION):
		if rotate_selected_arm(1):
			get_viewport().set_input_as_handled()


func request_selected_grab_drop() -> GrabDropResultScript:
	var vehicle := _get_selected_vehicle()
	if vehicle == null or vehicle.runtime_state == null:
		var missing_vehicle_result := GrabDropResultScript.rejected(
			GrabDropResultScript.Action.NONE,
			GrabDropResultScript.Status.NO_TARGET
		)
		grab_drop_completed.emit(
			&"",
			missing_vehicle_result.action,
			missing_vehicle_result.status
		)
		return missing_vehicle_result
	var target := resolve_target_for_vehicle(vehicle)
	var result := _command.execute(vehicle.runtime_state, target)
	vehicle.sync_from_state()
	grab_drop_completed.emit(vehicle.get_vehicle_id(), result.action, result.status)
	return result


func rotate_selected_arm(direction: int) -> bool:
	var vehicle := _get_selected_vehicle()
	if not _can_rotate(vehicle):
		return false
	var step := clampi(direction, -1, 1)
	if step == 0:
		return false
	vehicle.runtime_state.facing = posmod(vehicle.runtime_state.facing + step, 4)
	vehicle.sync_from_state()
	facing_changed.emit(vehicle.get_vehicle_id(), vehicle.runtime_state.facing)
	return true


func resolve_target_for_vehicle(vehicle: VehicleActorScript) -> Variant:
	if vehicle == null or vehicle.runtime_state == null or vehicle.definition == null:
		return null
	var front_cells := get_forward_interaction_cells(vehicle)
	if front_cells.is_empty():
		return null
	var candidates: Array[Variant] = []
	for interaction_interface in _collect_item_interaction_interfaces():
		if not _is_action_compatible(vehicle.runtime_state, interaction_interface):
			continue
		var interaction_cells := _get_interaction_cells(interaction_interface)
		if interaction_cells.is_empty() or not _cells_overlap(front_cells, interaction_cells):
			continue
		if not candidates.has(interaction_interface):
			candidates.append(interaction_interface)

	if candidates.size() != 1:
		return null
	return candidates[0]


func get_forward_interaction_cells(vehicle: VehicleActorScript) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if vehicle == null or vehicle.runtime_state == null or vehicle.definition == null:
		return result
	var anchor: Vector2i = vehicle.runtime_state.anchor_cell
	var footprint: Vector2i = vehicle.definition.footprint
	match vehicle.runtime_state.facing:
		VehicleRuntimeStateScript.Facing.NORTH:
			for offset_x in range(footprint.x):
				result.append(anchor + Vector2i(offset_x, -1))
		VehicleRuntimeStateScript.Facing.EAST:
			for offset_y in range(footprint.y):
				result.append(anchor + Vector2i(footprint.x, offset_y))
		VehicleRuntimeStateScript.Facing.SOUTH:
			for offset_x in range(footprint.x):
				result.append(anchor + Vector2i(offset_x, footprint.y))
		VehicleRuntimeStateScript.Facing.WEST:
			for offset_y in range(footprint.y):
				result.append(anchor + Vector2i(-1, offset_y))
	return result


func _collect_item_interaction_interfaces() -> Array[Variant]:
	var interfaces: Array[Variant] = []
	if object_manager != null:
		for interaction_interface in object_manager.get_item_interaction_interfaces():
			if interaction_interface != null and not interfaces.has(interaction_interface):
				interfaces.append(interaction_interface)
	if vehicle_manager != null:
		for vehicle_node in vehicle_manager.get_vehicles():
			var actor := vehicle_node as VehicleActorScript
			if actor == null or actor.runtime_state == null:
				continue
			for interaction_interface in actor.runtime_state.get_item_interaction_interfaces(
				actor.get_occupied_cells()
			):
				if interaction_interface != null and not interfaces.has(interaction_interface):
					interfaces.append(interaction_interface)
	return interfaces


func _is_action_compatible(runtime: VehicleRuntimeStateScript, target: Variant) -> bool:
	if runtime == null:
		return false
	if runtime.arm_has_item:
		var receiver := target as ItemReceiverInterfaceScript
		return (
			receiver != null
			and runtime.carried_item != null
			and receiver.accepts_item_type(runtime.carried_item.get_item_type())
		)
	var source := target as ItemSourceInterfaceScript
	if source != null:
		return true
	var receiver := target as ItemReceiverInterfaceScript
	return receiver != null and receiver.can_take_item()


func _get_interaction_cells(target: Variant) -> Array[Vector2i]:
	var source := target as ItemSourceInterfaceScript
	if source != null:
		return source.get_interaction_cells()
	var receiver := target as ItemReceiverInterfaceScript
	if receiver != null:
		return receiver.get_interaction_cells()
	var empty_cells: Array[Vector2i] = []
	return empty_cells


func _get_selected_vehicle() -> VehicleActorScript:
	if vehicle_selection_controller == null:
		return null
	return vehicle_selection_controller.get_selected_vehicle()


func _can_rotate(vehicle: VehicleActorScript) -> bool:
	if vehicle == null or vehicle.definition == null or vehicle.runtime_state == null:
		return false
	if not vehicle.definition.has_capability(VehicleDefinitionScript.CAPABILITY_CAN_GRAB):
		return false
	return (
		vehicle.runtime_state.motion_state != VehicleRuntimeStateScript.MotionState.PLANNING
		and vehicle.runtime_state.motion_state != VehicleRuntimeStateScript.MotionState.MOVING
	)


func _cells_overlap(a: Array[Vector2i], b: Array[Vector2i]) -> bool:
	for cell in a:
		if b.has(cell):
			return true
	return false


func _has_command_modifier(event: InputEventKey) -> bool:
	return event.shift_pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed


func _is_text_input_focused() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit

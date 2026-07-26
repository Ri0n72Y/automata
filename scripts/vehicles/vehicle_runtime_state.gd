class_name VehicleRuntimeState
extends RefCounted

const VehicleDefinitionScript := preload("res://scripts/vehicles/vehicle_definition.gd")

enum Facing {
	NORTH,
	EAST,
	SOUTH,
	WEST,
}

enum MotionState {
	WAITING,
	PLANNING,
	MOVING,
	BLOCKED,
}

var _definition: VehicleDefinitionScript
var _arm_has_item: bool = false
var _tray_count: int = 0

var definition: VehicleDefinitionScript:
	get:
		return _definition

var arm_has_item: bool:
	get:
		return _arm_has_item

var tray_count: int:
	get:
		return _tray_count

var anchor_cell: Vector2i = Vector2i.ZERO
var facing: int = Facing.NORTH
var motion_state: int = MotionState.WAITING
var command_queue: Array[Dictionary] = []

var _initial_anchor_cell: Vector2i = Vector2i.ZERO
var _initial_facing: int = Facing.NORTH


func configure(
	p_definition: VehicleDefinitionScript,
	p_anchor_cell: Vector2i,
	p_facing: int = Facing.NORTH
) -> bool:
	if p_definition == null or not p_definition.is_configured():
		push_error("Vehicle runtime state requires a configured definition.")
		return false
	if p_facing < Facing.NORTH or p_facing > Facing.WEST:
		push_error("Vehicle facing is invalid.")
		return false

	_definition = p_definition
	_initial_anchor_cell = p_anchor_cell
	_initial_facing = p_facing
	reset()
	return true


func reset() -> void:
	anchor_cell = _initial_anchor_cell
	facing = _initial_facing
	motion_state = MotionState.WAITING
	command_queue.clear()
	_arm_has_item = false
	_tray_count = 0


func set_arm_has_item(value: bool) -> bool:
	if _definition == null or not _definition.has_capability(
		VehicleDefinitionScript.CAPABILITY_CAN_GRAB
	):
		return false
	_arm_has_item = value
	return true


func set_tray_count(value: int) -> bool:
	if _definition == null or not _definition.has_capability(
		VehicleDefinitionScript.CAPABILITY_HAS_TRAY
	):
		return false
	if value < 0 or value > _definition.tray_capacity:
		return false
	_tray_count = value
	return true


func enqueue_command(command: Dictionary) -> void:
	command_queue.append(command.duplicate(true))


func get_effective_speed() -> float:
	if _definition == null:
		return 0.0
	if _arm_has_item:
		return _definition.base_speed * _definition.carrying_speed_multiplier
	return _definition.base_speed

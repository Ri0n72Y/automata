class_name VehicleRuntimeState
extends RefCounted

const VehicleDefinitionScript := preload("res://scripts/vehicles/vehicle_definition.gd")
const MoveCommandScript := preload("res://scripts/vehicles/move_command.gd")
const TransportTrayStateScript := preload("res://scripts/vehicles/transport_tray_state.gd")
const StandardBlockScript := preload("res://scripts/objects/standard_block.gd")

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
var _carried_item: StandardBlockScript
var _tray_state: TransportTrayStateScript
var _active_move_command: MoveCommandScript

var definition: VehicleDefinitionScript:
	get:
		return _definition

var carried_item: StandardBlockScript:
	get:
		return _carried_item

var arm_has_item: bool:
	get:
		return _carried_item != null

var tray_state: TransportTrayStateScript:
	get:
		return _tray_state

var tray_count: int:
	get:
		return _tray_state.get_current_count() if _tray_state != null else 0

var active_move_command: MoveCommandScript:
	get:
		return _active_move_command

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

	var new_tray_state: TransportTrayStateScript
	if p_definition.has_capability(VehicleDefinitionScript.CAPABILITY_HAS_TRAY):
		new_tray_state = TransportTrayStateScript.new()
		if not new_tray_state.configure(p_definition.tray_capacity):
			push_error("Vehicle runtime state could not configure transport tray state.")
			return false

	_definition = p_definition
	_tray_state = new_tray_state
	_initial_anchor_cell = p_anchor_cell
	_initial_facing = p_facing
	reset()
	return true


func reset() -> void:
	anchor_cell = _initial_anchor_cell
	facing = _initial_facing
	motion_state = MotionState.WAITING
	_active_move_command = null
	command_queue.clear()
	_clear_carried_item()
	if _tray_state != null:
		_tray_state.reset()


func begin_move_planning() -> bool:
	if _active_move_command != null:
		return false
	if motion_state == MotionState.PLANNING or motion_state == MotionState.MOVING:
		return false
	motion_state = MotionState.PLANNING
	return true


func fail_move_planning() -> void:
	if _active_move_command == null and motion_state == MotionState.PLANNING:
		motion_state = MotionState.BLOCKED


func assign_move_command(command: MoveCommandScript) -> bool:
	if command == null or command.state != MoveCommandScript.State.MOVING:
		return false
	if _active_move_command != null:
		return false
	_active_move_command = command
	motion_state = MotionState.MOVING
	return true


func complete_move_command() -> void:
	if _active_move_command != null:
		_active_move_command.state = MoveCommandScript.State.WAITING
	_active_move_command = null
	motion_state = MotionState.WAITING


func block_move_command() -> void:
	if _active_move_command != null:
		_active_move_command.block()
	_active_move_command = null
	motion_state = MotionState.BLOCKED


func clear_move_command() -> void:
	_active_move_command = null
	motion_state = MotionState.WAITING


func claim_carried_item(block: StandardBlockScript) -> bool:
	if _definition == null or not _definition.has_capability(
		VehicleDefinitionScript.CAPABILITY_CAN_GRAB
	):
		return false
	if block == null or not block.is_valid() or _carried_item != null:
		return false
	if not block.try_claim(self):
		return false
	_carried_item = block
	return true


func release_carried_item() -> StandardBlockScript:
	if _carried_item == null or not _carried_item.is_claimed_by(self):
		return null
	var block := _carried_item
	if not block.release_claim(self):
		return null
	_carried_item = null
	return block


func set_arm_has_item(value: bool) -> bool:
	if _definition == null or not _definition.has_capability(
		VehicleDefinitionScript.CAPABILITY_CAN_GRAB
	):
		return false
	if value == arm_has_item:
		return true
	if value:
		return claim_carried_item(StandardBlockScript.create())
	return release_carried_item() != null


func set_tray_count(value: int) -> bool:
	if _tray_state == null:
		return false
	return _tray_state.replace_count_for_compatibility(value)


func enqueue_command(command: Dictionary) -> void:
	command_queue.append(command.duplicate(true))


func get_effective_speed() -> float:
	if _definition == null:
		return 0.0
	if arm_has_item:
		return _definition.base_speed * _definition.carrying_speed_multiplier
	return _definition.base_speed


func _clear_carried_item() -> void:
	if _carried_item != null and _carried_item.is_claimed_by(self):
		_carried_item.release_claim(self)
	_carried_item = null

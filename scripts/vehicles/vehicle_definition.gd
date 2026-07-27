class_name VehicleDefinition
extends RefCounted

enum VehicleKind {
	ARM,
	TRANSPORT,
}

const CAPABILITY_CAN_MOVE := "can_move"
const CAPABILITY_CAN_GRAB := "can_grab"
const CAPABILITY_CAN_CARRY := "can_carry"
const CAPABILITY_HAS_TRAY := "has_tray"

var _assembly_id: StringName = &""
var _display_name: String = ""
var _vehicle_kind: int = VehicleKind.ARM
var _footprint: Vector2i = Vector2i(1, 1)
var _base_speed: float = 1.0
var _carrying_speed_multiplier: float = 1.0
var _total_weight: float = 0.0
var _recommended_payload: float = 0.0
var _max_payload: float = 0.0
var _capability_tags: PackedStringArray = PackedStringArray()
var _tray_capacity: int = 0
var _is_configured: bool = false

var assembly_id: StringName:
	get:
		return _assembly_id

var display_name: String:
	get:
		return _display_name

var vehicle_kind: int:
	get:
		return _vehicle_kind

var footprint: Vector2i:
	get:
		return _footprint

var base_speed: float:
	get:
		return _base_speed

var carrying_speed_multiplier: float:
	get:
		return _carrying_speed_multiplier

var total_weight: float:
	get:
		return _total_weight

var recommended_payload: float:
	get:
		return _recommended_payload

var max_payload: float:
	get:
		return _max_payload

var capability_tags: PackedStringArray:
	get:
		return _capability_tags.duplicate()

var tray_capacity: int:
	get:
		return _tray_capacity


func configure(
	p_assembly_id: StringName,
	p_display_name: String,
	p_vehicle_kind: int,
	p_footprint: Vector2i,
	p_base_speed: float,
	p_total_weight: float,
	p_recommended_payload: float,
	p_max_payload: float,
	p_capability_tags: PackedStringArray,
	p_carrying_speed_multiplier: float = 1.0,
	p_tray_capacity: int = 0
) -> bool:
	if _is_configured:
		push_error("Vehicle definition is immutable after configuration.")
		return false
	if p_assembly_id == &"":
		push_error("Vehicle assembly id must not be empty.")
		return false
	if p_vehicle_kind < VehicleKind.ARM or p_vehicle_kind > VehicleKind.TRANSPORT:
		push_error("Vehicle kind is invalid.")
		return false
	if p_footprint.x <= 0 or p_footprint.y <= 0:
		push_error("Vehicle footprint must be positive.")
		return false
	if p_base_speed <= 0.0:
		push_error("Vehicle base speed must be greater than zero.")
		return false
	if p_total_weight < 0.0:
		push_error("Vehicle total weight must not be negative.")
		return false
	if p_recommended_payload < 0.0 or p_max_payload < p_recommended_payload:
		push_error("Vehicle payload limits are invalid.")
		return false
	if p_carrying_speed_multiplier <= 0.0 or p_carrying_speed_multiplier > 1.0:
		push_error("Vehicle carrying speed multiplier must be in (0, 1].")
		return false
	if p_tray_capacity < 0:
		push_error("Vehicle tray capacity must not be negative.")
		return false

	_assembly_id = p_assembly_id
	_display_name = p_display_name
	_vehicle_kind = p_vehicle_kind
	_footprint = p_footprint
	_base_speed = p_base_speed
	_total_weight = p_total_weight
	_recommended_payload = p_recommended_payload
	_max_payload = p_max_payload
	_capability_tags = p_capability_tags.duplicate()
	_carrying_speed_multiplier = p_carrying_speed_multiplier
	_tray_capacity = p_tray_capacity
	_is_configured = true
	return true


func is_configured() -> bool:
	return _is_configured


func has_capability(capability: String) -> bool:
	return _capability_tags.has(capability)


func can_move() -> bool:
	return has_capability(CAPABILITY_CAN_MOVE)

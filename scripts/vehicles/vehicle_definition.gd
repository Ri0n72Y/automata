class_name VehicleDefinition
extends Resource

enum VehicleKind {
	ARM,
	TRANSPORT,
}

const CAPABILITY_CAN_MOVE := "can_move"
const CAPABILITY_CAN_ROTATE := "can_rotate"
const CAPABILITY_CAN_GRAB := "can_grab"
const CAPABILITY_CAN_CARRY := "can_carry"
const CAPABILITY_HAS_TRAY := "has_tray"

@export_group("Identity")
@export var assembly_id: StringName = &""
@export var display_name: String = ""
@export_enum("Arm", "Transport") var vehicle_kind: int = VehicleKind.ARM

@export_group("Geometry")
@export var footprint: Vector2i = Vector2i.ONE

@export_group("Movement")
@export_range(0.01, 100.0, 0.01) var base_speed: float = 1.0
@export_range(0.01, 1.0, 0.01) var carrying_speed_multiplier: float = 1.0

@export_group("Mass / Payload")
@export_range(0.0, 100000.0, 0.1) var total_weight: float = 0.0
@export_range(0.0, 100000.0, 0.1) var recommended_payload: float = 0.0
@export_range(0.0, 100000.0, 0.1) var max_payload: float = 0.0

@export_group("Capabilities")
@export var capability_tags: PackedStringArray = PackedStringArray()
@export_range(0, 128, 1) var tray_capacity: int = 0


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
	if is_configured():
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

	assembly_id = p_assembly_id
	display_name = p_display_name
	vehicle_kind = p_vehicle_kind
	footprint = p_footprint
	base_speed = p_base_speed
	total_weight = p_total_weight
	recommended_payload = p_recommended_payload
	max_payload = p_max_payload
	capability_tags = p_capability_tags.duplicate()
	carrying_speed_multiplier = p_carrying_speed_multiplier
	tray_capacity = p_tray_capacity
	return true


func is_configured() -> bool:
	return (
		assembly_id != &""
		and vehicle_kind >= VehicleKind.ARM
		and vehicle_kind <= VehicleKind.TRANSPORT
		and footprint.x > 0
		and footprint.y > 0
		and base_speed > 0.0
		and total_weight >= 0.0
		and recommended_payload >= 0.0
		and max_payload >= recommended_payload
		and carrying_speed_multiplier > 0.0
		and carrying_speed_multiplier <= 1.0
		and tray_capacity >= 0
	)


func has_capability(capability: String) -> bool:
	return capability_tags.has(capability)


func can_move() -> bool:
	return has_capability(CAPABILITY_CAN_MOVE)

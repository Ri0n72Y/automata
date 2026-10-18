class_name VehiclePartDefinition
extends Resource

## 组装部件定义：底盘 / 轮组 / 工作件共用一种数据形状。
## 能力标签与 VehicleDefinition 的 capability_tags 使用同一套常量，
## 蓝图组合后直接投影为 VehicleDefinition / AssemblyCapabilities / Program 语句需求。

enum Slot {
	CHASSIS,
	WHEEL,
	WORK_MODULE,
}

@export_group("Identity")
@export var part_id: StringName = &""
@export var slot: int = Slot.CHASSIS
@export var display_name: String = ""
@export_multiline var description: String = ""

@export_group("Capabilities")
@export var capability_tags: PackedStringArray = PackedStringArray()
@export var tray_capacity: int = 0
@export var can_rotate: bool = false

@export_group("Geometry / Movement")
@export var footprint: Vector2i = Vector2i.ONE
@export var base_speed: float = 1.0
@export var speed_multiplier: float = 1.0
@export var carrying_speed_multiplier: float = 1.0

@export_group("Mass / Payload")
@export var weight: float = 0.0
@export var recommended_payload: float = 0.0
@export var max_payload: float = 0.0
## 蓝图预算 / 自复制闸门用的抽象零件成本（不是货币）。
@export var cost: int = 0

@export_group("Design Notes")
## 该部件适用的关卡机制（文档/UI 提示用，不参与能力计算）。
@export var suitable_levels: PackedStringArray = PackedStringArray()


func is_configured() -> bool:
	return (
		part_id != &""
		and slot >= Slot.CHASSIS
		and slot <= Slot.WORK_MODULE
		and display_name != ""
		and footprint.x > 0
		and footprint.y > 0
		and base_speed >= 0.0
		and speed_multiplier > 0.0
		and carrying_speed_multiplier > 0.0
		and carrying_speed_multiplier <= 1.0
		and weight >= 0.0
		and tray_capacity >= 0
	)


func has_capability(capability: String) -> bool:
	return capability_tags.has(capability)


static func make(
	p_part_id: StringName,
	p_slot: int,
	p_display_name: String,
	p_description: String,
	p_capability_tags: PackedStringArray,
	p_footprint: Vector2i,
	p_base_speed: float,
	p_carrying_speed_multiplier: float,
	p_weight: float,
	p_recommended_payload: float,
	p_max_payload: float,
	p_tray_capacity: int,
	p_can_rotate: bool,
	p_suitable_levels: PackedStringArray
) -> VehiclePartDefinition:
	var part := VehiclePartDefinition.new()
	part.part_id = p_part_id
	part.slot = p_slot
	part.display_name = p_display_name
	part.description = p_description
	part.capability_tags = p_capability_tags
	part.footprint = p_footprint
	part.base_speed = p_base_speed
	part.speed_multiplier = 1.0
	part.carrying_speed_multiplier = p_carrying_speed_multiplier
	part.weight = p_weight
	part.recommended_payload = p_recommended_payload
	part.max_payload = p_max_payload
	part.tray_capacity = p_tray_capacity
	part.can_rotate = p_can_rotate
	part.suitable_levels = p_suitable_levels
	return part

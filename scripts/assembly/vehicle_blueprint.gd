class_name VehicleBlueprint
extends Resource

## 小车蓝图：底盘 + 轮组 + 工作件的组合，是玩家在设计界面里唯一编辑的真值。
## 蓝图不持有运行期状态：部署时投影为 VehicleDefinition，交给现有
## VehicleActor / AssemblyCompileGate / Program 能力校验链路。
## 设计文档：docs/design/vehicle_assembly_v1.md

const VehiclePartDefinitionScript := preload("res://scripts/assembly/vehicle_part_definition.gd")
const VehiclePartCatalogScript := preload("res://scripts/assembly/vehicle_part_catalog.gd")
const VehicleDefinitionScript := preload("res://scripts/vehicles/vehicle_definition.gd")

const BLUEPRINT_ID_PATTERN := "^[a-z][a-z0-9_]{1,31}$"
const PRESET_REVISION := 1
## 单个货物方块的抽象重量（kg）：底盘 max_payload 通过它限制托盘格数。
const ITEM_WEIGHT := 2.0

@export_group("Identity")
@export var blueprint_id: StringName = &""
@export var display_name: String = ""

@export_group("Parts")
@export var chassis_id: StringName = &""
@export var wheel_id: StringName = &""
@export var work_module_id: StringName = &""

var _last_error: String = ""


func configure(
	p_blueprint_id: StringName,
	p_display_name: String,
	p_chassis_id: StringName,
	p_wheel_id: StringName,
	p_work_module_id: StringName
) -> bool:
	_last_error = ""
	if not _is_valid_id(p_blueprint_id):
		_last_error = "blueprint_id 必须是 2-32 位小写字母/数字/下划线，且以字母开头。"
		return false
	var chassis := VehiclePartCatalogScript.find_part(
		VehiclePartDefinitionScript.Slot.CHASSIS, p_chassis_id
	)
	if chassis == null:
		_last_error = "未知底盘：%s" % String(p_chassis_id)
		return false
	var wheel := VehiclePartCatalogScript.find_part(
		VehiclePartDefinitionScript.Slot.WHEEL, p_wheel_id
	)
	if wheel == null:
		_last_error = "未知轮组：%s" % String(p_wheel_id)
		return false
	var work_module := VehiclePartCatalogScript.find_part(
		VehiclePartDefinitionScript.Slot.WORK_MODULE, p_work_module_id
	)
	if work_module == null:
		_last_error = "未知工作件：%s" % String(p_work_module_id)
		return false

	blueprint_id = p_blueprint_id
	chassis_id = p_chassis_id
	wheel_id = p_wheel_id
	work_module_id = p_work_module_id
	display_name = p_display_name if p_display_name != "" else _default_display_name(
		chassis, work_module
	)
	return true


func is_configured() -> bool:
	return (
		_is_valid_id(blueprint_id)
		and display_name != ""
		and get_chassis() != null
		and get_wheel() != null
		and get_work_module() != null
	)


func get_last_error() -> String:
	return _last_error


func get_chassis() -> VehiclePartDefinition:
	return VehiclePartCatalogScript.find_part(
		VehiclePartDefinitionScript.Slot.CHASSIS, chassis_id
	)


func get_wheel() -> VehiclePartDefinition:
	return VehiclePartCatalogScript.find_part(
		VehiclePartDefinitionScript.Slot.WHEEL, wheel_id
	)


func get_work_module() -> VehiclePartDefinition:
	return VehiclePartCatalogScript.find_part(
		VehiclePartDefinitionScript.Slot.WORK_MODULE, work_module_id
	)


func get_parts() -> Array:
	var parts: Array = []
	for part in [get_chassis(), get_wheel(), get_work_module()]:
		if part != null:
			parts.append(part)
	return parts


func get_footprint() -> Vector2i:
	var chassis := get_chassis()
	return chassis.footprint if chassis != null else Vector2i.ONE


func get_total_weight() -> float:
	var total := 0.0
	for part in get_parts():
		total += part.weight
	return total


func get_base_speed() -> float:
	var chassis := get_chassis()
	var wheel := get_wheel()
	if chassis == null:
		return 0.0
	var multiplier: float = wheel.speed_multiplier if wheel != null else 1.0
	return maxf(chassis.base_speed * multiplier, 0.1)


func get_carrying_speed_multiplier() -> float:
	var chassis := get_chassis()
	if chassis == null:
		return 1.0
	return clampf(chassis.carrying_speed_multiplier, 0.01, 1.0)


func get_capability_tags() -> PackedStringArray:
	var seen := {}
	var capabilities := PackedStringArray()
	for part in get_parts():
		for capability in part.capability_tags:
			if seen.has(capability):
				continue
			seen[capability] = true
			capabilities.append(capability)
	return capabilities


func get_tray_capacity() -> int:
	var work_module := get_work_module()
	if work_module == null or work_module.tray_capacity <= 0:
		return 0
	var chassis := get_chassis()
	if chassis == null or chassis.max_payload <= 0.0:
		return work_module.tray_capacity
	var payload_capacity := int(floor(chassis.max_payload / ITEM_WEIGHT))
	return mini(work_module.tray_capacity, payload_capacity)


func get_total_cost() -> int:
	var total := 0
	for part in get_parts():
		total += part.cost
	return total


func get_available_actions() -> PackedStringArray:
	return VehiclePartCatalogScript.actions_for_capabilities(get_capability_tags())


func get_summary() -> Dictionary:
	return {
		"blueprint_id": String(blueprint_id),
		"display_name": display_name,
		"chassis": get_chassis().display_name if get_chassis() != null else "",
		"wheel": get_wheel().display_name if get_wheel() != null else "",
		"work_module": get_work_module().display_name if get_work_module() != null else "",
		"capabilities": get_capability_tags(),
		"actions": get_available_actions(),
		"footprint": get_footprint(),
		"base_speed": get_base_speed(),
		"total_weight": get_total_weight(),
		"total_cost": get_total_cost(),
		"tray_capacity": get_tray_capacity(),
	}


func to_vehicle_definition() -> VehicleDefinition:
	if not is_configured():
		return null
	var definition := VehicleDefinitionScript.new()
	var chassis := get_chassis()
	var configured := definition.configure(
		blueprint_id,
		display_name,
		VehicleDefinitionScript.VehicleKind.ASSEMBLED,
		get_footprint(),
		get_base_speed(),
		get_total_weight(),
		chassis.recommended_payload,
		chassis.max_payload,
		get_capability_tags(),
		get_carrying_speed_multiplier(),
		get_tray_capacity()
	)
	return definition if configured else null


func to_dictionary() -> Dictionary:
	return {
		"version": PRESET_REVISION,
		"blueprint_id": String(blueprint_id),
		"display_name": display_name,
		"chassis_id": String(chassis_id),
		"wheel_id": String(wheel_id),
		"work_module_id": String(work_module_id),
	}


static func from_dictionary(data: Dictionary) -> VehicleBlueprint:
	var blueprint := VehicleBlueprint.new()
	var ok := blueprint.configure(
		StringName(str(data.get("blueprint_id", ""))),
		str(data.get("display_name", "")),
		StringName(str(data.get("chassis_id", ""))),
		StringName(str(data.get("wheel_id", ""))),
		StringName(str(data.get("work_module_id", "")))
	)
	return blueprint if ok else null


func _is_valid_id(candidate: StringName) -> bool:
	var pattern := RegEx.new()
	pattern.compile(BLUEPRINT_ID_PATTERN)
	return pattern.search(String(candidate)) != null


func _default_display_name(chassis: VehiclePartDefinition, work_module: VehiclePartDefinition) -> String:
	return "%s + %s" % [chassis.display_name, work_module.display_name]

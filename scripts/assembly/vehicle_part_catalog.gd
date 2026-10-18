class_name VehiclePartCatalog
extends RefCounted

## 组装部件目录（MVP，代码内数据）。
## 设计文档：docs/design/vehicle_assembly_v1.md
## 说明：部件目前以代码构建，保证契约可测试、无外部资源依赖；
## 后续如需编辑器可视化配置，可把这些定义迁移为 .tres 资源，目录 API 不变。

const VehiclePartDefinitionScript := preload("res://scripts/assembly/vehicle_part_definition.gd")
const VehicleDefinitionScript := preload("res://scripts/vehicles/vehicle_definition.gd")

const CAPABILITY_MOVE := VehicleDefinitionScript.CAPABILITY_CAN_MOVE
const CAPABILITY_ROTATE := VehicleDefinitionScript.CAPABILITY_CAN_ROTATE
const CAPABILITY_GRAB := VehicleDefinitionScript.CAPABILITY_CAN_GRAB
const CAPABILITY_CARRY := VehicleDefinitionScript.CAPABILITY_CAN_CARRY
const CAPABILITY_TRAY := VehicleDefinitionScript.CAPABILITY_HAS_TRAY

static var _chassis: Dictionary = {}
static var _wheels: Dictionary = {}
static var _work_modules: Dictionary = {}

## 常用动作名（UI 展示用）。能力标签是机器契约，动作名是玩家可读投影。
const ACTION_BY_CAPABILITY := {
	&"can_move": "MoveTo",
	&"can_rotate": "Rotate",
	&"can_grab": "GrabDrop",
	&"has_tray": "Tray",
	&"can_carry": "Carry",
	&"can_push": "Push",
}


static func chassis_definitions() -> Dictionary:
	_ensure_catalog()
	return _chassis.duplicate()


static func wheel_definitions() -> Dictionary:
	_ensure_catalog()
	return _wheels.duplicate()


static func work_module_definitions() -> Dictionary:
	_ensure_catalog()
	return _work_modules.duplicate()


static func find_part(slot: int, part_id: StringName) -> VehiclePartDefinition:
	_ensure_catalog()
	var table: Dictionary
	match slot:
		VehiclePartDefinitionScript.Slot.CHASSIS:
			table = _chassis
		VehiclePartDefinitionScript.Slot.WHEEL:
			table = _wheels
		VehiclePartDefinitionScript.Slot.WORK_MODULE:
			table = _work_modules
		_:
			return null
	return table.get(part_id)


static func actions_for_capabilities(capabilities: PackedStringArray) -> PackedStringArray:
	var seen := {}
	var actions := PackedStringArray()
	for capability in capabilities:
		var action: String = ACTION_BY_CAPABILITY.get(StringName(capability), "")
		if action == "" or seen.has(action) or action == "Carry":
			continue
		seen[action] = true
		actions.append(action)
	return actions


static func default_blueprints() -> Array:
	_ensure_catalog()
	var result: Array = []
	result.append(_make_blueprint(&"bp_scout_arm", "侦察抓取车", &"differential", &"standard", &"gripper_arm"))
	result.append(_make_blueprint(&"bp_hauler", "运输托盘车", &"differential", &"heavy", &"cargo_tray"))
	result.append(_make_blueprint(&"bp_skid_hauler", "滑移运输车", &"skid_steer", &"heavy", &"cargo_tray"))
	result.append(_make_blueprint(&"bp_omni_arm", "全向抓取车", &"omni", &"fast", &"gripper_arm"))
	return result


static func _make_blueprint(
	id: StringName,
	display_name: String,
	chassis_id: StringName,
	wheel_id: StringName,
	work_module_id: StringName
) -> Resource:
	var BlueprintScript := load("res://scripts/assembly/vehicle_blueprint.gd")
	var blueprint: Resource = BlueprintScript.new()
	blueprint.configure(id, display_name, chassis_id, wheel_id, work_module_id)
	return blueprint


static func _ensure_catalog() -> void:
	if not _chassis.is_empty():
		return
	var Part := VehiclePartDefinitionScript

	# ---------------- 底盘 ----------------
	_chassis[&"differential"] = Part.make(
		&"differential",
		Part.Slot.CHASSIS,
		"差速底盘",
		"左右轮独立驱动的经典差速底盘：可原地旋转，是最灵活的基准底盘。",
		PackedStringArray([CAPABILITY_MOVE, CAPABILITY_ROTATE]),
		Vector2i.ONE,
		2.0,
		0.55,
		18.0,
		20.0,
		30.0,
		0,
		true,
		PackedStringArray(["搬运", "狭窄通道", "综合关"])
	)
	_chassis[&"skid_steer"] = Part.make(
		&"skid_steer",
		Part.Slot.CHASSIS,
		"滑移转向底盘",
		"履带式滑移转向：同样可原地旋转，速度较慢但载重与稳定性更好。",
		PackedStringArray([CAPABILITY_MOVE, CAPABILITY_ROTATE]),
		Vector2i.ONE,
		1.7,
		0.8,
		24.0,
		26.0,
		40.0,
		0,
		true,
		PackedStringArray(["重载运输", "长距离", "综合关"])
	)
	_chassis[&"omni"] = Part.make(
		&"omni",
		Part.Slot.CHASSIS,
		"全向底盘",
		"麦克纳姆轮全向底盘：MoveTo 不改变朝向（少一次转身），移动更快，但载重最低。",
		PackedStringArray([CAPABILITY_MOVE, CAPABILITY_ROTATE, VehicleDefinitionScript.CAPABILITY_CAN_STRAFE]),
		Vector2i.ONE,
		2.3,
		0.45,
		14.0,
		14.0,
		14.0,
		0,
		true,
		PackedStringArray(["高速取件", "时间挑战", "对位取件"])
	)

	# ---------------- 轮组 ----------------
	_wheels[&"standard"] = Part.make(
		&"standard",
		Part.Slot.WHEEL,
		"标准轮组",
		"通用橡胶轮组，速度/成本均衡。",
		PackedStringArray(),
		Vector2i.ONE,
		0.0,
		1.0,
		4.0,
		0.0,
		0.0,
		0,
		false,
		PackedStringArray([])
	)
	_wheels[&"fast"] = Part.make(
		&"fast",
		Part.Slot.WHEEL,
		"高速轮组",
		"轻量高速轮组：速度 +15%，载重略降。",
		PackedStringArray(),
		Vector2i.ONE,
		0.0,
		1.0,
		3.0,
		0.0,
		0.0,
		0,
		false,
		PackedStringArray([])
	)
	_wheels[&"fast"].speed_multiplier = 1.15
	_wheels[&"heavy"] = Part.make(
		&"heavy",
		Part.Slot.WHEEL,
		"重载轮组",
		"加宽重载轮组：速度 -10%，允许更高载重。",
		PackedStringArray(),
		Vector2i.ONE,
		0.0,
		1.0,
		8.0,
		0.0,
		0.0,
		0,
		false,
		PackedStringArray([])
	)
	_wheels[&"heavy"].speed_multiplier = 0.9

	# ---------------- 工作件 ----------------
	_work_modules[&"gripper_arm"] = Part.make(
		&"gripper_arm",
		Part.Slot.WORK_MODULE,
		"机械臂抓手",
		"单件抓取/放置工作件。用于取件、装车、把方块送进目标箱。",
		PackedStringArray([CAPABILITY_GRAB, CAPABILITY_CARRY]),
		Vector2i.ONE,
		0.0,
		1.0,
		6.0,
		0.0,
		0.0,
		0,
		false,
		PackedStringArray(["取放", "装车", "分拣"])
	)
	_work_modules[&"cargo_tray"] = Part.make(
		&"cargo_tray",
		Part.Slot.WORK_MODULE,
		"货运托盘",
		"8 格托盘，可一次搬运多件货物；自身不具备抓取能力。",
		PackedStringArray([CAPABILITY_CARRY, CAPABILITY_TRAY]),
		Vector2i.ONE,
		0.0,
		1.0,
		5.0,
		0.0,
		0.0,
		8,
		false,
		PackedStringArray(["批量运输", "中转站", "长距离"])
	)
	# 设计文档中的后续工作件（未进入 MVP 目录）：
	# - 推铲 push_blade：can_push，用于清障/把方块推入沟槽；
	# - 扫描器 scanner：can_scan，用于标识目标箱编号（Bean Sorting 关卡）；
	# - 升降台 lifter：can_lift，用于跨层平台；
	# - 焊枪/fabricator：can_assemble，自复制终局阶段用于组装其它小车。

	# 抽象成本：蓝图预算与自复制闸门用（关卡设计可限制总成本）。
	var cost_by_part := {
		&"differential": 12,
		&"skid_steer": 16,
		&"omni": 14,
		&"standard": 2,
		&"fast": 3,
		&"heavy": 4,
		&"gripper_arm": 8,
		&"cargo_tray": 6,
	}
	for table in [_chassis, _wheels, _work_modules]:
		for part_id in table:
			table[part_id].cost = int(cost_by_part.get(part_id, 0))

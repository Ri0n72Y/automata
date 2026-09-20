class_name Scene01TutorialUI
extends CanvasLayer

const TutorialScript := preload("res://scripts/scene_01/scene_01_tutorial.gd")
const CompileGateScript := preload("res://scripts/scene_01/scene_01_assembly_compile_gate.gd")
const AssemblyAdapterScript := preload("res://scripts/scene_01/scene_01_assembly_definition_adapter.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const AssemblyCapabilitiesScript := preload("res://scripts/assembly/assembly_capabilities.gd")
const ObservableScript := preload("res://scripts/scene_01/scene_01_observable_state.gd")
const LayoutMetrics := preload("res://scripts/scene_01/scene_01_ui_layout_metrics.gd")

@onready var _panel: PanelContainer = %TutorialPanel
@onready var _progress_label: Label = %ProgressLabel
@onready var _title_label: Label = %StepTitle
@onready var _body_label: Label = %StepBody
@onready var _goal_label: Label = %GoalLabel
@onready var _capability_label: Label = %CapabilityLabel
@onready var _previous_button: Button = %PreviousButton
@onready var _next_button: Button = %NextButton
@onready var _skip_button: Button = %SkipButton
@onready var _root: Node = get_parent()
@onready var _tutorial: TutorialScript = _root.get_node("SceneRoot/Scene01Tutorial") as TutorialScript
@onready var _observable: ObservableScript = _root.get_node("SceneRoot/Scene01ObservableState") as ObservableScript
@onready var _compile_gate: CompileGateScript = _root.get_node("SceneRoot/Scene01AssemblyCompileGate") as CompileGateScript
@onready var _manual_guide: Control = _root.get_node("UIRoot/RootControl") as Control
@onready var _reopen_button: Button = _root.get_node("UIRoot/RootControl/Panel/Margin/VBox/HeaderRow/TutorialButton") as Button


func _ready() -> void:
	_previous_button.pressed.connect(_tutorial.previous_step)
	_next_button.pressed.connect(_tutorial.next_step)
	_skip_button.pressed.connect(_tutorial.skip_tutorial)
	_reopen_button.pressed.connect(_tutorial.reopen_tutorial)
	_tutorial.presentation_changed.connect(_refresh)
	_observable.configured.connect(_refresh)
	_observable.standard_box_count_changed.connect(func(_a, _b): _refresh())
	_root.lifecycle_state_changed.connect(func(_a, _b): _refresh())
	get_viewport().size_changed.connect(_apply_left_rail_layout)
	_apply_left_rail_layout()
	_refresh()
	call_deferred("_refresh")


func _apply_left_rail_layout() -> void:
	var viewport_width := float(get_viewport().get_visible_rect().size.x)
	_panel.offset_right = _panel.offset_left + LayoutMetrics.left_rail_width(viewport_width)


func _refresh() -> void:
	var tutorial_visible := _tutorial.is_visible()
	_panel.visible = tutorial_visible
	_manual_guide.visible = not tutorial_visible
	if not tutorial_visible:
		return
	var step := _tutorial.get_step()
	_progress_label.text = "教学完成" if step == TutorialScript.Step.DONE else "目标 %d / 5" % _tutorial.get_completed_goal_count()
	_title_label.text = _step_title(step)
	_body_label.text = _step_body(step)
	_goal_label.text = _goal_text(step)
	_capability_label.text = _capability_summary()
	_previous_button.disabled = step == TutorialScript.Step.SELECT_ARM
	_next_button.disabled = step == TutorialScript.Step.DONE or (step == TutorialScript.Step.MULTI_VEHICLE and not _tutorial.are_all_goals_complete())
	_skip_button.text = "关闭教学" if step == TutorialScript.Step.DONE else "跳过教学"


func _goal_text(step: int) -> String:
	var state := "1/1" if _tutorial.is_goal_complete(step) else "0/1"
	var page_goal := ""
	match step:
		TutorialScript.Step.SELECT_ARM: page_goal = "选择 Arm（%s）" % state
		TutorialScript.Step.MANUAL_PICKUP: page_goal = "手动抓取方块（%s）" % state
		TutorialScript.Step.MANUAL_DROP: page_goal = "箱子计数 +1（%s）" % state
		TutorialScript.Step.PROGRAM_RUN: page_goal = "Program 自动装箱 +1（%s）" % state
		TutorialScript.Step.MULTI_VEHICLE: page_goal = "同一 Program 控制 Arm + Transport（%s）" % state
		_: page_goal = "教学目标（5/5）"
	var current_box := _observable.get_standard_box_count() if _observable.is_configured() else 0
	var target_box := int(_root.call("get_mission_target_count"))
	return "本页目标：%s\n场景目标：填满 StandardBox（%d/%d）" % [page_goal, current_box, target_box]


func _capability_summary() -> String:
	return "%s\n%s" % [
		_capability_line(VehicleManagerScript.ARM_VEHICLE_ID, "Arm", true),
		_capability_line(VehicleManagerScript.TRANSPORT_VEHICLE_ID, "Transport", false),
	]


func _capability_line(vehicle_id: StringName, label: String, is_arm: bool) -> String:
	var result = _compile_gate.get_compile_result(vehicle_id)
	if result == null or not result.is_success():
		return "%s：首次运行后确认" % label
	var parts := PackedStringArray(["编译通过"])
	if result.has_capability(AssemblyCapabilitiesScript.CAN_MOVE):
		parts.append("可移动")
	if is_arm and result.has_capability(AssemblyCapabilitiesScript.GRAB_DROP):
		parts.append("可抓取")
	if not is_arm and _has_interface(result, AssemblyAdapterScript.TRAY_INTERFACE_KIND):
		parts.append("可承载")
	return "%s：%s" % [label, " · ".join(parts)]


func _has_interface(result, kind: StringName) -> bool:
	for interface_value in result.get_interaction_interfaces():
		if interface_value != null and interface_value.kind == kind:
			return true
	return false


func _step_title(step: int) -> String:
	match step:
		TutorialScript.Step.SELECT_ARM: return "1 · 选择机械臂"
		TutorialScript.Step.MANUAL_PICKUP: return "2 · 手动抓取"
		TutorialScript.Step.MANUAL_DROP: return "3 · 手动装箱"
		TutorialScript.Step.PROGRAM_RUN: return "4 · 基础自动化"
		TutorialScript.Step.MULTI_VEHICLE: return "5 · 一个程序，多辆车"
		_: return "教学完成"


func _step_body(step: int) -> String:
	match step:
		TutorialScript.Step.SELECT_ARM: return "左键点击机械臂小车。HUD 会显示当前车辆状态。"
		TutorialScript.Step.MANUAL_PICKUP: return "M 选择方块堆旁目标格；A/D 每次旋转 90°；C 抓取。"
		TutorialScript.Step.MANUAL_DROP: return "移动到 StandardBox 旁并按 C 放入方块。Tips：可从上方灵动岛切换倍速。"
		TutorialScript.Step.PROGRAM_RUN: return "打开右侧 PROGRAM，用 Arm 的 MoveTo + Rotate + GrabDrop 完成一次真实装箱。"
		TutorialScript.Step.MULTI_VEHICLE: return "在同一成功装箱程序加入 Transport MoveTo；每条命令显式写 vehicle_id。"
		_: return "五个教学目标均已完成；场景最终目标仍是填满 StandardBox。"

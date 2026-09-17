class_name Scene01TutorialUI
extends CanvasLayer
const TutorialScript := preload("res://scripts/scene_01/scene_01_tutorial.gd")
const CompileGateScript := preload("res://scripts/scene_01/scene_01_assembly_compile_gate.gd")
const AssemblyAdapterScript := preload("res://scripts/scene_01/scene_01_assembly_definition_adapter.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const AssemblyCapabilitiesScript := preload("res://scripts/assembly/assembly_capabilities.gd")
@onready var _panel: PanelContainer = %TutorialPanel
@onready var _progress_label: Label = %ProgressLabel
@onready var _title_label: Label = %StepTitle
@onready var _body_label: Label = %StepBody
@onready var _capability_label: Label = %CapabilityLabel
@onready var _skip_button: Button = %SkipButton
@onready var _root: Node = get_parent()
@onready var _tutorial: TutorialScript = _root.get_node("SceneRoot/Scene01Tutorial") as TutorialScript
@onready var _compile_gate: CompileGateScript = _root.get_node("SceneRoot/Scene01AssemblyCompileGate") as CompileGateScript
@onready var _manual_guide: Control = _root.get_node("UIRoot/RootControl") as Control
@onready var _reopen_button: Button = _root.get_node("UIRoot/RootControl/Panel/Margin/VBox/HeaderRow/TutorialButton") as Button
func _ready() -> void:
	_skip_button.pressed.connect(_on_skip_pressed)
	_reopen_button.pressed.connect(_on_reopen_pressed)
	_tutorial.presentation_changed.connect(_refresh)
	_root.lifecycle_state_changed.connect(_on_lifecycle_state_changed)
	_refresh()
func _on_skip_pressed() -> void:
	_tutorial.skip_tutorial()
func _on_reopen_pressed() -> void:
	_tutorial.reopen_tutorial()
func _on_lifecycle_state_changed(_previous_state: int, _current_state: int) -> void:
	_refresh()
func _refresh() -> void:
	var tutorial_visible := _tutorial.is_visible()
	_panel.visible = tutorial_visible
	_manual_guide.visible = not tutorial_visible
	if not tutorial_visible:
		return
	var step := _tutorial.get_step()
	_progress_label.text = "完成" if step == TutorialScript.Step.DONE else "步骤 %d / %d" % [step + 1, TutorialScript.Step.DONE]
	_title_label.text = _step_title(step)
	_body_label.text = _step_body(step)
	_capability_label.text = _capability_summary()
	_skip_button.text = "关闭教学" if step == TutorialScript.Step.DONE else "跳过教学"
func _capability_summary() -> String:
	return "%s\n%s" % [
		_capability_line(VehicleManagerScript.ARM_VEHICLE_ID, "机械臂小车", true),
		_capability_line(VehicleManagerScript.TRANSPORT_VEHICLE_ID, "运输平台", false),
	]
func _capability_line(vehicle_id: StringName, label: String, is_arm: bool) -> String:
	var result = _compile_gate.get_compile_result(vehicle_id)
	if result == null or not result.is_success():
		return "%s：首次运行后由装配编译确认" % label
	var parts := PackedStringArray(["编译通过"])
	if result.has_capability(AssemblyCapabilitiesScript.CAN_MOVE):
		parts.append("可移动")
	if is_arm and result.has_capability(AssemblyCapabilitiesScript.GRAB_DROP):
		parts.append("可抓取")
	if not is_arm and _has_interface(result, AssemblyAdapterScript.TRAY_INTERFACE_KIND):
		parts.append("可承载")
	return "%s：%s" % [label, " / ".join(parts)]
func _has_interface(result, kind: StringName) -> bool:
	for interface_value in result.get_interaction_interfaces():
		if interface_value != null and interface_value.kind == kind:
			return true
	return false
func _step_title(step: int) -> String:
	match step:
		TutorialScript.Step.SELECT_ARM:
			return "1 · 选择机械臂"
		TutorialScript.Step.MANUAL_PICKUP:
			return "2 · 手动抓取"
		TutorialScript.Step.MANUAL_DROP:
			return "3 · 手动装箱"
		TutorialScript.Step.PROGRAM_RUN:
			return "4 · 基础自动化"
		TutorialScript.Step.MULTI_VEHICLE:
			return "5 · 一个程序，多辆车"
		_:
			return "教学完成"
func _step_body(step: int) -> String:
	match step:
		TutorialScript.Step.SELECT_ARM:
			return "左键点击机械臂小车。左下角 HUD 会显示当前选中车辆和可用命令。"
		TutorialScript.Step.MANUAL_PICKUP:
			return "按 M 移动到左侧方块堆的交互位置，确认目标后用 A / D 调整朝向，再按 C 抓取。"
		TutorialScript.Step.MANUAL_DROP:
			return "把机械臂移动到右侧 StandardBox 的交互位置，朝向箱体并按 C 放入一个方块。"
		TutorialScript.Step.PROGRAM_RUN:
			return "在右侧 PROGRAM SOURCE 用 Arm 的 MoveTo + GrabDrop 创建并 Run 一次真实装箱程序。可用按钮，也可直接改源码；错误会定位到物理行号。"
		TutorialScript.Step.MULTI_VEHICLE:
			return "在同一个成功装箱程序中再加入 Transport 的 MoveTo。DSL v2 没有 SelectVehicle：每条 [vehicle_id:command] 自己写明执行车辆。"
		_:
			return "你已经完成手动搬运、基础 Program 和最小多车串行。可继续完成 StandardBox 任务并观察最终评分。"

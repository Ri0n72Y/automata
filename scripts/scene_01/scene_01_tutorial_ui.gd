class_name Scene01TutorialUI
extends CanvasLayer
const TutorialScript := preload("res://scripts/scene_01/scene_01_tutorial.gd")
@onready var _panel: PanelContainer = %TutorialPanel
@onready var _reopen_button: Button = %ReopenTutorialButton
@onready var _progress_label: Label = %ProgressLabel
@onready var _title_label: Label = %StepTitle
@onready var _body_label: Label = %StepBody
@onready var _capability_label: Label = %CapabilityLabel
@onready var _skip_button: Button = %SkipButton
@onready var _manual_guide: Control = get_parent().get_node_or_null("UIRoot/RootControl") as Control
var _tutorial: TutorialScript
func _ready() -> void:
	_tutorial = get_parent().get_node("SceneRoot/Scene01Tutorial") as TutorialScript
	_skip_button.pressed.connect(_on_skip_pressed)
	_reopen_button.pressed.connect(_on_reopen_pressed)
	_tutorial.step_changed.connect(_on_step_changed)
	_tutorial.visibility_changed.connect(_on_visibility_changed)
	_tutorial.presentation_changed.connect(_refresh)
	_refresh()
func _on_skip_pressed() -> void:
	_tutorial.skip_tutorial()
func _on_reopen_pressed() -> void:
	_tutorial.reopen_tutorial()
func _on_step_changed(_previous_step: int, _current_step: int) -> void:
	_refresh()
func _on_visibility_changed(_is_visible: bool) -> void:
	_refresh()
func _refresh() -> void:
	if _tutorial == null:
		return
	var tutorial_visible := _tutorial.is_visible()
	_panel.visible = tutorial_visible
	_reopen_button.visible = not tutorial_visible
	if _manual_guide != null:
		_manual_guide.visible = not tutorial_visible
	if not tutorial_visible:
		return
	var step := _tutorial.get_step()
	_progress_label.text = "完成" if step == TutorialScript.Step.DONE else "步骤 %d / 5" % (step + 1)
	_title_label.text = _step_title(step)
	_body_label.text = _step_body(step)
	_capability_label.text = _tutorial.get_capability_summary()
	_skip_button.text = "关闭教学" if step == TutorialScript.Step.DONE else "跳过教学"
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

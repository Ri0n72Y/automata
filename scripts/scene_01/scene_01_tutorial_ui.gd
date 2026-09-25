class_name Scene01TutorialUI
extends VBoxContainer

const TutorialScript := preload("res://scripts/scene_01/scene_01_tutorial.gd")
const ObservableScript := preload("res://scripts/scene_01/scene_01_observable_state.gd")

@onready var _progress_label: Label = %ProgressLabel
@onready var _collapse_button: Button = %CollapseButton
@onready var _body: VBoxContainer = %TutorialBody
@onready var _title_label: Label = %StepTitle
@onready var _body_label: Label = %StepBody
@onready var _goal_label: Label = %GoalLabel
@onready var _previous_button: Button = %PreviousButton
@onready var _next_button: Button = %NextButton
@onready var _skip_button: Button = %SkipButton
@onready var _guide_section: VBoxContainer = %GuideSection
@onready var _reopen_button: Button = %TutorialButton

var _root: Node
var _tutorial: TutorialScript
var _observable: ObservableScript
var _collapsed := false


func _ready() -> void:
	_root = _find_scene_root()
	if _root == null:
		push_error("Scene01TutorialUI requires a Scene 01 composition root.")
		return
	_tutorial = _root.get_node("SceneRoot/Scene01Tutorial") as TutorialScript
	_observable = _root.get_node("SceneRoot/Scene01ObservableState") as ObservableScript
	_previous_button.pressed.connect(_tutorial.previous_step)
	_next_button.pressed.connect(_tutorial.next_step)
	_skip_button.pressed.connect(_tutorial.skip_tutorial)
	_collapse_button.pressed.connect(_on_collapse_pressed)
	_reopen_button.pressed.connect(_tutorial.reopen_tutorial)
	_tutorial.presentation_changed.connect(_refresh)
	_observable.configured.connect(_refresh)
	_observable.standard_box_count_changed.connect(func(_a, _b): _refresh())
	_root.lifecycle_state_changed.connect(func(_a, _b): _refresh())
	set_collapsed(false)
	_refresh()
	call_deferred("_refresh")


func set_collapsed(collapsed: bool) -> void:
	_collapsed = collapsed
	if _body != null:
		_body.visible = not _collapsed
	if _collapse_button != null:
		_collapse_button.text = "+" if _collapsed else "−"
		_collapse_button.tooltip_text = "展开教学" if _collapsed else "折叠教学"
	if _collapsed:
		get_viewport().gui_release_focus()


func is_collapsed() -> bool:
	return _collapsed


func _on_collapse_pressed() -> void:
	set_collapsed(not _collapsed)


func _refresh() -> void:
	if _tutorial == null or _observable == null:
		return
	var tutorial_visible := _tutorial.is_visible()
	visible = tutorial_visible
	_guide_section.visible = not tutorial_visible
	if not tutorial_visible:
		return
	var step := _tutorial.get_step()
	_progress_label.text = (
		"教学完成"
		if step == TutorialScript.Step.DONE
		else "目标 %d / 5" % _tutorial.get_completed_goal_count()
	)
	_title_label.text = _step_title(step)
	_body_label.text = _step_body(step)
	_goal_label.text = _goal_text(step)
	_previous_button.disabled = step == TutorialScript.Step.SELECT_ARM
	_next_button.disabled = (
		step == TutorialScript.Step.DONE
		or (
			step == TutorialScript.Step.MULTI_VEHICLE
			and not _tutorial.are_all_goals_complete()
		)
	)
	_skip_button.text = "关闭教学" if step == TutorialScript.Step.DONE else "跳过教学"


func _find_scene_root() -> Node:
	var cursor: Node = self
	while cursor != null:
		if cursor.has_node("SceneRoot/Scene01Tutorial"):
			return cursor
		cursor = cursor.get_parent()
	return null


func _goal_text(step: int) -> String:
	var state := "1/1" if _tutorial.is_goal_complete(step) else "0/1"
	var page_goal := ""
	match step:
		TutorialScript.Step.SELECT_ARM:
			page_goal = "选择机械臂车（%s）" % state
		TutorialScript.Step.MANUAL_PICKUP:
			page_goal = "手动抓取方块（%s）" % state
		TutorialScript.Step.MANUAL_DROP:
			page_goal = "箱子计数 +1（%s）" % state
		TutorialScript.Step.PROGRAM_RUN:
			page_goal = "程序自动装箱 +1（%s）" % state
		TutorialScript.Step.MULTI_VEHICLE:
			page_goal = "同一程序控制机械臂车 + 运输车（%s）" % state
		_:
			page_goal = "教学目标（5/5）"
	var current_box := _observable.get_standard_box_count() if _observable.is_configured() else 0
	var target_box := int(_root.call("get_mission_target_count"))
	return "本页目标：%s\n场景目标：填满标准箱（%d/%d）" % [
		page_goal,
		current_box,
		target_box,
	]


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
			return "左键点击机械臂车。左侧状态区会显示当前车辆。"
		TutorialScript.Step.MANUAL_PICKUP:
			return "按 M 选择方块堆旁目标格；A / D 每次旋转 90°；C 抓取。"
		TutorialScript.Step.MANUAL_DROP:
			return "移动到标准箱旁并按 C 放入方块。提示：可从上方运行控制切换倍速。"
		TutorialScript.Step.PROGRAM_RUN:
			return "打开右侧程序面板，用机械臂车的移动、旋转和抓放命令完成一次真实装箱。"
		TutorialScript.Step.MULTI_VEHICLE:
			return "在同一成功装箱程序中加入运输车移动命令；每条命令仍显式指定车辆 ID。"
		_:
			return "五个教学目标均已完成；场景最终目标仍是填满标准箱。"

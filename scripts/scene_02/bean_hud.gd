extends CanvasLayer

## Bean Sorting HUD: consumes round assignment + settlement snapshots and
## lifecycle state; owns no game truth.

const BeanSortingControllerScript := preload("res://scripts/scene_02/bean_sorting_controller.gd")
const BeanBatchScript := preload("res://scripts/beans/bean_batch.gd")

@export var scene_controller_path: NodePath = NodePath("..")

@onready var state_label: Label = %StateLabel
@onready var mapping_label: Label = %MappingLabel
@onready var targets_label: Label = %TargetsLabel
@onready var sources_label: Label = %SourcesLabel
@onready var submit_button: Button = %SubmitButton
@onready var reroll_button: Button = %RerollButton
@onready var result_panel: PanelContainer = %ResultPanel
@onready var result_label: Label = %ResultLabel

var controller: BeanSortingControllerScript


func _ready() -> void:
	controller = get_node_or_null(scene_controller_path) as BeanSortingControllerScript
	mapping_label.text = "黄豆 → 1 号箱\n绿豆 → 2 号箱\n白豆 → 3 号箱\n（4 / 5 号为干扰箱）"
	submit_button.pressed.connect(_on_submit)
	reroll_button.pressed.connect(_on_reroll)
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _on_submit() -> void:
	if controller != null:
		controller.submit_beans()
	_refresh()


func _on_reroll() -> void:
	if controller != null:
		controller.reroll_round()
	_refresh()


func _refresh() -> void:
	if controller == null:
		return
	if not bool(controller.call("is_scene_initialized")):
		state_label.text = "场景初始化中…"
		submit_button.disabled = true
		return
	var state: int = controller.get_bean_state()
	state_label.text = _state_text(state)
	targets_label.text = _targets_text()
	sources_label.text = _sources_text()
	var runner := controller.get_node_or_null("SceneRoot/Scene01ProgramRunner")
	var runner_busy := runner != null and bool(runner.call("is_busy"))
	submit_button.disabled = (
		state != BeanSortingControllerScript.BeanState.RUNNING
		or controller.is_settled()
		or runner_busy
	)
	reroll_button.disabled = (
		state == BeanSortingControllerScript.BeanState.RUNNING
		or state == BeanSortingControllerScript.BeanState.PAUSED
	)
	result_panel.visible = controller.is_settled()
	if result_panel.visible:
		result_label.text = _result_text(controller.get_settlement())


func _state_text(state: int) -> String:
	match state:
		BeanSortingControllerScript.BeanState.RUNNING:
			return "状态：运行中"
		BeanSortingControllerScript.BeanState.PAUSED:
			return "状态：已暂停"
		BeanSortingControllerScript.BeanState.COMPLETED:
			return "状态：已结算"
		_:
			return "状态：就绪"


func _targets_text() -> String:
	var manager = controller.get_bean_object_manager()
	if manager == null:
		return ""
	var targets = manager.get_targets()
	var lines: Array[String] = ["目标箱（本局编号）："]
	for index in range(targets.size()):
		var number: int = controller.get_box_number_for_slot(index)
		var grams: int = targets[index].inventory.get_total_grams()
		var kind := ""
		if number == 1:
			kind = " ← 黄豆"
		elif number == 2:
			kind = " ← 绿豆"
		elif number == 3:
			kind = " ← 白豆"
		lines.append("#%d  %d g%s" % [number, grams, kind])
	return "\n".join(lines)


func _sources_text() -> String:
	var manager = controller.get_bean_object_manager()
	if manager == null:
		return ""
	var lines: Array[String] = []
	for source in manager.get_sources():
		lines.append(
			"%s：%d g" % [
				BeanBatchScript.display_name_for(source.bean_type),
				source.inventory.remaining_grams,
			]
		)
	return "来源剩余：\n" + "\n".join(lines)


func _result_text(snapshot: Dictionary) -> String:
	var per_bean: Dictionary = snapshot.get("per_bean_correct", {})
	var lines: Array[String] = [
		"最终得分：%d / %d" % [
			int(snapshot.get("score", 0)),
			int(snapshot.get("max_score", 3000)),
		],
		"正确交付：%d g" % int(snapshot.get("correct_grams", 0)),
		"错箱：%d g" % int(snapshot.get("wrong_box_grams", 0)),
		"流失/未提交：%d g" % int(snapshot.get("lost_or_unsubmitted_grams", 0)),
		"黄豆正确：%d g" % int(per_bean.get(BeanBatchScript.TYPE_SOYBEAN, 0)),
		"绿豆正确：%d g" % int(per_bean.get(BeanBatchScript.TYPE_MUNG_BEAN, 0)),
		"白豆正确：%d g" % int(per_bean.get(BeanBatchScript.TYPE_WHITE_BEAN, 0)),
		"用时：%.1f s" % float(snapshot.get("elapsed_time", 0.0)),
	]
	return "\n".join(lines)

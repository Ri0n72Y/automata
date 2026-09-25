class_name Scene01Hud
extends CanvasLayer

const ObservableStateScript := preload("res://scripts/scene_01/scene_01_observable_state.gd")
const MissionControllerScript := preload("res://scripts/scene_01/scene_01_mission_controller.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const VehicleRuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const VehicleDefinitionScript := preload("res://scripts/vehicles/vehicle_definition.gd")
const VehicleActorScript := preload("res://scripts/vehicles/vehicle_actor.gd")
const VehicleSelectionControllerScript := preload("res://scripts/input/vehicle_selection_controller.gd")
const GridSelectionControllerScript := preload("res://scripts/input/grid_selection_controller.gd")
const VehicleMoveControllerScript := preload("res://scripts/input/vehicle_move_controller.gd")
const VehicleGrabDropControllerScript := preload("res://scripts/input/vehicle_grab_drop_controller.gd")
const MissionStateScript := preload("res://scripts/scene_01/scene_01_mission_state.gd")
const GrabDropResultScript := preload("res://scripts/vehicles/grab_drop_result.gd")
const LayoutMetrics := preload("res://scripts/scene_01/scene_01_ui_layout_metrics.gd")
const CHEVRON_DOWN_ICON: Texture2D = preload("res://assets/ui/icons/chevron_down.svg")
const CHEVRON_RIGHT_ICON: Texture2D = preload("res://assets/ui/icons/chevron_right.svg")

@onready var selected_label: Label = %SelectedLabel
@onready var mission_label: Label = %MissionLabel
@onready var mission_value_label: Label = %MissionValueLabel
@onready var mission_progress: ProgressBar = %MissionProgress
@onready var pointer_label: Label = %PointerLabel
@onready var position_value_label: Label = %PositionValueLabel
@onready var facing_value_label: Label = %FacingValueLabel
@onready var cargo_name_label: Label = %CargoNameLabel
@onready var cargo_value_label: Label = %CargoValueLabel
@onready var move_value_label: Label = %MoveValueLabel
@onready var rotate_value_label: Label = %RotateValueLabel
@onready var grab_value_label: Label = %GrabValueLabel
@onready var feedback_label: Label = %FeedbackLabel
@onready var completion_panel: PanelContainer = %CompletionPanel
@onready var completion_summary_label: Label = %CompletionSummaryLabel
@onready var sidebar_panel: PanelContainer = %SidebarPanel
@onready var status_card: PanelContainer = %StatusCard
@onready var status_collapse_button: Button = %StatusCollapseButton

var _status_collapsed := false

var _scene_controller: MissionControllerScript
var _observable: ObservableStateScript
var _vehicle_manager: VehicleManagerScript
var _vehicle_selection: VehicleSelectionControllerScript
var _grid_selection: GridSelectionControllerScript
var _move_controller: VehicleMoveControllerScript
var _grab_drop_controller: VehicleGrabDropControllerScript


func _ready() -> void:
	_scene_controller = get_parent() as MissionControllerScript
	_observable = _scene_controller.get_node("SceneRoot/Scene01ObservableState") as ObservableStateScript
	_vehicle_manager = _scene_controller.get_node(
		"SceneRoot/RobotRoot/Scene01VehicleManager"
	) as VehicleManagerScript
	_vehicle_selection = _scene_controller.get_node(
		"SceneRoot/GridRoot/VehicleSelectionController"
	) as VehicleSelectionControllerScript
	_grid_selection = _scene_controller.get_node(
		"SceneRoot/GridRoot/GridSelectionController"
	) as GridSelectionControllerScript
	_move_controller = _scene_controller.get_node(
		"SceneRoot/GridRoot/VehicleMoveController"
	) as VehicleMoveControllerScript
	_grab_drop_controller = _scene_controller.get_node(
		"SceneRoot/GridRoot/VehicleGrabDropController"
	) as VehicleGrabDropControllerScript
	_bind_signals()
	status_collapse_button.pressed.connect(_on_status_collapse_pressed)
	set_status_collapsed(false)
	get_viewport().size_changed.connect(_apply_sidebar_layout)
	_apply_sidebar_layout()
	_refresh()
	call_deferred("_refresh")


func _apply_sidebar_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	sidebar_panel.offset_left = LayoutMetrics.EDGE_MARGIN
	sidebar_panel.offset_top = LayoutMetrics.CONTENT_TOP
	sidebar_panel.offset_right = sidebar_panel.offset_left + LayoutMetrics.left_rail_width(float(viewport_size.x))
	sidebar_panel.offset_bottom = sidebar_panel.offset_top


func set_status_collapsed(collapsed: bool) -> void:
	_status_collapsed = collapsed
	if status_card != null:
		status_card.visible = not _status_collapsed
	if status_collapse_button != null:
		status_collapse_button.icon = CHEVRON_RIGHT_ICON if _status_collapsed else CHEVRON_DOWN_ICON
		status_collapse_button.tooltip_text = "展开状态" if _status_collapsed else "折叠状态"
	if _status_collapsed:
		get_viewport().gui_release_focus()


func is_status_collapsed() -> bool:
	return _status_collapsed


func _on_status_collapse_pressed() -> void:
	set_status_collapsed(not _status_collapsed)


func _bind_signals() -> void:
	_observable.configured.connect(_refresh)
	_observable.vehicle_state_changed.connect(_on_observable_changed)
	_observable.arm_has_item_changed.connect(_on_observable_changed)
	_observable.tray_count_changed.connect(_on_observable_changed)
	_observable.standard_box_count_changed.connect(_on_observable_changed)
	_observable.mission_state_changed.connect(_on_observable_changed)
	_vehicle_selection.selection_changed.connect(_on_selection_changed)
	_grid_selection.hover_changed.connect(_on_hover_changed)
	_grid_selection.live_target_mode_changed.connect(_on_target_mode_changed)
	_move_controller.move_accepted.connect(_on_move_accepted)
	_move_controller.move_rejected.connect(_on_move_rejected)
	_move_controller.move_stopped.connect(_on_move_stopped)
	_grab_drop_controller.grab_drop_completed.connect(_on_grab_drop_completed)
	_grab_drop_controller.facing_changed.connect(_on_arm_facing_changed)
	_bind_vehicle_turn_signals(_vehicle_selection.get_selected_vehicle_id())
	_scene_controller.lifecycle_state_changed.connect(_on_lifecycle_changed)
	_scene_controller.lifecycle_reset_completed.connect(_on_reset_completed)


func _refresh() -> void:
	var observable_ready := _observable.is_configured()
	var selected_id := _vehicle_selection.get_selected_vehicle_id()
	var has_selection := selected_id != &""
	selected_label.text = _selected_vehicle_name(selected_id)

	var motion_state := -1
	if observable_ready and has_selection:
		motion_state = _observable.get_vehicle_state(selected_id)

	if observable_ready:
		var target_count := _scene_controller.get_mission_target_count()
		var current_count := _observable.get_standard_box_count()
		var box_text := str(current_count)
		if target_count > 0:
			box_text = "%d/%d" % [current_count, target_count]
		mission_label.text = "标准箱"
		mission_value_label.text = box_text.replace("/", " / ")
		mission_progress.max_value = maxf(float(target_count), 1.0)
		mission_progress.value = float(current_count)
		var mission_state := _observable.get_mission_state()
		completion_panel.visible = mission_state == MissionStateScript.State.COMPLETED
		if completion_panel.visible:
			completion_summary_label.text = "标准箱 %s · 任务已完成" % box_text
	else:
		mission_label.text = "标准箱"
		mission_value_label.text = "—"
		mission_progress.max_value = 1.0
		mission_progress.value = 0.0
		completion_panel.visible = false

	_refresh_pointer_label()
	_grab_drop_controller.refresh_interaction_preview()
	_refresh_vehicle_status(selected_id, motion_state)


func _refresh_pointer_label() -> void:
	if _grid_selection != null and _grid_selection.has_hovered_cell():
		var cell := _grid_selection.hovered_cell
		pointer_label.text = "X %d   Y %d" % [cell.x, cell.y]
	else:
		pointer_label.text = "X —   Y —"


func _refresh_vehicle_status(selected_id: StringName, motion_state: int) -> void:
	if selected_id == &"":
		position_value_label.text = "—"
		facing_value_label.text = "—"
		cargo_name_label.text = "载荷"
		cargo_value_label.text = "—"
		_set_availability(move_value_label, "—")
		_set_availability(rotate_value_label, "—")
		_set_availability(grab_value_label, "—")
		return

	var vehicle := _vehicle_manager.get_vehicle_by_id(selected_id) as VehicleActorScript
	if vehicle == null or vehicle.runtime_state == null or vehicle.definition == null:
		position_value_label.text = "—"
		facing_value_label.text = "—"
		cargo_name_label.text = "载荷"
		cargo_value_label.text = "—"
		_set_availability(move_value_label, "—")
		_set_availability(rotate_value_label, "—")
		_set_availability(grab_value_label, "—")
		return

	var runtime = vehicle.runtime_state
	position_value_label.text = "%d, %d" % [runtime.anchor_cell.x, runtime.anchor_cell.y]
	facing_value_label.text = _facing_text(runtime.facing)

	if vehicle.definition.has_capability(VehicleDefinitionScript.CAPABILITY_CAN_GRAB):
		cargo_name_label.text = "手持"
		cargo_value_label.text = "方块" if runtime.arm_has_item else "空"
	elif vehicle.definition.has_capability(VehicleDefinitionScript.CAPABILITY_HAS_TRAY):
		cargo_name_label.text = "托盘"
		cargo_value_label.text = str(runtime.tray_count)
	else:
		cargo_name_label.text = "载荷"
		cargo_value_label.text = "—"

	var statuses := _availability_statuses(vehicle, motion_state)
	_set_availability(move_value_label, String(statuses.move))
	_set_availability(rotate_value_label, String(statuses.rotate))
	_set_availability(grab_value_label, String(statuses.grab))


func _availability_statuses(vehicle: VehicleActorScript, motion_state: int) -> Dictionary:
	if vehicle == null or vehicle.definition == null:
		return {"move": "—", "rotate": "—", "grab": "—"}
	if _scene_controller.is_scene_paused():
		return {"move": "暂停", "rotate": "暂停", "grab": "暂停"}

	var definition = vehicle.definition
	var turning := vehicle.is_turning()
	var busy := (
		motion_state == VehicleRuntimeStateScript.MotionState.PLANNING
		or motion_state == VehicleRuntimeStateScript.MotionState.MOVING
	)

	var move_text := "可用"
	if not definition.has_capability(VehicleDefinitionScript.CAPABILITY_CAN_MOVE):
		move_text = "不可用"
	elif motion_state == VehicleRuntimeStateScript.MotionState.PLANNING:
		move_text = "规划中"
	elif motion_state == VehicleRuntimeStateScript.MotionState.MOVING:
		move_text = "移动中"
	elif motion_state == VehicleRuntimeStateScript.MotionState.BLOCKED:
		move_text = "受阻"
	elif turning:
		move_text = "忙碌"
	elif _grid_selection.is_live_target_mode():
		move_text = "选点中"

	var rotate_text := "可用"
	if not definition.has_capability(VehicleDefinitionScript.CAPABILITY_CAN_ROTATE):
		rotate_text = "不可用"
	elif turning:
		rotate_text = "旋转中"
	elif busy:
		rotate_text = "忙碌"
	elif _grid_selection.is_live_target_mode():
		rotate_text = "选点中"

	var grab_text := "无目标"
	if not definition.has_capability(VehicleDefinitionScript.CAPABILITY_CAN_GRAB):
		grab_text = "不可用"
	elif turning or busy:
		grab_text = "忙碌"
	elif _grid_selection.is_live_target_mode():
		grab_text = "选点中"
	elif _grab_drop_controller.is_interaction_preview_valid():
		grab_text = "可用"

	return {"move": move_text, "rotate": rotate_text, "grab": grab_text}


func _set_availability(label: Label, text: String) -> void:
	label.text = text
	var color := Color(0.28, 0.36, 0.45, 1)
	match text:
		"可用":
			color = Color(0.03, 0.62, 0.4, 1)
		"受阻":
			color = Color(0.72, 0.16, 0.16, 1)
		"规划中", "移动中", "旋转中", "选点中", "忙碌", "暂停":
			color = Color(0.72, 0.43, 0.08, 1)
	label.add_theme_color_override("font_color", color)


func _facing_text(facing: int) -> String:
	match facing:
		VehicleRuntimeStateScript.Facing.NORTH:
			return "北"
		VehicleRuntimeStateScript.Facing.EAST:
			return "东"
		VehicleRuntimeStateScript.Facing.SOUTH:
			return "南"
		VehicleRuntimeStateScript.Facing.WEST:
			return "西"
		_:
			return "—"


func _selected_vehicle_name(vehicle_id: StringName) -> String:
	if vehicle_id == &"":
		return "未选择"
	var vehicle = _vehicle_manager.get_vehicle_by_id(vehicle_id)
	if vehicle == null or vehicle.definition == null:
		return String(vehicle_id)
	return vehicle.definition.display_name


func _motion_state_text(state: int) -> String:
	match state:
		VehicleRuntimeStateScript.MotionState.WAITING:
			return "等待"
		VehicleRuntimeStateScript.MotionState.PLANNING:
			return "规划中"
		VehicleRuntimeStateScript.MotionState.MOVING:
			return "移动中"
		VehicleRuntimeStateScript.MotionState.BLOCKED:
			return "受阻"
		_:
			return "—"


func _mission_state_text(state: int) -> String:
	match state:
		MissionStateScript.State.READY:
			return "就绪"
		MissionStateScript.State.RUNNING:
			return "运行中"
		MissionStateScript.State.PAUSED:
			return "已暂停"
		MissionStateScript.State.COMPLETED:
			return "已完成"
		_:
			return "—"


func _on_observable_changed(_a = null, _b = null, _c = null) -> void:
	_refresh()


func _on_selection_changed(vehicle_id: StringName, has_selection: bool) -> void:
	if has_selection:
		_bind_vehicle_turn_signals(vehicle_id)
	_refresh()


func _on_hover_changed(_cell: Vector2i, _has_hover: bool) -> void:
	_refresh_pointer_label()


func _bind_vehicle_turn_signals(vehicle_id: StringName) -> void:
	if vehicle_id == &"":
		return
	var vehicle := _vehicle_manager.get_vehicle_by_id(vehicle_id) as VehicleActorScript
	if vehicle == null:
		return
	var started_callable := Callable(self, "_on_vehicle_turn_started")
	if not vehicle.turn_started.is_connected(started_callable):
		vehicle.turn_started.connect(started_callable)
	var completed_callable := Callable(self, "_on_vehicle_turn_completed")
	if not vehicle.turn_completed.is_connected(completed_callable):
		vehicle.turn_completed.connect(completed_callable)
	var move_completed_callable := Callable(self, "_on_vehicle_move_completed")
	if not vehicle.move_completed.is_connected(move_completed_callable):
		vehicle.move_completed.connect(move_completed_callable)


func _on_target_mode_changed(_active: bool) -> void:
	_refresh()


func _on_arm_facing_changed(_vehicle_id: StringName, _facing: int) -> void:
	_refresh()


func _on_vehicle_turn_started(_direction: int) -> void:
	_refresh()


func _on_vehicle_turn_completed(_facing: int) -> void:
	_refresh()


func _on_vehicle_move_completed(_target_anchor: Vector2i) -> void:
	_refresh()


func _on_lifecycle_changed(_previous_state: int, _current_state: int) -> void:
	_refresh()


func _on_reset_completed() -> void:
	_set_feedback("场景已重置", false)
	_refresh()


func _on_move_accepted(vehicle_id: StringName, _target_anchor: Vector2i) -> void:
	_set_feedback("%s：移动命令已接受" % _selected_vehicle_name(vehicle_id), false)
	_refresh()


func _on_move_rejected(vehicle_id: StringName, _target_anchor: Vector2i, reason: StringName) -> void:
	var prefix := _selected_vehicle_name(vehicle_id) if vehicle_id != &"" else "移动"
	_set_feedback("%s：%s" % [prefix, _move_rejection_text(reason)], true)
	_refresh()


func _on_move_stopped(vehicle_id: StringName) -> void:
	_set_feedback("%s：移动已停止" % _selected_vehicle_name(vehicle_id), false)
	_refresh()


func _on_grab_drop_completed(vehicle_id: StringName, action: int, status: int) -> void:
	var action_name := "抓取" if action == GrabDropResultScript.Action.GRAB else "放置"
	if action == GrabDropResultScript.Action.NONE:
		action_name = "抓放"
	if status == GrabDropResultScript.Status.ACCEPTED:
		_set_feedback("%s：%s成功" % [_selected_vehicle_name(vehicle_id), action_name], false)
	else:
		_set_feedback("%s：%s失败 · %s" % [
			_selected_vehicle_name(vehicle_id),
			action_name,
			_grab_drop_status_text(status),
		], true)
	_refresh()


func _set_feedback(message: String, is_error: bool) -> void:
	feedback_label.text = message
	feedback_label.visible = not message.is_empty()
	feedback_label.add_theme_color_override(
		"font_color",
		Color(0.72, 0.16, 0.16, 1) if is_error else Color(0.08, 0.48, 0.34, 1)
	)


func _move_rejection_text(reason: StringName) -> String:
	match reason:
		&"no_vehicle_selected":
			return "未选择车辆"
		&"no_move_capability":
			return "当前车辆无法移动"
		&"vehicle_busy":
			return "车辆正在执行任务"
		&"no_path":
			return "目标不可达"
		&"start_failed":
			return "移动启动失败"
		_:
			return "移动被拒绝"


func _grab_drop_status_text(status: int) -> String:
	match status:
		GrabDropResultScript.Status.NO_CAPABILITY:
			return "当前车辆没有机械臂能力"
		GrabDropResultScript.Status.BUSY:
			return "车辆正在执行任务"
		GrabDropResultScript.Status.NO_TARGET:
			return "前方没有唯一可交互目标"
		GrabDropResultScript.Status.EMPTY:
			return "来源为空"
		GrabDropResultScript.Status.FULL:
			return "目标已满"
		GrabDropResultScript.Status.TYPE_MISMATCH:
			return "物品类型不匹配"
		GrabDropResultScript.Status.ALREADY_CONTAINED:
			return "物品已被占用"
		GrabDropResultScript.Status.GROUND_OCCUPIED:
			return "地面位置已被占用"
		GrabDropResultScript.Status.OWNERSHIP_CONFLICT:
			return "物品所有权冲突"
		_:
			return "目标无效"

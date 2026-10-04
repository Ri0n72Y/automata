class_name Scene01Hud
extends CanvasLayer

const ObservableStateScript := preload("res://scripts/scene_01/scene_01_observable_state.gd")
const MissionControllerScript := preload("res://scripts/scene_01/scene_01_mission_controller.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const VehicleRuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const VehicleSelectionControllerScript := preload("res://scripts/input/vehicle_selection_controller.gd")
const GridSelectionControllerScript := preload("res://scripts/input/grid_selection_controller.gd")
const VehicleMoveControllerScript := preload("res://scripts/input/vehicle_move_controller.gd")
const VehicleGrabDropControllerScript := preload("res://scripts/input/vehicle_grab_drop_controller.gd")
const AvailabilityScript := preload("res://scripts/input/vehicle_command_availability.gd")
const ManualAvailabilityScript := preload("res://scripts/input/vehicle_manual_interaction_availability.gd")
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
@onready var sidebar_margin: MarginContainer = $RootControl/SidebarPanel/Margin
@onready var sidebar_scroll: ScrollContainer = %SidebarScroll
@onready var sidebar_content: VBoxContainer = %Sidebar
@onready var status_card: PanelContainer = %StatusCard
@onready var status_collapse_button: Button = %StatusCollapseButton
@onready var rail_collapse_button: Button = %RailCollapseButton

var _status_collapsed := false
var _rail_collapsed := false

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
	rail_collapse_button.pressed.connect(_on_rail_collapse_pressed)
	set_status_collapsed(false)
	set_rail_collapsed(false)
	sidebar_content.minimum_size_changed.connect(_queue_sidebar_layout)
	get_viewport().size_changed.connect(_apply_sidebar_layout)
	_apply_sidebar_layout()
	_refresh()
	call_deferred("_refresh")


func _apply_sidebar_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	sidebar_panel.offset_left = LayoutMetrics.EDGE_MARGIN
	sidebar_panel.offset_top = LayoutMetrics.CONTENT_TOP
	var rail_width := (
		LayoutMetrics.LEFT_RAIL_COLLAPSED_WIDTH
		if _rail_collapsed
		else LayoutMetrics.left_rail_width(float(viewport_size.x))
	)
	sidebar_panel.offset_right = sidebar_panel.offset_left + rail_width
	var content_height := (
		sidebar_content.get_combined_minimum_size().y
		+ sidebar_margin.get_theme_constant("margin_top")
		+ sidebar_margin.get_theme_constant("margin_bottom")
	)
	var max_height := LayoutMetrics.left_sidebar_max_height(float(viewport_size.y))
	var target_height := minf(content_height, max_height)
	sidebar_panel.offset_bottom = sidebar_panel.offset_top + target_height
	if rail_collapse_button != null:
		rail_collapse_button.offset_left = sidebar_panel.offset_right - 34.0
		rail_collapse_button.offset_top = sidebar_panel.offset_top + 8.0
		rail_collapse_button.offset_right = sidebar_panel.offset_right - 8.0
		rail_collapse_button.offset_bottom = sidebar_panel.offset_top + 34.0


func _queue_sidebar_layout() -> void:
	call_deferred("_apply_sidebar_layout")


func set_status_collapsed(collapsed: bool) -> void:
	_status_collapsed = collapsed
	if status_card != null:
		status_card.visible = not _status_collapsed
	if status_collapse_button != null:
		status_collapse_button.icon = CHEVRON_RIGHT_ICON if _status_collapsed else CHEVRON_DOWN_ICON
		status_collapse_button.tooltip_text = "展开状态" if _status_collapsed else "折叠状态"
	if _status_collapsed and status_card != null:
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner != null and status_card.is_ancestor_of(focus_owner):
			get_viewport().gui_release_focus()
	_queue_sidebar_layout()


func is_status_collapsed() -> bool:
	return _status_collapsed


func set_rail_collapsed(collapsed: bool) -> void:
	_rail_collapsed = collapsed
	if sidebar_margin != null:
		sidebar_margin.visible = not _rail_collapsed
	if sidebar_panel != null:
		sidebar_panel.mouse_filter = (
			Control.MOUSE_FILTER_IGNORE if _rail_collapsed else Control.MOUSE_FILTER_STOP
		)
	if rail_collapse_button != null:
		rail_collapse_button.text = "→" if _rail_collapsed else "←"
		rail_collapse_button.tooltip_text = "展开侧栏" if _rail_collapsed else "折叠侧栏"
	if _rail_collapsed:
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner != null and sidebar_margin != null and sidebar_margin.is_ancestor_of(focus_owner):
			get_viewport().gui_release_focus()
	_apply_sidebar_layout()


func is_rail_collapsed() -> bool:
	return _rail_collapsed


func _on_status_collapse_pressed() -> void:
	set_status_collapsed(not _status_collapsed)


func _on_rail_collapse_pressed() -> void:
	set_rail_collapsed(not _rail_collapsed)


func _bind_signals() -> void:
	_observable.configured.connect(_refresh)
	_observable.vehicle_state_changed.connect(_on_observable_changed)
	_observable.vehicle_pose_changed.connect(_on_observable_changed)
	_observable.vehicle_turning_changed.connect(_on_observable_changed)
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
	_scene_controller.lifecycle_state_changed.connect(_on_lifecycle_changed)
	_scene_controller.lifecycle_reset_completed.connect(_on_reset_completed)


func _refresh() -> void:
	var observable_ready := _observable.is_configured()
	var selected_id := _vehicle_selection.get_selected_vehicle_id()
	selected_label.text = _selected_vehicle_name(selected_id)

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
	_refresh_vehicle_status(selected_id)


func _refresh_pointer_label() -> void:
	if _grid_selection != null and _grid_selection.has_hovered_cell():
		var cell := _grid_selection.hovered_cell
		pointer_label.text = "X %d   Y %d" % [cell.x, cell.y]
	else:
		pointer_label.text = "X —   Y —"


func _refresh_vehicle_status(selected_id: StringName) -> void:
	if selected_id == &"":
		position_value_label.text = "—"
		facing_value_label.text = "—"
		cargo_name_label.text = "载荷"
		cargo_value_label.text = "—"
		_set_availability(move_value_label, "—")
		_set_availability(rotate_value_label, "—")
		_set_availability(grab_value_label, "—")
		return

	var anchor := _observable.get_vehicle_anchor_cell(selected_id)
	position_value_label.text = (
		"—"
		if anchor == Vector2i(-1, -1)
		else "%d, %d" % [anchor.x, anchor.y]
	)
	facing_value_label.text = _facing_text(_observable.get_vehicle_facing(selected_id))

	match selected_id:
		VehicleManagerScript.ARM_VEHICLE_ID:
			cargo_name_label.text = "手持"
			cargo_value_label.text = "方块" if _observable.get_arm_has_item() else "空"
		VehicleManagerScript.TRANSPORT_VEHICLE_ID:
			cargo_name_label.text = "托盘"
			cargo_value_label.text = str(_observable.get_tray_count())
		_:
			cargo_name_label.text = "载荷"
			cargo_value_label.text = "—"

	_set_availability(
		move_value_label,
		_availability_text(_move_controller.get_selected_move_interaction_availability())
	)
	_set_availability(
		rotate_value_label,
		_availability_text(_grab_drop_controller.get_selected_rotate_interaction_availability())
	)
	_set_availability(
		grab_value_label,
		_availability_text(_grab_drop_controller.get_selected_grab_drop_interaction_availability())
	)


func _availability_text(status: StringName) -> String:
	match status:
		AvailabilityScript.AVAILABLE:
			return "可用"
		AvailabilityScript.NO_VEHICLE:
			return "—"
		AvailabilityScript.NO_CAPABILITY, AvailabilityScript.PREPARATION_REJECTED, ManualAvailabilityScript.UI_OPEN:
			return "不可用"
		AvailabilityScript.PAUSED:
			return "暂停"
		AvailabilityScript.PLANNING:
			return "规划中"
		AvailabilityScript.MOVING:
			return "移动中"
		AvailabilityScript.BLOCKED:
			return "受阻"
		ManualAvailabilityScript.TARGETING:
			return "选点中"
		AvailabilityScript.ROTATING:
			return "旋转中"
		AvailabilityScript.BUSY:
			return "忙碌"
		AvailabilityScript.NO_TARGET:
			return "无目标"
		_:
			push_warning("Unknown vehicle command availability: %s" % String(status))
			return "未知"


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


func _on_observable_changed(_a = null, _b = null, _c = null) -> void:
	_refresh()


func _on_selection_changed(_vehicle_id: StringName, _has_selection: bool) -> void:
	_refresh()


func _on_hover_changed(_cell: Vector2i, _has_hover: bool) -> void:
	_refresh_pointer_label()


func _on_target_mode_changed(_active: bool) -> void:
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

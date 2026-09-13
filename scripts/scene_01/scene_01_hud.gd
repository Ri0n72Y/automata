class_name Scene01Hud
extends CanvasLayer

const ObservableStateScript := preload("res://scripts/scene_01/scene_01_observable_state.gd")
const MissionControllerScript := preload("res://scripts/scene_01/scene_01_mission_controller.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const VehicleRuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const VehicleDefinitionScript := preload("res://scripts/vehicles/vehicle_definition.gd")
const VehicleSelectionControllerScript := preload("res://scripts/input/vehicle_selection_controller.gd")
const GridSelectionControllerScript := preload("res://scripts/input/grid_selection_controller.gd")
const VehicleMoveControllerScript := preload("res://scripts/input/vehicle_move_controller.gd")
const VehicleGrabDropControllerScript := preload("res://scripts/input/vehicle_grab_drop_controller.gd")
const MissionStateScript := preload("res://scripts/scene_01/scene_01_mission_state.gd")
const GrabDropResultScript := preload("res://scripts/vehicles/grab_drop_result.gd")

@onready var selected_label: Label = %SelectedLabel
@onready var vehicle_state_label: Label = %VehicleStateLabel
@onready var inventory_label: Label = %InventoryLabel
@onready var mission_label: Label = %MissionLabel
@onready var pause_label: Label = %PauseLabel
@onready var commands_label: Label = %CommandsLabel
@onready var feedback_label: Label = %FeedbackLabel
@onready var completion_panel: PanelContainer = %CompletionPanel
@onready var completion_summary_label: Label = %CompletionSummaryLabel

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
	_refresh()
	call_deferred("_refresh")


func _bind_signals() -> void:
	_observable.configured.connect(_refresh)
	_observable.vehicle_state_changed.connect(_on_observable_changed)
	_observable.arm_has_item_changed.connect(_on_observable_changed)
	_observable.tray_count_changed.connect(_on_observable_changed)
	_observable.standard_box_count_changed.connect(_on_observable_changed)
	_observable.mission_state_changed.connect(_on_observable_changed)
	_vehicle_selection.selection_changed.connect(_on_selection_changed)
	_grid_selection.live_target_mode_changed.connect(_on_target_mode_changed)
	_move_controller.move_accepted.connect(_on_move_accepted)
	_move_controller.move_rejected.connect(_on_move_rejected)
	_move_controller.move_stopped.connect(_on_move_stopped)
	_grab_drop_controller.grab_drop_completed.connect(_on_grab_drop_completed)
	_grab_drop_controller.facing_changed.connect(_on_arm_facing_changed)
	_scene_controller.lifecycle_state_changed.connect(_on_lifecycle_changed)
	_scene_controller.lifecycle_reset_completed.connect(_on_reset_completed)


func _refresh() -> void:
	var observable_ready := _observable.is_configured()
	var selected_id := _vehicle_selection.get_selected_vehicle_id()
	var has_selection := selected_id != &""
	selected_label.text = "选中：%s" % _selected_vehicle_name(selected_id)

	var motion_state := -1
	if observable_ready and has_selection:
		motion_state = _observable.get_vehicle_state(selected_id)
	vehicle_state_label.text = "状态：%s" % _motion_state_text(motion_state)

	if observable_ready:
		var target_count := _scene_controller.get_mission_target_count()
		var box_text := str(_observable.get_standard_box_count())
		if target_count > 0:
			box_text = "%d/%d" % [_observable.get_standard_box_count(), target_count]
		inventory_label.text = "机械臂：%s   托盘：%d   标准箱：%s" % [
			"持有方块" if _observable.get_arm_has_item() else "空",
			_observable.get_tray_count(),
			box_text,
		]
		var mission_state := _observable.get_mission_state()
		mission_label.text = "任务：%s   进度：%s" % [_mission_state_text(mission_state), box_text]
		completion_panel.visible = mission_state == MissionStateScript.State.COMPLETED
		if completion_panel.visible:
			completion_summary_label.text = "标准箱 %s · 任务已完成" % box_text
	else:
		inventory_label.text = "机械臂：—   托盘：—   标准箱：—"
		mission_label.text = "任务：初始化中"
		completion_panel.visible = false

	pause_label.visible = _scene_controller.is_scene_paused()
	commands_label.text = _command_availability_text(motion_state, selected_id)


func _command_availability_text(motion_state: int, selected_id: StringName) -> String:
	if selected_id == &"":
		return "命令：M 移动 未选择车辆   X 停止 未选择车辆   C 抓放 未选择车辆"
	if _scene_controller.is_scene_paused():
		return "命令：M 移动 暂停   X 停止 暂停   C 抓放 暂停"

	var vehicle = _vehicle_manager.get_vehicle_by_id(selected_id)
	var definition = vehicle.definition if vehicle != null else null
	var busy := (
		motion_state == VehicleRuntimeStateScript.MotionState.PLANNING
		or motion_state == VehicleRuntimeStateScript.MotionState.MOVING
	)
	var can_move := (
		definition != null
		and definition.has_capability(VehicleDefinitionScript.CAPABILITY_CAN_MOVE)
	)
	var can_grab := (
		definition != null
		and definition.has_capability(VehicleDefinitionScript.CAPABILITY_CAN_GRAB)
	)

	var move_text := "可用"
	if not can_move:
		move_text = "车辆无移动能力"
	elif busy:
		move_text = "车辆忙碌"
	elif _grid_selection.is_live_target_mode():
		move_text = "选择目标中"

	var stop_text := (
		"可用"
		if motion_state == VehicleRuntimeStateScript.MotionState.MOVING
		else "车辆未移动"
	)

	var grab_text := "无有效交互目标"
	if not can_grab:
		grab_text = "车辆无机械臂"
	elif busy:
		grab_text = "车辆忙碌"
	elif _grid_selection.is_live_target_mode():
		grab_text = "移动选点中"
	elif _grab_drop_controller.is_interaction_preview_valid():
		grab_text = "可用"

	return "命令：M 移动 %s   X 停止 %s   C 抓放 %s" % [
		move_text,
		stop_text,
		grab_text,
	]


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
			return "WAITING"
		VehicleRuntimeStateScript.MotionState.PLANNING:
			return "PLANNING"
		VehicleRuntimeStateScript.MotionState.MOVING:
			return "MOVING"
		VehicleRuntimeStateScript.MotionState.BLOCKED:
			return "BLOCKED"
		_:
			return "—"


func _mission_state_text(state: int) -> String:
	match state:
		MissionStateScript.State.READY:
			return "READY"
		MissionStateScript.State.RUNNING:
			return "RUNNING"
		MissionStateScript.State.PAUSED:
			return "PAUSED"
		MissionStateScript.State.COMPLETED:
			return "COMPLETED"
		_:
			return "—"


func _on_observable_changed(_a = null, _b = null, _c = null) -> void:
	_refresh()


func _on_selection_changed(_vehicle_id: StringName, _has_selection: bool) -> void:
	_grab_drop_controller.refresh_interaction_preview()
	_refresh()


func _on_target_mode_changed(_active: bool) -> void:
	_refresh()


func _on_arm_facing_changed(_vehicle_id: StringName, _facing: int) -> void:
	_refresh()


func _on_lifecycle_changed(_previous_state: int, _current_state: int) -> void:
	_refresh()


func _on_reset_completed() -> void:
	feedback_label.text = "场景已重置"
	_refresh()


func _on_move_accepted(vehicle_id: StringName, _target_anchor: Vector2i) -> void:
	feedback_label.text = "%s：移动命令已接受" % _selected_vehicle_name(vehicle_id)
	_refresh()


func _on_move_rejected(vehicle_id: StringName, _target_anchor: Vector2i, reason: StringName) -> void:
	var prefix := _selected_vehicle_name(vehicle_id) if vehicle_id != &"" else "移动"
	feedback_label.text = "%s：%s" % [prefix, _move_rejection_text(reason)]
	_refresh()


func _on_move_stopped(vehicle_id: StringName) -> void:
	feedback_label.text = "%s：移动已停止" % _selected_vehicle_name(vehicle_id)
	_refresh()


func _on_grab_drop_completed(vehicle_id: StringName, action: int, status: int) -> void:
	var action_name := "抓取" if action == GrabDropResultScript.Action.GRAB else "放置"
	if action == GrabDropResultScript.Action.NONE:
		action_name = "抓放"
	if status == GrabDropResultScript.Status.ACCEPTED:
		feedback_label.text = "%s：%s成功" % [_selected_vehicle_name(vehicle_id), action_name]
	else:
		feedback_label.text = "%s：%s失败 · %s" % [
			_selected_vehicle_name(vehicle_id),
			action_name,
			_grab_drop_status_text(status),
		]
	_refresh()


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

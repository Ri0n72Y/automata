class_name Scene01Hud
extends CanvasLayer

const ObservableStateScript := preload("res://scripts/scene_01/scene_01_observable_state.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const VehicleRuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
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

var _scene_controller: Node
var _observable: ObservableStateScript
var _vehicle_manager: VehicleManagerScript
var _vehicle_selection: Node
var _grid_selection: Node
var _move_controller: Node
var _grab_drop_controller: Node


func _ready() -> void:
	_scene_controller = get_parent()
	_observable = _scene_node("SceneRoot/Scene01ObservableState") as ObservableStateScript
	_vehicle_manager = _scene_node("SceneRoot/RobotRoot/Scene01VehicleManager") as VehicleManagerScript
	_vehicle_selection = _scene_node("SceneRoot/GridRoot/VehicleSelectionController")
	_grid_selection = _scene_node("SceneRoot/GridRoot/GridSelectionController")
	_move_controller = _scene_node("SceneRoot/GridRoot/VehicleMoveController")
	_grab_drop_controller = _scene_node("SceneRoot/GridRoot/VehicleGrabDropController")
	_bind_signals()
	_refresh()


func _bind_signals() -> void:
	if _observable != null:
		_connect_once(_observable, &"configured", _refresh)
		_connect_once(_observable, &"vehicle_state_changed", _on_observable_changed)
		_connect_once(_observable, &"arm_has_item_changed", _on_observable_changed)
		_connect_once(_observable, &"tray_count_changed", _on_observable_changed)
		_connect_once(_observable, &"standard_box_count_changed", _on_observable_changed)
		_connect_once(_observable, &"mission_state_changed", _on_observable_changed)
	if _vehicle_selection != null:
		_connect_once(_vehicle_selection, &"selection_changed", _on_selection_changed)
	if _grid_selection != null:
		_connect_once(_grid_selection, &"live_target_mode_changed", _on_target_mode_changed)
	if _move_controller != null:
		_connect_once(_move_controller, &"move_accepted", _on_move_accepted)
		_connect_once(_move_controller, &"move_rejected", _on_move_rejected)
		_connect_once(_move_controller, &"move_stopped", _on_move_stopped)
	if _grab_drop_controller != null:
		_connect_once(_grab_drop_controller, &"grab_drop_completed", _on_grab_drop_completed)
	if _scene_controller != null:
		_connect_once(_scene_controller, &"lifecycle_state_changed", _on_lifecycle_changed)
		_connect_once(_scene_controller, &"lifecycle_reset_completed", _on_reset_completed)


func _refresh() -> void:
	var observable_ready := _observable != null and _observable.is_configured()
	var selected_id := _selected_vehicle_id()
	var has_selection := selected_id != &""
	selected_label.text = "选中：%s" % _selected_vehicle_name(selected_id)

	var motion_state := -1
	if observable_ready and has_selection:
		motion_state = _observable.get_vehicle_state(selected_id)
	vehicle_state_label.text = "状态：%s" % _motion_state_text(motion_state)

	if observable_ready:
		var target_count := _mission_target_count()
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

	pause_label.visible = _is_paused()
	commands_label.text = _command_availability_text(motion_state, has_selection)


func _command_availability_text(motion_state: int, has_selection: bool) -> String:
	if not has_selection:
		return "命令：M 移动 —   X 停止 —   C 抓放 —"
	var paused := _is_paused()
	var busy := (
		motion_state == VehicleRuntimeStateScript.MotionState.PLANNING
		or motion_state == VehicleRuntimeStateScript.MotionState.MOVING
	)
	var move_available := (
		not paused
		and not busy
		and _grid_selection != null
		and _grid_selection.has_method("is_live_target_available")
		and bool(_grid_selection.call("is_live_target_available"))
	)
	var move_text := "可用" if move_available else "不可用"
	if _grid_selection != null and _grid_selection.has_method("is_live_target_mode"):
		if bool(_grid_selection.call("is_live_target_mode")):
			move_text = "选择目标中"
	var stop_available := not paused and motion_state == VehicleRuntimeStateScript.MotionState.MOVING
	var grab_available := (
		not paused
		and not busy
		and _grab_drop_controller != null
		and _grab_drop_controller.has_method("is_interaction_preview_valid")
		and bool(_grab_drop_controller.call("is_interaction_preview_valid"))
	)
	return "命令：M 移动 %s   X 停止 %s   C 抓放 %s" % [
		move_text,
		"可用" if stop_available else "不可用",
		"可用" if grab_available else "不可用",
	]


func _selected_vehicle_id() -> StringName:
	if _vehicle_selection == null or not _vehicle_selection.has_method("get_selected_vehicle_id"):
		return &""
	return StringName(_vehicle_selection.call("get_selected_vehicle_id"))


func _selected_vehicle_name(vehicle_id: StringName) -> String:
	if vehicle_id == &"":
		return "未选择"
	if _vehicle_manager == null:
		return String(vehicle_id)
	var vehicle = _vehicle_manager.get_vehicle_by_id(vehicle_id)
	if vehicle == null or vehicle.definition == null:
		return String(vehicle_id)
	return vehicle.definition.display_name


func _mission_target_count() -> int:
	if _scene_controller == null or not _scene_controller.has_method("get_mission_target_count"):
		return 0
	return int(_scene_controller.call("get_mission_target_count"))


func _is_paused() -> bool:
	return (
		_scene_controller != null
		and _scene_controller.has_method("is_scene_paused")
		and bool(_scene_controller.call("is_scene_paused"))
	)


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
	_refresh()


func _on_target_mode_changed(_active: bool) -> void:
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


func _connect_once(source: Object, signal_name: StringName, callable: Callable) -> void:
	if source == null or not source.has_signal(signal_name):
		return
	if not source.is_connected(signal_name, callable):
		source.connect(signal_name, callable)


func _scene_node(path: String) -> Node:
	if _scene_controller == null:
		return null
	return _scene_controller.get_node_or_null(NodePath(path))

class_name Scene01OperationsPanel
extends CanvasLayer

const AvailabilityScript := preload("res://scripts/input/vehicle_command_availability.gd")
const ManualAvailabilityScript := preload("res://scripts/input/vehicle_manual_interaction_availability.gd")
const LayoutMetrics := preload("res://scripts/scene_01/scene_01_ui_layout_metrics.gd")

@onready var _panel: PanelContainer = %OperationsPanel
@onready var _vehicle_label: Label = %VehicleLabel
@onready var _move_status: Label = %MoveStatus
@onready var _move_button: Button = %MoveButton
@onready var _rotate_status: Label = %RotateStatus
@onready var _rotate_left_button: Button = %RotateLeftButton
@onready var _rotate_right_button: Button = %RotateRightButton
@onready var _grab_drop_status: Label = %GrabDropStatus
@onready var _grab_drop_button: Button = %GrabDropButton

@onready var _scene_controller: Node = get_parent()
@onready var _vehicle_selection: Node = get_parent().get_node("SceneRoot/GridRoot/VehicleSelectionController")
@onready var _move_controller: Node = get_parent().get_node("SceneRoot/GridRoot/VehicleMoveController")
@onready var _grab_drop_controller: Node = get_parent().get_node("SceneRoot/GridRoot/VehicleGrabDropController")
@onready var _grid_selection: Node = get_parent().get_node("SceneRoot/GridRoot/GridSelectionController")


func _ready() -> void:
	_move_button.pressed.connect(_on_move_pressed)
	_rotate_left_button.pressed.connect(func(): _request_turn(-1))
	_rotate_right_button.pressed.connect(func(): _request_turn(1))
	_grab_drop_button.pressed.connect(_on_grab_drop_pressed)
	get_viewport().size_changed.connect(_apply_layout)
	_apply_layout()
	_refresh_projection()
	set_process(true)


func _process(_delta: float) -> void:
	_refresh_projection()


func _apply_layout() -> void:
	var viewport_width := float(get_viewport().get_visible_rect().size.x)
	var width := LayoutMetrics.program_rail_width(viewport_width)
	_panel.offset_top = LayoutMetrics.CONTENT_TOP
	_panel.offset_right = -LayoutMetrics.EDGE_MARGIN
	_panel.offset_left = _panel.offset_right - width
	_panel.offset_bottom = _panel.offset_top + LayoutMetrics.OPERATIONS_PANEL_HEIGHT


func _refresh_projection() -> void:
	var vehicle: Variant = _vehicle_selection.call("get_selected_vehicle")
	if vehicle == null:
		_vehicle_label.text = "当前车辆 · 未选择"
	else:
		var display_name := String(vehicle.get_vehicle_id())
		if vehicle.definition != null and not String(vehicle.definition.display_name).is_empty():
			display_name = String(vehicle.definition.display_name)
		_vehicle_label.text = "当前车辆 · %s" % display_name

	var move_status := StringName(_move_controller.call("get_selected_move_interaction_availability"))
	var rotate_status := StringName(_grab_drop_controller.call("get_selected_rotate_interaction_availability"))
	var grab_drop_status := StringName(_grab_drop_controller.call("get_selected_grab_drop_interaction_availability"))

	_move_status.text = _status_text(move_status)
	_rotate_status.text = _status_text(rotate_status)
	_grab_drop_status.text = _status_text(grab_drop_status)

	_move_button.disabled = not _is_move_actionable(move_status)
	_move_button.text = "取消目标" if move_status == ManualAvailabilityScript.TARGETING else "选择目标"
	var rotate_disabled := rotate_status != AvailabilityScript.AVAILABLE
	_rotate_left_button.disabled = rotate_disabled
	_rotate_right_button.disabled = rotate_disabled
	_grab_drop_button.disabled = grab_drop_status != AvailabilityScript.AVAILABLE


func _on_move_pressed() -> void:
	var status := StringName(_move_controller.call("get_selected_move_interaction_availability"))
	if not _is_move_actionable(status):
		return
	_grid_selection.call("toggle_live_target_mode")
	_refresh_projection()


func _request_turn(direction: int) -> void:
	var status := StringName(_grab_drop_controller.call("get_selected_rotate_interaction_availability"))
	if status != AvailabilityScript.AVAILABLE:
		return
	_grab_drop_controller.call("rotate_selected_vehicle", direction)
	_refresh_projection()


func _on_grab_drop_pressed() -> void:
	var status := StringName(_grab_drop_controller.call("get_selected_grab_drop_interaction_availability"))
	if status != AvailabilityScript.AVAILABLE:
		return
	_grab_drop_controller.call("request_selected_grab_drop")
	_refresh_projection()


func _is_move_actionable(status: StringName) -> bool:
	return (
		status == AvailabilityScript.AVAILABLE
		or status == AvailabilityScript.BLOCKED
		or status == ManualAvailabilityScript.TARGETING
	)


func _status_text(status: StringName) -> String:
	match status:
		AvailabilityScript.AVAILABLE:
			return "可用"
		AvailabilityScript.NO_VEHICLE:
			return "未选择车辆"
		AvailabilityScript.NO_CAPABILITY:
			return "当前车辆不支持"
		AvailabilityScript.PAUSED:
			return "已暂停"
		AvailabilityScript.PREPARATION_REJECTED:
			return "场景尚未就绪"
		AvailabilityScript.BUSY:
			return "车辆忙碌"
		AvailabilityScript.PLANNING:
			return "路径规划中"
		AvailabilityScript.MOVING:
			return "移动中"
		AvailabilityScript.BLOCKED:
			return "移动受阻 · 可重新选点"
		AvailabilityScript.ROTATING:
			return "旋转中"
		AvailabilityScript.NO_TARGET:
			return "没有可交互目标"
		ManualAvailabilityScript.TARGETING:
			return "选择目标中"
		ManualAvailabilityScript.UI_OPEN:
			return "其他操作界面占用"
		_:
			return "不可用"

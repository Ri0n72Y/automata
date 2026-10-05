class_name Scene01OperationsPanel
extends CanvasLayer

const AvailabilityScript := preload("res://scripts/input/vehicle_command_availability.gd")
const ManualAvailabilityScript := preload("res://scripts/input/vehicle_manual_interaction_availability.gd")
const LayoutMetrics := preload("res://scripts/scene_01/scene_01_ui_layout_metrics.gd")
const ProgramUIScript := preload("res://scripts/scene_01/scene_01_program_ui.gd")
const VehicleSelectionControllerScript := preload("res://scripts/input/vehicle_selection_controller.gd")
const VehicleMoveControllerScript := preload("res://scripts/input/vehicle_move_controller.gd")
const VehicleGrabDropControllerScript := preload("res://scripts/input/vehicle_grab_drop_controller.gd")
const GridSelectionControllerScript := preload("res://scripts/input/grid_selection_controller.gd")

@onready var _panel: PanelContainer = %OperationsPanel
@onready var _content: VBoxContainer = $RootControl/OperationsPanel/Margin/VBox
@onready var _title: Label = %OperationsTitle
@onready var _mode_button: Button = %AuthoringModeButton
@onready var _vehicle_label: Label = %VehicleLabel
@onready var _move_row: Control = %MoveRow
@onready var _move_status: Label = %MoveStatus
@onready var _move_button: Button = %MoveButton
@onready var _rotate_row: Control = %RotateRow
@onready var _rotate_status: Label = %RotateStatus
@onready var _rotate_left_button: Button = %RotateLeftButton
@onready var _rotate_right_button: Button = %RotateRightButton
@onready var _grab_drop_row: Control = %GrabDropRow
@onready var _grab_drop_status: Label = %GrabDropStatus
@onready var _grab_drop_button: Button = %GrabDropButton
@onready var _authoring_divider: HSeparator = %AuthoringDivider
@onready var _program_ui: ProgramUIScript = $RootControl/OperationsPanel/Margin/VBox/ProgramAuthoring as ProgramUIScript

@onready var _vehicle_selection: VehicleSelectionControllerScript = get_parent().get_node("SceneRoot/GridRoot/VehicleSelectionController") as VehicleSelectionControllerScript
@onready var _move_controller: VehicleMoveControllerScript = get_parent().get_node("SceneRoot/GridRoot/VehicleMoveController") as VehicleMoveControllerScript
@onready var _grab_drop_controller: VehicleGrabDropControllerScript = get_parent().get_node("SceneRoot/GridRoot/VehicleGrabDropController") as VehicleGrabDropControllerScript
@onready var _grid_selection: GridSelectionControllerScript = get_parent().get_node("SceneRoot/GridRoot/GridSelectionController") as GridSelectionControllerScript

var _authoring_mode := false
var _authoring_move_targeting := false


func _ready() -> void:
	_mode_button.pressed.connect(func(): set_authoring_mode(not _authoring_mode))
	_move_button.pressed.connect(_on_move_pressed)
	_rotate_left_button.pressed.connect(func(): _request_turn(-1))
	_rotate_right_button.pressed.connect(func(): _request_turn(1))
	_grab_drop_button.pressed.connect(_on_grab_drop_pressed)
	_move_controller.move_target_selected.connect(_on_move_target_selected)
	_grid_selection.live_target_mode_changed.connect(_on_live_target_mode_changed)
	_program_ui.editing_enabled_changed.connect(_on_program_editing_enabled_changed)
	_content.minimum_size_changed.connect(_queue_layout)
	get_viewport().size_changed.connect(_apply_layout)
	set_authoring_mode(false)
	_refresh_projection()
	set_process(true)


func _input(event: InputEvent) -> void:
	if not _authoring_mode:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _panel.get_global_rect().has_point(event.position):
			get_viewport().gui_release_focus()


func _process(_delta: float) -> void:
	_refresh_projection()


func set_authoring_mode(enabled: bool) -> void:
	var entering_authoring := enabled and not _authoring_mode
	if entering_authoring and _grid_selection.is_live_target_mode():
		_grid_selection.deactivate_live_target_mode()
	elif not enabled:
		_cancel_authoring_move_targeting()
	_authoring_mode = enabled
	_program_ui.visible = enabled
	_authoring_divider.visible = enabled
	_title.text = "程序" if enabled else "操作台"
	_mode_button.text = "收起" if enabled else "展开"
	_mode_button.tooltip_text = "返回日常操作" if enabled else "展开程序编辑"
	_refresh_projection()
	_apply_layout()
	if not enabled:
		get_viewport().gui_release_focus()


func is_authoring_mode() -> bool:
	return _authoring_mode


func get_source_text() -> String:
	return _program_ui.get_source_text()


func set_source_text(source: String) -> void:
	_program_ui.set_source_text(source)


func get_program() -> Scene01Program:
	return _program_ui.get_program()


func focus_source_editor() -> void:
	if _authoring_mode:
		_program_ui.focus_source_editor()


func _apply_layout() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var width := LayoutMetrics.program_rail_width(float(viewport_size.x)) if _authoring_mode else LayoutMetrics.PRIMARY_RAIL_WIDTH
	_panel.anchor_bottom = 1.0 if _authoring_mode else 0.0
	_panel.offset_top = LayoutMetrics.CONTENT_TOP
	_panel.offset_right = -LayoutMetrics.EDGE_MARGIN
	_panel.offset_left = _panel.offset_right - width
	_panel.offset_bottom = -LayoutMetrics.CONTENT_BOTTOM_MARGIN if _authoring_mode else _panel.offset_top + ceilf(_panel.get_combined_minimum_size().y)


func _queue_layout() -> void:
	call_deferred("_apply_layout")


func _refresh_projection() -> void:
	if not is_instance_valid(_vehicle_selection):
		return
	var vehicle := _vehicle_selection.get_selected_vehicle()
	if vehicle == null:
		_vehicle_label.text = "当前车辆 · 未选择"
	else:
		var display_name := String(vehicle.get_vehicle_id())
		if vehicle.definition != null and not String(vehicle.definition.display_name).is_empty():
			display_name = String(vehicle.definition.display_name)
		_vehicle_label.text = "当前车辆 · %s" % display_name

	var move_status := _move_controller.get_selected_move_interaction_availability()
	var rotate_status := _grab_drop_controller.get_selected_rotate_interaction_availability()
	var grab_drop_status := _grab_drop_controller.get_selected_grab_drop_interaction_availability()

	var move_visible := move_status != AvailabilityScript.NO_CAPABILITY
	var rotate_visible := rotate_status != AvailabilityScript.NO_CAPABILITY
	var grab_drop_visible := grab_drop_status != AvailabilityScript.NO_CAPABILITY
	var visibility_changed := (
		_move_row.visible != move_visible
		or _rotate_row.visible != rotate_visible
		or _grab_drop_row.visible != grab_drop_visible
	)
	_move_row.visible = move_visible
	_rotate_row.visible = rotate_visible
	_grab_drop_row.visible = grab_drop_visible
	if visibility_changed:
		call_deferred("_apply_layout")

	_move_status.text = _status_text(move_status)
	_rotate_status.text = _status_text(rotate_status)
	_grab_drop_status.text = _status_text(grab_drop_status)

	if _authoring_mode:
		_move_button.text = "取消目标" if _authoring_move_targeting else "插入"
		_grab_drop_button.text = "插入"
		_move_button.disabled = false if _authoring_move_targeting else not _can_author(move_status)
		var rotate_disabled := not _can_author(rotate_status)
		_rotate_left_button.disabled = rotate_disabled
		_rotate_right_button.disabled = rotate_disabled
		_grab_drop_button.disabled = not _can_author(grab_drop_status)
	else:
		_move_button.disabled = not _is_move_actionable(move_status)
		_move_button.text = "取消目标" if move_status == ManualAvailabilityScript.TARGETING else "选择目标"
		var rotate_disabled := rotate_status != AvailabilityScript.AVAILABLE
		_rotate_left_button.disabled = rotate_disabled
		_rotate_right_button.disabled = rotate_disabled
		_grab_drop_button.disabled = grab_drop_status != AvailabilityScript.AVAILABLE


func _on_move_pressed() -> void:
	var status := _move_controller.get_selected_move_interaction_availability()
	if _authoring_mode:
		if _authoring_move_targeting:
			_cancel_authoring_move_targeting()
			return
		if not _can_author(status):
			return
		_begin_authoring_move_targeting()
		return
	if not _is_move_actionable(status):
		return
	_grid_selection.toggle_live_target_mode()
	_refresh_projection()


func _request_turn(direction: int) -> void:
	var status := _grab_drop_controller.get_selected_rotate_interaction_availability()
	if _authoring_mode:
		if not _can_author(status):
			return
		var rotation := "counterclockwise" if direction < 0 else "clockwise"
		_insert_vehicle_statement("rotate] %s" % rotation)
		return
	if status != AvailabilityScript.AVAILABLE:
		return
	_grab_drop_controller.rotate_selected_vehicle(direction)
	_refresh_projection()


func _on_grab_drop_pressed() -> void:
	var status := _grab_drop_controller.get_selected_grab_drop_interaction_availability()
	if _authoring_mode:
		if not _can_author(status):
			return
		_insert_vehicle_statement("grabDrop]")
		return
	if status != AvailabilityScript.AVAILABLE:
		return
	_grab_drop_controller.request_selected_grab_drop()
	_refresh_projection()


func _begin_authoring_move_targeting() -> void:
	_authoring_move_targeting = _move_controller.begin_selected_move_target_selection(
		VehicleMoveControllerScript.TargetCommitMode.SELECT_ONLY
	)
	_refresh_projection()


func _cancel_authoring_move_targeting() -> void:
	if not _authoring_move_targeting:
		return
	_authoring_move_targeting = false
	if _grid_selection.is_live_target_mode():
		_grid_selection.deactivate_live_target_mode()
	_refresh_projection()


func _on_move_target_selected(vehicle_id: StringName, target_anchor: Vector2i) -> void:
	if not _authoring_mode or not _authoring_move_targeting:
		return
	_authoring_move_targeting = false
	_program_ui.insert_statement("[%s:moveTo] %d %d" % [
		String(vehicle_id),
		target_anchor.x,
		target_anchor.y,
	])
	_refresh_projection()


func _on_live_target_mode_changed(active: bool) -> void:
	if not active and _authoring_move_targeting:
		_authoring_move_targeting = false
		_refresh_projection()


func _on_program_editing_enabled_changed(enabled: bool) -> void:
	if not enabled:
		_cancel_authoring_move_targeting()


func _insert_vehicle_statement(command_tail: String) -> void:
	var vehicle := _vehicle_selection.get_selected_vehicle()
	if vehicle == null:
		return
	_program_ui.insert_statement("[%s:%s" % [String(vehicle.get_vehicle_id()), command_tail])


func _can_author(status: StringName) -> bool:
	return status != AvailabilityScript.NO_VEHICLE and status != AvailabilityScript.NO_CAPABILITY


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

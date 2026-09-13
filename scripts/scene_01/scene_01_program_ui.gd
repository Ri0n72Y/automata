class_name Scene01ProgramUI
extends CanvasLayer

const ProgramScript := preload("res://scripts/scene_01/scene_01_program.gd")
const AssemblyCapabilitiesScript := preload("res://scripts/assembly/assembly_capabilities.gd")

const SAVE_PATH := "user://scene_01_program.tres"

@export var scene_controller_path: NodePath = NodePath("..")
@export var runner_path: NodePath = NodePath("../SceneRoot/Scene01ProgramRunner")
@export var vehicle_manager_path: NodePath = NodePath("../SceneRoot/RobotRoot/Scene01VehicleManager")
@export var compile_gate_path: NodePath = NodePath("../SceneRoot/Scene01AssemblyCompileGate")

@onready var _vehicle_option: OptionButton = %VehicleOption
@onready var _target_x: SpinBox = %TargetX
@onready var _target_y: SpinBox = %TargetY
@onready var _repeat_count: SpinBox = %RepeatCount
@onready var _repeat_target_option: OptionButton = %RepeatTargetOption
@onready var _program_list: ItemList = %ProgramList
@onready var _connect_target_option: OptionButton = %ConnectTargetOption
@onready var _add_move_button: Button = %AddMoveButton
@onready var _add_grab_button: Button = %AddGrabButton
@onready var _add_repeat_button: Button = %AddRepeatButton
@onready var _connect_button: Button = %ConnectButton
@onready var _delete_button: Button = %DeleteButton
@onready var _save_button: Button = %SaveButton
@onready var _load_button: Button = %LoadButton
@onready var _run_button: Button = %RunButton
@onready var _status_label: Label = %StatusLabel

var _runner: Scene01ProgramRunner
var _vehicle_manager: Node
var _compile_gate: Node
var _program: Scene01Program


func _ready() -> void:
	_runner = get_node_or_null(runner_path) as Scene01ProgramRunner
	_vehicle_manager = get_node_or_null(vehicle_manager_path)
	_compile_gate = get_node_or_null(compile_gate_path)
	_program = ProgramScript.new()
	_program.reset()
	_bind_ui()
	_bind_runner()
	_populate_vehicles()
	_refresh_program_view()
	_refresh_capability_buttons()


func get_program() -> Scene01Program:
	return _program


func _bind_ui() -> void:
	_vehicle_option.item_selected.connect(_on_vehicle_selected)
	_add_move_button.pressed.connect(_on_add_move)
	_add_grab_button.pressed.connect(_on_add_grab)
	_add_repeat_button.pressed.connect(_on_add_repeat)
	_connect_button.pressed.connect(_on_connect)
	_delete_button.pressed.connect(_on_delete)
	_save_button.pressed.connect(_on_save)
	_load_button.pressed.connect(_on_load)
	_run_button.pressed.connect(_on_run)


func _bind_runner() -> void:
	if _runner == null:
		_status_label.text = "ProgramRunner 未配置"
		_set_editing_enabled(false)
		return
	_runner.execution_started.connect(_on_execution_started)
	_runner.node_started.connect(_on_node_started)
	_runner.execution_completed.connect(_on_execution_completed)
	_runner.execution_failed.connect(_on_execution_failed)
	_runner.execution_reset.connect(_on_execution_reset)


func _populate_vehicles() -> void:
	_vehicle_option.clear()
	if _vehicle_manager == null or not _vehicle_manager.has_method("get_vehicles"):
		return
	for vehicle_node in _vehicle_manager.call("get_vehicles"):
		var vehicle := vehicle_node as VehicleActor
		if vehicle == null or vehicle.definition == null:
			continue
		_vehicle_option.add_item(vehicle.definition.display_name)
		_vehicle_option.set_item_metadata(_vehicle_option.item_count - 1, vehicle.get_vehicle_id())
		if vehicle.get_vehicle_id() == _program.vehicle_id:
			_vehicle_option.select(_vehicle_option.item_count - 1)
	_sync_vehicle_id()


func _sync_vehicle_id() -> void:
	if _vehicle_option.item_count <= 0:
		return
	var index := _vehicle_option.selected
	_program.vehicle_id = StringName(_vehicle_option.get_item_metadata(index))


func _on_vehicle_selected(_index: int) -> void:
	_sync_vehicle_id()
	_refresh_capability_buttons()
	_status_label.text = "程序车辆：%s" % String(_program.vehicle_id)


func _on_add_move() -> void:
	var node_id := _program.append_node(ProgramScript.NodeType.MOVE_TO)
	_program.set_move_target(node_id, Vector2i(int(_target_x.value), int(_target_y.value)))
	_refresh_program_view(node_id)


func _on_add_grab() -> void:
	var node_id := _program.append_node(ProgramScript.NodeType.GRAB_DROP)
	_refresh_program_view(node_id)


func _on_add_repeat() -> void:
	if _repeat_target_option.item_count <= 0:
		_status_label.text = "Repeat 需要一个之前的执行节点"
		return
	var node_id := _program.append_node(ProgramScript.NodeType.REPEAT)
	var target_id := int(_repeat_target_option.get_item_metadata(_repeat_target_option.selected))
	_program.set_repeat(node_id, int(_repeat_count.value), target_id)
	_refresh_program_view(node_id)


func _on_connect() -> void:
	var selected := _program_list.get_selected_items()
	if selected.is_empty() or _connect_target_option.item_count <= 0:
		return
	var from_id := int(_program_list.get_item_metadata(selected[0]))
	var to_id := int(_connect_target_option.get_item_metadata(_connect_target_option.selected))
	if _program.connect_nodes(from_id, to_id):
		_refresh_program_view(from_id)
	else:
		_status_label.text = "连接无效"


func _on_delete() -> void:
	var selected := _program_list.get_selected_items()
	if selected.is_empty():
		return
	var node_id := int(_program_list.get_item_metadata(selected[0]))
	if not _program.remove_node(node_id):
		_status_label.text = "Start 不能删除"
		return
	_refresh_program_view()


func _on_save() -> void:
	var result := ResourceSaver.save(_program, SAVE_PATH)
	_status_label.text = "已保存" if result == OK else "保存失败：%d" % result


func _on_load() -> void:
	if not ResourceLoader.exists(SAVE_PATH):
		_status_label.text = "没有已保存程序"
		return
	var loaded := ResourceLoader.load(SAVE_PATH) as Scene01Program
	if loaded == null:
		_status_label.text = "程序读取失败"
		return
	_program = loaded
	_populate_vehicles()
	_refresh_program_view()
	_refresh_capability_buttons()
	_status_label.text = "已读取"


func _on_run() -> void:
	_sync_vehicle_id()
	if _runner == null or not _runner.start_program(_program):
		if _runner != null and _runner.get_last_error() != &"":
			_status_label.text = "运行前拒绝：%s" % String(_runner.get_last_error())
		return


func _on_execution_started(vehicle_id: StringName) -> void:
	_set_editing_enabled(false)
	_status_label.text = "运行中：%s" % String(vehicle_id)


func _on_node_started(node_id: int, _node_type: int) -> void:
	_status_label.text = "运行节点 #%d" % node_id
	_select_list_node(node_id)


func _on_execution_completed(_vehicle_id: StringName) -> void:
	_set_editing_enabled(true)
	_refresh_capability_buttons()
	_status_label.text = "程序完成"


func _on_execution_failed(node_id: int, reason: StringName) -> void:
	_set_editing_enabled(true)
	_refresh_capability_buttons()
	_status_label.text = "节点 #%d 失败：%s" % [node_id, String(reason)]


func _on_execution_reset() -> void:
	_set_editing_enabled(true)
	_refresh_capability_buttons()
	_status_label.text = "程序已重置"


func _refresh_program_view(select_node_id: int = ProgramScript.NO_NODE_ID) -> void:
	_program_list.clear()
	_repeat_target_option.clear()
	_connect_target_option.clear()
	for node in _program.get_nodes():
		var node_id := int(node.get("id", ProgramScript.NO_NODE_ID))
		var node_type := int(node.get("type", -1))
		var text := _node_text(node)
		_program_list.add_item(text)
		_program_list.set_item_metadata(_program_list.item_count - 1, node_id)
		_connect_target_option.add_item("#%d" % node_id)
		_connect_target_option.set_item_metadata(_connect_target_option.item_count - 1, node_id)
		if node_type != ProgramScript.NodeType.START and node_type != ProgramScript.NodeType.REPEAT:
			_repeat_target_option.add_item("#%d %s" % [node_id, _node_type_name(node_type)])
			_repeat_target_option.set_item_metadata(_repeat_target_option.item_count - 1, node_id)
	if select_node_id != ProgramScript.NO_NODE_ID:
		_select_list_node(select_node_id)


func _node_text(node: Dictionary) -> String:
	var node_id := int(node.get("id", ProgramScript.NO_NODE_ID))
	var node_type := int(node.get("type", -1))
	var next_id := int(node.get("next_id", ProgramScript.NO_NODE_ID))
	var suffix := "END" if next_id == ProgramScript.NO_NODE_ID else "#%d" % next_id
	match node_type:
		ProgramScript.NodeType.MOVE_TO:
			return "#%d MoveTo %s → %s" % [node_id, str(node.get("target_anchor", Vector2i(-1, -1))), suffix]
		ProgramScript.NodeType.GRAB_DROP:
			return "#%d GrabDrop → %s" % [node_id, suffix]
		ProgramScript.NodeType.REPEAT:
			return "#%d Repeat %d × #%d → %s" % [node_id, int(node.get("repeat_count", 1)), int(node.get("repeat_target_id", ProgramScript.NO_NODE_ID)), suffix]
		_:
			return "#%d Start → %s" % [node_id, suffix]


func _node_type_name(node_type: int) -> String:
	match node_type:
		ProgramScript.NodeType.MOVE_TO:
			return "MoveTo"
		ProgramScript.NodeType.GRAB_DROP:
			return "GrabDrop"
		ProgramScript.NodeType.REPEAT:
			return "Repeat"
		_:
			return "Start"


func _select_list_node(node_id: int) -> void:
	for index in range(_program_list.item_count):
		if int(_program_list.get_item_metadata(index)) == node_id:
			_program_list.select(index)
			_program_list.ensure_current_is_visible()
			return


func _refresh_capability_buttons() -> void:
	var can_move := false
	var can_grab_drop := false
	if _compile_gate != null and _program != null and _compile_gate.has_method("prepare_scene_run"):
		if bool(_compile_gate.call("prepare_scene_run")):
			can_move = bool(_compile_gate.call("has_vehicle_capability", _program.vehicle_id, AssemblyCapabilitiesScript.CAN_MOVE))
			can_grab_drop = bool(_compile_gate.call("has_vehicle_capability", _program.vehicle_id, AssemblyCapabilitiesScript.GRAB_DROP))
	_add_move_button.disabled = not can_move
	_add_grab_button.disabled = not can_grab_drop


func _set_editing_enabled(enabled: bool) -> void:
	_vehicle_option.disabled = not enabled
	_target_x.editable = enabled
	_target_y.editable = enabled
	_repeat_count.editable = enabled
	_repeat_target_option.disabled = not enabled
	_connect_target_option.disabled = not enabled
	_add_repeat_button.disabled = not enabled
	_connect_button.disabled = not enabled
	_delete_button.disabled = not enabled
	_save_button.disabled = not enabled
	_load_button.disabled = not enabled
	_run_button.disabled = not enabled
	if not enabled:
		_add_move_button.disabled = true
		_add_grab_button.disabled = true

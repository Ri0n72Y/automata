extends CanvasLayer

## 蓝图编辑 / 部署界面（Scene 01 覆盖层）。
## 设计文档：docs/design/vehicle_assembly_v1.md §7
## 入口：B 键开关；部署仅允许在 READY 状态进行。

const BlueprintScript := preload("res://scripts/assembly/vehicle_blueprint.gd")
const CatalogScript := preload("res://scripts/assembly/vehicle_part_catalog.gd")
const PartScript := preload("res://scripts/assembly/vehicle_part_definition.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")

const TOGGLE_ACTION := &"blueprint_toggle"
const TOGGLE_KEY := KEY_B
const SAVE_DIR := "user://blueprints"
const SAVE_PATH := "user://blueprints/last_blueprint.json"

@export var scene_controller_path: NodePath = NodePath("..")

@onready var panel: PanelContainer = %BlueprintPanel
@onready var chassis_option: OptionButton = %ChassisOption
@onready var wheel_option: OptionButton = %WheelOption
@onready var module_option: OptionButton = %ModuleOption
@onready var name_edit: LineEdit = %NameEdit
@onready var actions_label: Label = %ActionsLabel
@onready var stats_label: Label = %StatsLabel
@onready var status_label: Label = %StatusLabel
@onready var deploy_button: Button = %DeployButton
@onready var close_button: Button = %CloseButton
@onready var save_button: Button = %SaveButton
@onready var load_button: Button = %LoadButton

var controller: Node
var blueprint: Resource
var _placing := false
## Blueprint resolved for the current placement session. Preview and final
## submission must consume this same candidate (a repeated blueprint id gets a
## free-id clone before placement starts, not at click time).
var _deployment_blueprint: Resource
var _ghost: MeshInstance3D
var _ghost_material: StandardMaterial3D
var _chassis_ids: Array[StringName] = []
var _wheel_ids: Array[StringName] = []
var _module_ids: Array[StringName] = []


func _ready() -> void:
	controller = get_node_or_null(scene_controller_path)
	_ensure_toggle_action()
	_populate_options()
	blueprint = CatalogScript.default_blueprints()[0]
	_create_ghost()
	_sync_options_from_blueprint()
	_refresh()
	close_button.pressed.connect(_close)
	save_button.pressed.connect(_save_blueprint)
	load_button.pressed.connect(_load_blueprint)
	deploy_button.pressed.connect(_begin_deployment)
	chassis_option.item_selected.connect(_on_part_selected)
	wheel_option.item_selected.connect(_on_part_selected)
	module_option.item_selected.connect(_on_part_selected)
	name_edit.text_changed.connect(_on_name_changed)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(TOGGLE_ACTION):
		if visible:
			_close()
		else:
			_open()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not _placing:
		return
	if event is InputEventMouseMotion:
		_update_ghost(event.position)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_point_on_panel(event.position):
			return
		_place_from_screen(event.position)
		get_viewport().set_input_as_handled()


func _open() -> void:
	# Editing and placement are mutually exclusive: reopening the editor must
	# discard any in-flight placement candidate, otherwise a later world click
	# could deploy the previously cached combination.
	_cancel_deployment()
	visible = true
	_refresh()


func _close() -> void:
	visible = false
	_cancel_deployment()


func _on_part_selected(_index: int) -> void:
	# Defensive: part edits invalidate any cached placement candidate.
	_cancel_deployment()
	var chassis_id: StringName = _selected_id(chassis_option, _chassis_ids)
	var wheel_id: StringName = _selected_id(wheel_option, _wheel_ids)
	var module_id: StringName = _selected_id(module_option, _module_ids)
	var candidate := BlueprintScript.new()
	var previous_name := name_edit.text.strip_edges()
	if candidate.configure(
		StringName(_compose_id(chassis_id, module_id)),
		previous_name,
		chassis_id,
		wheel_id,
		module_id
	):
		blueprint = candidate
		status_label.text = "已更新组合"
	else:
		status_label.text = candidate.get_last_error()
	_refresh(previous_name)


func _on_name_changed(new_name: String) -> void:
	if blueprint == null:
		return
	var candidate := BlueprintScript.new()
	if candidate.configure(
		blueprint.blueprint_id,
		new_name,
		blueprint.chassis_id,
		blueprint.wheel_id,
		blueprint.work_module_id
	):
		blueprint = candidate


func _refresh(preserved_name: String = "") -> void:
	if blueprint == null:
		return
	var actions: PackedStringArray = blueprint.get_available_actions()
	actions_label.text = "  ·  ".join(Array(actions)) if not actions.is_empty() else "（无可用动作）"
	stats_label.text = "速度 %.2f    重量 %.1f    成本 %d\n托盘容量 %d    占地 %d×%d" % [
		blueprint.get_base_speed(),
		blueprint.get_total_weight(),
		blueprint.get_total_cost(),
		blueprint.get_tray_capacity(),
		blueprint.get_footprint().x,
		blueprint.get_footprint().y,
	]
	if not preserved_name.is_empty():
		name_edit.text = preserved_name
	elif name_edit.text.strip_edges() == "":
		name_edit.text = blueprint.display_name
	_sync_options_from_blueprint()
	var ready_to_deploy := _is_ready()
	deploy_button.disabled = not ready_to_deploy
	var readiness_text := (
		"READY 状态可部署" if ready_to_deploy else "运行中不可部署（先 Reset）"
	)
	var current_status := status_label.text
	if (
		current_status == ""
		or current_status.begins_with("READY")
		or current_status.begins_with("运行中不可部署")
	):
		status_label.text = readiness_text


func _begin_deployment() -> void:
	if not _is_ready():
		status_label.text = "只能在 READY 状态部署蓝图车。"
		return
	if not blueprint.is_configured():
		status_label.text = blueprint.get_last_error()
		return
	var manager := controller.get("scene_vehicle_manager") as VehicleManagerScript
	if manager == null:
		status_label.text = "车辆管理器不可用。"
		return
	_deployment_blueprint = _blueprint_with_free_id(manager)
	if _deployment_blueprint == null:
		status_label.text = "无法生成唯一车辆 id。"
		return
	_placing = true
	_ghost.visible = false
	status_label.text = "在场地内点击放置：青色=可放置，红色=占用/越界。"
	visible = false


func _place_from_screen(screen_position: Vector2) -> void:
	var cell := _cell_from_screen(screen_position)
	if cell == Vector2i(-1, -1):
		return
	var manager := controller.get("scene_vehicle_manager") as VehicleManagerScript
	if manager == null:
		return
	var deployment_blueprint: Resource = (
		_deployment_blueprint if _deployment_blueprint != null else _blueprint_with_free_id(manager)
	)
	if deployment_blueprint == null:
		status_label.text = "无法生成唯一车辆 id。"
		return
	if not manager.can_deploy_blueprint(deployment_blueprint, cell):
		status_label.text = "该位置不可放置（越界、被占用或与其它车辆重叠）。"
		return
	if controller.call("deploy_blueprint_vehicle", deployment_blueprint, cell, 0):
		blueprint = deployment_blueprint
		status_label.text = "已部署：%s @ (%d, %d)" % [blueprint.display_name, cell.x, cell.y]
		var actor = manager.get_vehicle_by_id(blueprint.blueprint_id)
		if actor != null:
			var selection = controller.get("vehicle_selection_controller")
			if selection != null:
				selection.select_vehicle(actor)
		_cancel_deployment()
		_open()
	else:
		status_label.text = "部署失败：请查看输出日志。"


func _cancel_deployment() -> void:
	_placing = false
	_deployment_blueprint = null
	if _ghost != null:
		_ghost.visible = false


func _candidate_blueprint() -> Resource:
	if _deployment_blueprint != null:
		return _deployment_blueprint
	return blueprint


func _update_ghost(screen_position: Vector2) -> void:
	var candidate := _candidate_blueprint()
	if candidate == null:
		return
	var cell := _cell_from_screen(screen_position)
	if cell == Vector2i(-1, -1):
		_ghost.visible = false
		return
	var manager := controller.get("scene_vehicle_manager") as VehicleManagerScript
	var valid: bool = manager != null and manager.can_deploy_blueprint(candidate, cell)
	var footprint: Vector2i = candidate.get_footprint()
	var ghost_mesh := _ghost.mesh as BoxMesh
	ghost_mesh.size = Vector3(
		float(footprint.x) * 0.94,
		0.03,
		float(footprint.y) * 0.94
	)
	_ghost.global_position = controller.call(
		"grid_footprint_center_to_world", cell, footprint
	) + Vector3(0, 0.04, 0)
	_ghost_material.albedo_color = (
		Color(0.247, 0.776, 0.808, 0.45)
		if valid
		else Color(0.886, 0.231, 0.196, 0.45)
	)
	_ghost.visible = true


func _cell_from_screen(screen_position: Vector2) -> Vector2i:
	var camera := get_viewport().get_camera_3d()
	var candidate := _candidate_blueprint()
	if camera == null or controller == null or candidate == null:
		return Vector2i(-1, -1)
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var hit = Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)
	if hit == null:
		return Vector2i(-1, -1)
	return controller.call(
		"world_to_nearest_grid_anchor", hit, candidate.get_footprint()
	)


func _is_point_on_panel(point: Vector2) -> bool:
	return panel != null and panel.visible and panel.get_global_rect().has_point(point)


func _is_ready() -> bool:
	if controller == null:
		return false
	if not bool(controller.call("is_scene_initialized")):
		return false
	return not bool(controller.call("is_gameplay_running")) and not bool(
		controller.call("is_scene_paused")
	)


func _save_blueprint() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		status_label.text = "保存失败：无法写入 user://blueprints。"
		return
	file.store_string(JSON.stringify(blueprint.to_dictionary(), "\t"))
	file.close()
	status_label.text = "蓝图已保存：last_blueprint.json"


func _load_blueprint() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		status_label.text = "没有已保存的蓝图。"
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not parsed is Dictionary:
		status_label.text = "蓝图文件损坏。"
		return
	var loaded = BlueprintScript.from_dictionary(parsed)
	if loaded == null:
		status_label.text = "蓝图无法加载：未知部件或非法 id。"
		return
	blueprint = loaded
	name_edit.text = blueprint.display_name
	_sync_options_from_blueprint()
	status_label.text = "蓝图已读取。"
	_refresh()


func _populate_options() -> void:
	_chassis_ids = _fill_option(chassis_option, CatalogScript.chassis_definitions())
	_wheel_ids = _fill_option(wheel_option, CatalogScript.wheel_definitions())
	_module_ids = _fill_option(module_option, CatalogScript.work_module_definitions())


func _fill_option(option: OptionButton, definitions: Dictionary) -> Array[StringName]:
	option.clear()
	var ids: Array[StringName] = []
	for part_id in definitions:
		var part = definitions[part_id]
		ids.append(part_id)
		option.add_item("%s  (%d)" % [part.display_name, part.cost])
	return ids


func _sync_options_from_blueprint() -> void:
	_select_in_option(chassis_option, _chassis_ids, blueprint.chassis_id)
	_select_in_option(wheel_option, _wheel_ids, blueprint.wheel_id)
	_select_in_option(module_option, _module_ids, blueprint.work_module_id)


func _select_in_option(option: OptionButton, ids: Array[StringName], part_id: StringName) -> void:
	var index := ids.find(part_id)
	if index >= 0 and option.selected != index:
		option.select(index)


func _selected_id(option: OptionButton, ids: Array[StringName]) -> StringName:
	var index := option.selected
	return ids[index] if index >= 0 and index < ids.size() else &""


func _compose_id(chassis_id: StringName, module_id: StringName) -> String:
	return "bp_%s_%s" % [String(chassis_id), String(module_id)]


func _blueprint_with_free_id(manager: VehicleManagerScript) -> Resource:
	if manager.get_vehicle_by_id(blueprint.blueprint_id) == null:
		return blueprint
	var suffix := 2
	while suffix < 100:
		var candidate_id := StringName("%s_%d" % [String(blueprint.blueprint_id), suffix])
		if manager.get_vehicle_by_id(candidate_id) == null:
			var clone := BlueprintScript.new()
			if clone.configure(
				candidate_id,
				blueprint.display_name,
				blueprint.chassis_id,
				blueprint.wheel_id,
				blueprint.work_module_id
			):
				return clone
			return null
		suffix += 1
	return null


func _create_ghost() -> void:
	_ghost = MeshInstance3D.new()
	_ghost.name = "BlueprintDeployGhost"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.94, 0.03, 0.94)
	_ghost.mesh = mesh
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_material.no_depth_test = true
	_ghost_material.albedo_color = Color(0.247, 0.776, 0.808, 0.45)
	_ghost.material_override = _ghost_material
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.visible = false
	var scene_root := controller.get_node_or_null("SceneRoot") if controller != null else null
	if scene_root != null:
		scene_root.add_child(_ghost)
	else:
		add_child(_ghost)


func _ensure_toggle_action() -> void:
	if InputMap.has_action(TOGGLE_ACTION):
		return
	InputMap.add_action(TOGGLE_ACTION)
	var key_event := InputEventKey.new()
	key_event.physical_keycode = TOGGLE_KEY
	InputMap.action_add_event(TOGGLE_ACTION, key_event)

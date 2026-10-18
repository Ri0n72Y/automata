extends CanvasLayer

## 独立装配工作台（Besiege 式）：中央 3D 模型 + 底部配件库 + 右侧属性检查器。
## 数据真值仍是 VehicleBlueprint；本界面只做投影与编辑，部署时交给现有
## deploy_blueprint_vehicle / Assembly 编译链路。

const BlueprintScript := preload("res://scripts/assembly/vehicle_blueprint.gd")
const CatalogScript := preload("res://scripts/assembly/vehicle_part_catalog.gd")
const PartScript := preload("res://scripts/assembly/vehicle_part_definition.gd")
const VisualScript := preload("res://scripts/assembly/vehicle_part_visual.gd")
const CardScript := preload("res://scripts/ui/blueprint_part_card.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const SAVE_PATH := "user://blueprints/last_blueprint.json"

const CHASSIS_ORDER := [&"differential", &"skid_steer", &"omni"]
const WHEEL_ORDER := [&"standard", &"fast", &"heavy"]
const MODULE_ORDER := [&"gripper_arm", &"cargo_tray"]
const SLOT_NAMES := ["底盘", "轮组", "工作件"]

@export var scene_controller_path: NodePath = NodePath("..")

@onready var editor_panel: PanelContainer = %EditorPanel
@onready var name_edit: LineEdit = %NameEdit
@onready var save_button: Button = %SaveButton
@onready var load_button: Button = %LoadButton
@onready var deploy_button: Button = %DeployButton
@onready var close_button: Button = %CloseButton
@onready var preview_container: SubViewportContainer = %PreviewContainer
@onready var preview_viewport: SubViewport = %PreviewViewport
@onready var preview_camera: Camera3D = %PreviewCamera
@onready var preview_model_root: Node3D = %PreviewModelRoot
@onready var slot_badge: Label = %SlotBadge
@onready var part_shelf: HBoxContainer = %PartShelf
@onready var shelf_slot_label: Label = %ShelfSlotLabel
@onready var slot_value: Label = %SlotValue
@onready var part_name: Label = %PartName
@onready var part_description: Label = %PartDescription
@onready var actions_label: Label = %ActionsLabel
@onready var stats_label: Label = %StatsLabel
@onready var levels_label: Label = %LevelsLabel
@onready var assembly_label: Label = %AssemblyLabel
@onready var status_label: Label = %StatusLabel

var controller: Node
var blueprint: Resource
var _selected_slot: int = PartScript.Slot.CHASSIS
var _preview_root: Node3D
var _cards: Array[Node] = []
var _orbit_yaw := 0.72
var _orbit_pitch := 0.42
var _orbit_distance := 2.9
var _dragging := false
var _drag_distance := 0.0
var _syncing_name := false
var _selection_cage: Node3D
var _level_input_disabled := false


func _ready() -> void:
	add_to_group(&"blueprint_ui")
	controller = get_node_or_null(scene_controller_path)
	visible = false
	save_button.pressed.connect(_save_blueprint)
	load_button.pressed.connect(_load_blueprint)
	deploy_button.pressed.connect(_begin_deployment)
	close_button.pressed.connect(_close)
	name_edit.text_changed.connect(_on_name_changed)
	preview_container.gui_input.connect(_on_preview_input)
	preview_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_ensure_default_blueprint()
	_build_preview_stage()
	_refresh_editor()
	set_process(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("blueprint_toggle") and not _is_text_input_focused():
		if visible:
			_close()
		else:
			_open()
		get_viewport().set_input_as_handled()
	elif (
		visible
		and not _is_text_input_focused()
		and event is InputEventKey
		and event.pressed
		and event.keycode == KEY_ESCAPE
	):
		_close()
		get_viewport().set_input_as_handled()


func _open() -> void:
	_ensure_default_blueprint()
	_set_level_input_enabled(false)
	visible = true
	set_process(true)
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_rebuild_preview()
	_refresh_editor()


func _close() -> void:
	visible = false
	set_process(false)
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	get_viewport().gui_release_focus()
	_set_level_input_enabled(true)


func _set_level_input_enabled(enabled: bool) -> void:
	if _level_input_disabled == not enabled:
		return
	_level_input_disabled = not enabled
	if controller == null:
		return
	var nodes: Array = [
		controller.get("vehicle_move_controller"),
		controller.get("vehicle_selection_controller"),
		controller.get("grid_selection_controller"),
		controller.get("vehicle_grab_drop_controller"),
		controller.get("scene_camera_rig"),
	]
	var level_switcher := get_parent().get_node_or_null("LevelSwitcher") if get_parent() != null else null
	nodes.append(level_switcher)
	for node in nodes:
		if node is Node:
			node.set_process_input(enabled)
			node.set_process_unhandled_input(enabled)
	var move_controller = controller.get("vehicle_move_controller")
	if move_controller != null and move_controller.has_method("set_vehicle_ui_open"):
		move_controller.call("set_vehicle_ui_open", not enabled)


func _process(_delta: float) -> void:
	pass


# ------------------------------------------------------------------ editing

func _ensure_default_blueprint() -> void:
	if blueprint != null and blueprint.is_configured():
		return
	var candidate := BlueprintScript.new()
	if candidate.configure(
		&"bp_custom",
		"侦察车",
		&"differential",
		&"standard",
		&""
	):
		blueprint = candidate


func _selected_part_id() -> StringName:
	if blueprint == null:
		return &""
	match _selected_slot:
		PartScript.Slot.CHASSIS:
			return blueprint.chassis_id
		PartScript.Slot.WHEEL:
			return blueprint.wheel_id
		_:
			return blueprint.work_module_id


func _apply_part(slot: int, part_id: StringName) -> void:
	if blueprint == null:
		return
	var candidate := BlueprintScript.new()
	var ok := candidate.configure(
		blueprint.blueprint_id,
		blueprint.display_name,
		part_id if slot == PartScript.Slot.CHASSIS else blueprint.chassis_id,
		part_id if slot == PartScript.Slot.WHEEL else blueprint.wheel_id,
		part_id if slot == PartScript.Slot.WORK_MODULE else blueprint.work_module_id
	)
	if not ok:
		status_label.text = candidate.get_last_error()
		return
	blueprint = candidate
	_rebuild_preview()
	_refresh_editor()
	status_label.text = "已安装：%s" % _part_display_name(slot, part_id)


func _part_display_name(slot: int, part_id: StringName) -> String:
	if slot == PartScript.Slot.WORK_MODULE and part_id == &"":
		return "空置工作位"
	var part = CatalogScript.find_part(slot, part_id)
	return part.display_name if part != null else String(part_id)


func _on_part_card_pressed(slot: int, part_id: StringName) -> void:
	_selected_slot = slot
	_apply_part(slot, part_id)


func _select_slot(slot: int) -> void:
	_selected_slot = slot
	_update_selection_cage()
	_refresh_editor()


func _update_selection_cage() -> void:
	if _selection_cage != null and is_instance_valid(_selection_cage):
		_selection_cage.queue_free()
	_selection_cage = null
	if _preview_root == null or _selected_slot == PartScript.Slot.WORK_MODULE:
		return
	var slot_node := VisualScript.slot_node(_preview_root, _selected_slot)
	var bounds := VisualScript.slot_aabb(slot_node)
	if bounds.size == Vector3.ZERO:
		return
	_selection_cage = VisualScript.make_selection_box(bounds)
	_preview_root.add_child(_selection_cage)


func _on_name_changed(new_name: String) -> void:
	if _syncing_name or blueprint == null:
		return
	var candidate := BlueprintScript.new()
	var ok := candidate.configure(
		blueprint.blueprint_id,
		new_name,
		blueprint.chassis_id,
		blueprint.wheel_id,
		blueprint.work_module_id
	)
	if ok:
		blueprint = candidate
		_refresh_properties()
	else:
		status_label.text = candidate.get_last_error()


# ------------------------------------------------------------------ preview

func _rebuild_preview() -> void:
	if preview_model_root == null or blueprint == null:
		return
	for child in preview_model_root.get_children():
		child.free()
	_preview_root = VisualScript.build_vehicle(
		blueprint.chassis_id,
		blueprint.wheel_id,
		blueprint.work_module_id
	)
	preview_model_root.add_child(_preview_root)
	_update_selection_cage()
	_update_camera()


func _update_camera() -> void:
	if preview_camera == null:
		return
	var target := Vector3(0.0, 0.72, 0.0)
	var offset := Vector3(
		sin(_orbit_yaw) * cos(_orbit_pitch) * _orbit_distance,
		sin(_orbit_pitch) * _orbit_distance,
		cos(_orbit_yaw) * cos(_orbit_pitch) * _orbit_distance
	)
	preview_camera.position = target + offset
	preview_camera.look_at(target, Vector3.UP)


func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_dragging = true
				_drag_distance = 0.0
			else:
				if _dragging and _drag_distance < 6.0:
					_select_slot_at(button.position)
				_dragging = false
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_distance = clampf(_orbit_distance - 0.2, 2.0, 4.6)
			_update_camera()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_distance = clampf(_orbit_distance + 0.2, 2.0, 4.6)
			_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		_drag_distance += motion.relative.length()
		_orbit_yaw -= motion.relative.x * 0.01
		_orbit_pitch = clampf(_orbit_pitch + motion.relative.y * 0.01, 0.12, 1.15)
		_update_camera()


func _select_slot_at(viewport_position: Vector2) -> void:
	if _preview_root == null or preview_camera == null:
		return
	var origin := preview_camera.project_ray_origin(viewport_position)
	var direction := preview_camera.project_ray_normal(viewport_position)
	var model_space := preview_model_root.global_transform.affine_inverse()
	var local_origin := model_space * origin
	var local_direction := (model_space.basis * direction).normalized()
	var best_slot := -1
	var best_distance := INF
	for slot in [PartScript.Slot.CHASSIS, PartScript.Slot.WHEEL, PartScript.Slot.WORK_MODULE]:
		var slot_node := VisualScript.slot_node(_preview_root, slot)
		var bounds := VisualScript.slot_aabb(slot_node)
		if bounds.size == Vector3.ZERO:
			continue
		var hit = bounds.intersects_ray(local_origin, local_direction)
		if hit == null:
			continue
		var distance: float = (hit - local_origin).length()
		if distance < best_distance:
			best_distance = distance
			best_slot = slot
	if best_slot >= 0:
		_select_slot(best_slot)


# ---------------------------------------------------------------- refresh UI

func _refresh_editor() -> void:
	if blueprint == null:
		return
	_refresh_header()
	_refresh_shelf()
	_refresh_properties()
	var slot_name: String = SLOT_NAMES[_selected_slot]
	slot_badge.text = "选中安装位：%s  ·  点击模型切换" % slot_name
	shelf_slot_label.text = "%s · %s" % [slot_name, _part_display_name(_selected_slot, _selected_part_id())]


func _refresh_header() -> void:
	_syncing_name = true
	name_edit.text = blueprint.display_name
	_syncing_name = false
	deploy_button.disabled = not _is_ready()


func _refresh_shelf() -> void:
	for card in _cards:
		if is_instance_valid(card):
			card.queue_free()
	_cards.clear()
	var entries: Array = []
	match _selected_slot:
		PartScript.Slot.CHASSIS:
			for part_id in CHASSIS_ORDER:
				entries.append([part_id, ""])
		PartScript.Slot.WHEEL:
			for part_id in WHEEL_ORDER:
				entries.append([part_id, ""])
		_:
			entries.append([&"", "预留空槽"])
			for part_id in MODULE_ORDER:
				entries.append([part_id, ""])
	for entry in entries:
		var part_id: StringName = entry[0]
		var display := _part_display_name(_selected_slot, part_id)
		var subtitle := _part_card_subtitle(_selected_slot, part_id)
		var cost := 0
		var part = CatalogScript.find_part(_selected_slot, part_id)
		if part != null:
			cost = part.cost
		var card = CardScript.new()
		card.configure(_selected_slot, part_id, display, subtitle, cost)
		card.set_selected(part_id == _selected_part_id())
		card.pressed.connect(_on_part_card_pressed.bind(_selected_slot, part_id))
		part_shelf.add_child(card)
		_cards.append(card)


func _part_card_subtitle(slot: int, part_id: StringName) -> String:
	if part_id == &"":
		return "预留空槽"
	var part = CatalogScript.find_part(slot, part_id)
	if part == null:
		return ""
	if slot == PartScript.Slot.CHASSIS:
		return part.suitable_levels[0] if not part.suitable_levels.is_empty() else "通用底盘"
	if slot == PartScript.Slot.WHEEL:
		return "速度 ×%.2f" % part.speed_multiplier
	var actions := CatalogScript.actions_for_capabilities(part.capability_tags)
	return " · ".join(actions) if not actions.is_empty() else "工作件"


func _refresh_properties() -> void:
	if blueprint == null:
		return
	var slot := _selected_slot
	var part_id := _selected_part_id()
	slot_value.text = "%s · SLOT" % SLOT_NAMES[slot]
	part_name.text = _part_display_name(slot, part_id)
	if slot == PartScript.Slot.WORK_MODULE and part_id == &"":
		part_description.text = "预留安装位。点击底部任一工作件即可安装；空置时车辆仅保留底盘与轮组能力。"
		actions_label.text = "MoveTo · Rotate"
		stats_label.text = "无工作件属性\n成本 0"
		levels_label.text = "任意关卡"
	else:
		var part = CatalogScript.find_part(slot, part_id)
		if part != null:
			part_description.text = part.description
			stats_label.text = _part_stats_text(part)
			levels_label.text = "适用：" + ("、".join(part.suitable_levels) if not part.suitable_levels.is_empty() else "通用")
		actions_label.text = " · ".join(blueprint.get_available_actions())
	var summary: Dictionary = blueprint.get_summary()
	assembly_label.text = "整机 %s\n%s\n速度 %.2f · %.1f kg · 成本 %d\n占地 %d×%d · 托盘 %d" % [
		summary.get("display_name", ""),
		" · ".join(summary.get("actions", PackedStringArray())),
		summary.get("base_speed", 0.0),
		summary.get("total_weight", 0.0),
		summary.get("total_cost", 0),
		summary.get("footprint", Vector2i.ONE).x,
		summary.get("footprint", Vector2i.ONE).y,
		summary.get("tray_capacity", 0),
	]
	var slot_name: String = SLOT_NAMES[_selected_slot]
	slot_badge.text = "选中安装位：%s  ·  点击模型切换" % slot_name
	shelf_slot_label.text = "%s · %s" % [slot_name, _part_display_name(slot, part_id)]
	deploy_button.disabled = not _is_ready()


func _part_stats_text(part) -> String:
	if part.slot == PartScript.Slot.CHASSIS:
		return "速度 %.2f   载重 %.0f kg   成本 %d" % [part.base_speed, part.max_payload, part.cost]
	if part.slot == PartScript.Slot.WHEEL:
		return "速度倍率 %.2f   重量 %.1f kg   成本 %d" % [part.speed_multiplier, part.weight, part.cost]
	return "重量 %.1f kg   成本 %d\n托盘容量 %d" % [part.weight, part.cost, part.tray_capacity]


# ------------------------------------------------------------------- deploy

func _is_ready() -> bool:
	if controller == null:
		return false
	if not bool(controller.call("is_scene_initialized")):
		return false
	if bool(controller.call("is_gameplay_running")) or bool(controller.call("is_scene_paused")):
		return false
	return true


func _build_preview_stage() -> void:
	# Dark studio floor + faint grid so the preview reads as a lab workbench.
	var floor := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(9.0, 0.04, 9.0)
	floor.mesh = floor_mesh
	floor.position = Vector3(0, -0.03, 0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.086, 0.137, 0.169, 1)
	floor_material.roughness = 0.9
	floor.material_override = floor_material
	preview_viewport.add_child(floor)
	var line_material := StandardMaterial3D.new()
	line_material.albedo_color = Color(0.145, 0.239, 0.278, 1)
	line_material.roughness = 0.8
	var z_line_mesh := BoxMesh.new()
	z_line_mesh.size = Vector3(9.0, 0.012, 0.018)
	var z_lines := MultiMesh.new()
	z_lines.transform_format = MultiMesh.TRANSFORM_3D
	z_lines.mesh = z_line_mesh
	z_lines.instance_count = 13
	var x_line_mesh := BoxMesh.new()
	x_line_mesh.size = Vector3(0.018, 0.012, 9.0)
	var x_lines := MultiMesh.new()
	x_lines.transform_format = MultiMesh.TRANSFORM_3D
	x_lines.mesh = x_line_mesh
	x_lines.instance_count = 13
	for index in range(13):
		var offset := float(index - 6) * 0.5
		z_lines.set_instance_transform(index, Transform3D(Basis.IDENTITY, Vector3(0, -0.005, offset)))
		x_lines.set_instance_transform(index, Transform3D(Basis.IDENTITY, Vector3(offset, -0.005, 0)))
	for lines in [z_lines, x_lines]:
		var line_instance := MultiMeshInstance3D.new()
		line_instance.multimesh = lines
		line_instance.material_override = line_material
		preview_viewport.add_child(line_instance)


func _deployment_point() -> Node:
	var point := get_tree().get_first_node_in_group(&"level_deployment_point")
	if point == null and get_parent() != null:
		point = get_parent().get_node_or_null("LevelDeploymentPoint")
	return point


func _begin_deployment() -> bool:
	if not _is_ready():
		status_label.text = "只能在 READY 状态部署。先 Reset 场景。"
		return false
	if blueprint == null or not blueprint.is_configured():
		status_label.text = blueprint.get_last_error() if blueprint != null else "蓝图无效"
		return false
	var manager := controller.get("scene_vehicle_manager") as VehicleManagerScript
	if manager == null:
		status_label.text = "车辆管理器不可用。"
		return false
	var point := _deployment_point()
	if point == null:
		status_label.text = "本关没有配置部署点（LevelDeploymentPoint）。"
		return false
	if not point.has_method("get_deploy_cell") or not point.has_method("get_facing"):
		status_label.text = "部署点节点缺少 get_deploy_cell/get_facing。"
		return false
	var cell: Vector2i = point.call("get_deploy_cell")
	var facing: int = int(point.call("get_facing"))
	var candidate := _blueprint_with_free_id(manager)
	if candidate == null:
		status_label.text = "无法生成唯一车辆 id。"
		return false
	if not bool(manager.can_deploy_blueprint(candidate, cell)):
		status_label.text = "部署点 %s 被占用或不可放置，无法部署。" % str(cell)
		return false
	if not bool(controller.call("deploy_blueprint_vehicle", candidate, cell, facing)):
		status_label.text = "部署失败：请查看输出日志。"
		return false
	_close()
	var actor = manager.get_vehicle_by_id(candidate.blueprint_id)
	if actor != null:
		var selection = controller.get("vehicle_selection_controller")
		if selection != null:
			selection.select_vehicle(actor)
	status_label.text = "已部署到部署点 %s" % str(cell)
	return true


func _blueprint_with_free_id(manager: VehicleManagerScript) -> Resource:
	if blueprint == null:
		return null
	var base_id := _base_blueprint_id()
	for index in range(100):
		var candidate_id: StringName = base_id
		if index > 0:
			candidate_id = StringName("%s_%d" % [base_id, index + 1])
		if manager.get_vehicle_by_id(candidate_id) == null:
			var candidate := BlueprintScript.new()
			if not candidate.configure(
				candidate_id,
				blueprint.display_name,
				blueprint.chassis_id,
				blueprint.wheel_id,
				blueprint.work_module_id
			):
				return null
			return candidate
	return null


func _base_blueprint_id() -> String:
	var base := String(blueprint.blueprint_id)
	while true:
		var last := base.get_slice("_", -1)
		if not last.is_valid_int() or base.rfind("_") <= 0:
			break
		base = base.left(base.rfind("_"))
	return base


# ---------------------------------------------------------------- save/load

func _save_blueprint() -> void:
	if blueprint == null:
		return
	DirAccess.make_dir_recursive_absolute(SAVE_PATH.get_base_dir())
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		status_label.text = "保存失败：无法写入 %s" % SAVE_PATH
		return
	file.store_string(JSON.stringify(blueprint.to_dictionary(), "\t"))
	file.close()
	status_label.text = "已保存蓝图：%s" % SAVE_PATH


func _load_blueprint() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		status_label.text = "没有可读取的蓝图。"
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		status_label.text = "蓝图文件格式错误。"
		return
	var loaded := BlueprintScript.from_dictionary(parsed)
	if loaded == null:
		status_label.text = "蓝图内容无效。"
		return
	blueprint = loaded
	_selected_slot = PartScript.Slot.CHASSIS
	_rebuild_preview()
	_refresh_editor()
	status_label.text = "已读取蓝图：%s" % blueprint.display_name


func _is_text_input_focused() -> bool:
	var focus_owner := get_viewport().gui_get_focus_owner()
	return focus_owner is LineEdit or focus_owner is TextEdit

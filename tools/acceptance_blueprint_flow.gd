extends SceneTree

## 蓝图模块流程验收（不是测试套件，不进 CI）。
## 运行：godot --headless --path . --script res://tools/acceptance_blueprint_flow.gd
## 覆盖：设计数据 → 部署到场景 → Assembly 编译 → Program 执行移动 → 托盘/抓取能力差异。

const CatalogScript := preload("res://scripts/assembly/vehicle_part_catalog.gd")
const AssemblyCapabilitiesScript := preload("res://scripts/assembly/assembly_capabilities.gd")
const BlueprintScript = preload("res://scripts/assembly/vehicle_blueprint.gd")
const ProgramSourceScript := preload("res://scripts/scene_01/scene_01_program_source.gd")
const StandardBlockScript := preload("res://scripts/objects/standard_block.gd")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/scene_01/scene_01_basic_packing.tscn") as PackedScene
	_check(packed != null, "Scene 01 加载")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	await process_frame

	var controller = scene
	var manager = scene.get_node("SceneRoot/RobotRoot/Scene01VehicleManager")
	_check(manager.get_vehicle_count() == 2, "初始场景有 2 台模板车")

	# 1. 托盘蓝图：部署 → 托盘运行态 → 编译能力
	var tray_blueprint = CatalogScript.default_blueprints()[1]
	var tray_cell := _find_deploy_cell(manager, tray_blueprint)
	_check(tray_cell != Vector2i(-1, -1), "找到托盘车部署格")
	_check(bool(controller.call("deploy_blueprint_vehicle", tray_blueprint, tray_cell, 0)), "托盘蓝图部署成功")
	var tray_actor = manager.get_vehicle_by_id(tray_blueprint.blueprint_id)
	_check(tray_actor != null, "托盘车可按蓝图 id 寻址")
	_check(tray_actor != null and tray_actor.runtime_state.tray_state != null, "托盘车拥有托盘运行态")
	_check(manager.get_vehicle_count() == 3, "部署后场景有 3 台车")

	var gate = scene.get_node("SceneRoot/Scene01AssemblyCompileGate")
	var caps: Array[StringName] = [AssemblyCapabilitiesScript.CAN_MOVE]
	gate.set_required_capabilities(tray_blueprint.blueprint_id, caps)
	_check(bool(gate.call("prepare_scene_run")), "编译闸门接受监听蓝图车")
	_check(gate.call("get_compile_result", tray_blueprint.blueprint_id) != null, "蓝图车获得汇编编译结果")
	var compile_result = gate.call("get_compile_result", tray_blueprint.blueprint_id)
	if compile_result != null:
		_check(
			compile_result.get_metrics().get_cost() == tray_blueprint.get_total_cost(),
			"蓝图成本进入编译结果（%d）" % compile_result.get_metrics().get_cost()
		)

	# 托盘车必须有静态货物显示结构（槽位 + 计数标签），并受托盘能力控制。
	await process_frame
	await process_frame
	await process_frame
	var tray_visual = tray_actor.get_node("VisualRoot")
	var tray_slots = tray_visual.get_node_or_null("TraySlots")
	_check(tray_slots != null and tray_slots.get_child_count() == 8, "蓝图托盘车包含 8 个货物槽位")
	_check(
		tray_visual.get_tray_count_label_text() == "0/8",
		"蓝图托盘车计数标签 0/8"
	)

	# 托盘载货：货物显示 + 载重速度惩罚（设计中的底盘载货倍率）。
	var tray_state = tray_actor.runtime_state.tray_state
	var test_block = StandardBlockScript.create()
	_check(tray_state.put_item(test_block).is_success(), "托盘车可装载货物")
	await process_frame
	await process_frame
	_check(tray_visual.get_visible_tray_slot_count() == 1, "装载后显示 1 个货物槽位")
	_check(
		tray_actor.runtime_state.get_effective_speed()
		< tray_blueprint.get_base_speed(),
		"托盘载货触发速度惩罚"
	)
	tray_state.take_item()
	await process_frame
	_check(
		is_equal_approx(
			tray_actor.runtime_state.get_effective_speed(),
			tray_blueprint.get_base_speed()
		),
		"卸货后恢复空载速度"
	)

	# 场景部署点：每关一个可调位置，工作台从这里部署。
	var blueprint_ui = scene.get_node_or_null("BlueprintUIRoot")
	_check(blueprint_ui != null, "场景存在装配工作台")
	var deployment_point = scene.get_node_or_null("LevelDeploymentPoint")
	_check(deployment_point != null, "场景配置了可调部署点")
	if deployment_point != null:
		var configured_cell: Vector2i = deployment_point.call("get_deploy_cell")
		_check(
			bool(scene.is_grid_footprint_walkable(configured_cell, Vector2i.ONE)),
			"部署点在可走格上"
		)
	if blueprint_ui != null:
		# 保存/读取往返（读取后编辑器蓝图应与保存时一致）。
		var saved_blueprint = CatalogScript.default_blueprints()[3]
		blueprint_ui.set("blueprint", saved_blueprint)
		blueprint_ui.call("_save_blueprint")
		blueprint_ui.set("blueprint", CatalogScript.default_blueprints()[0])
		blueprint_ui.call("_load_blueprint")
		var loaded_blueprint = blueprint_ui.get("blueprint")
		_check(
			loaded_blueprint != null
			and loaded_blueprint.blueprint_id == saved_blueprint.blueprint_id,
			"蓝图保存/读取往返"
		)
		blueprint_ui.call("_close")

		# 工作台结构：默认差速+标准轮组+空工作件；点击安装位切换底部配件列表。
		var default_blueprint = BlueprintScript.new()
		_check(
			default_blueprint.configure(&"bp_ui_default", "侦察车", &"differential", &"standard", &""),
			"默认蓝图允许空工作位"
		)
		var empty_definition = default_blueprint.to_vehicle_definition()
		_check(
			empty_definition != null
			and empty_definition.has_capability("can_move")
			and empty_definition.has_capability("can_rotate")
			and empty_definition.tray_capacity == 0,
			"空工作位投影为仅移动/旋转能力"
		)
		blueprint_ui.set("blueprint", default_blueprint)
		blueprint_ui.call("_open")
		await process_frame
		_check(blueprint_ui.blueprint.work_module_id == &"", "默认工作件为空位占位")
		_check(blueprint_ui.get("_preview_root") != null, "3D 预览模型已构建")
		blueprint_ui.call("_select_slot", 2)
		await process_frame
		var shelf = blueprint_ui.get_node("RootControl/EditorPanel/EditorMargin/EditorVBox/ShelfPanel/ShelfMargin/ShelfVBox/PartScroll/PartShelf")
		_check(shelf.get_child_count() == 3, "工作件安装位列出空槽 + 2 个工作件")
		var preview_camera = blueprint_ui.get_node("RootControl/EditorPanel/EditorMargin/EditorVBox/Body/PreviewPanel/PreviewStack/PreviewContainer/PreviewViewport/PreviewCamera")
		var preview_model = blueprint_ui.get_node("RootControl/EditorPanel/EditorMargin/EditorVBox/Body/PreviewPanel/PreviewStack/PreviewContainer/PreviewViewport/PreviewModelRoot")
		blueprint_ui.call(
			"_select_slot_at",
			preview_camera.unproject_position(preview_model.to_global(Vector3(0.6, 0.2, 0.35)))
		)
		_check(int(blueprint_ui.get("_selected_slot")) == 1, "点击轮组区域切换到底盘/轮组安装位")
		blueprint_ui.call(
			"_select_slot_at",
			preview_camera.unproject_position(preview_model.to_global(Vector3(0, 0.8, 0)))
		)
		_check(int(blueprint_ui.get("_selected_slot")) == 2, "点击空工作位虚线框切到工作件安装位")
		blueprint_ui.call("_apply_part", 2, &"gripper_arm")
		_check(blueprint_ui.blueprint.work_module_id == &"gripper_arm", "安装机械臂工作件")
		blueprint_ui.call("_apply_part", 2, &"")
		_check(blueprint_ui.blueprint.work_module_id == &"", "可恢复空置工作位")
		blueprint_ui.call("_close")

	# 2. Program 驱动蓝图车移动
	var anchor: Vector2i = tray_actor.runtime_state.anchor_cell
	var target := anchor + Vector2i(2, 0)
	var source := "automata_scene01_program 2\n[%s:moveTo] %d %d\n" % [
		String(tray_blueprint.blueprint_id), target.x, target.y
	]
	var parsed: Dictionary = ProgramSourceScript.new().parse(source)
	_check(bool(parsed.get("diagnostics", []).is_empty()), "Program 解析蓝图车命令")
	var runner = scene.get_node("SceneRoot/Scene01ProgramRunner")
	var completed := {"value": false, "failed": false}
	runner.execution_completed.connect(func(): completed["value"] = true)
	runner.execution_failed.connect(func(_i, _r): completed["failed"] = true)
	_check(bool(runner.call("start_program", parsed.get("program"))), "Program 启动")
	var frames := 0
	while not completed["value"] and not completed["failed"] and frames < 900:
		await process_frame
		frames += 1
	_check(completed["value"], "Program 执行完成（%d 帧）" % frames)
	_check(
		tray_actor.runtime_state.anchor_cell == target,
		"蓝图车到达 Program 目标格 %s" % str(target)
	)

	# 运行中部署必须被拒绝（部署只允许 READY）。
	var running_blueprint = CatalogScript.default_blueprints()[2]
	var running_cell := _find_deploy_cell(manager, running_blueprint)
	var vehicle_count_before: int = manager.get_vehicle_count()
	_check(
		running_cell == Vector2i(-1, -1)
		or not bool(controller.call("deploy_blueprint_vehicle", running_blueprint, running_cell, 0)),
		"运行中拒绝部署蓝图车"
	)
	_check(manager.get_vehicle_count() == vehicle_count_before, "运行中部署不改变车辆数量")

	# 3. 抓取蓝图：能力差异（先 Reset 回 READY，部署只允许 READY）
	scene.call("reset_scene_state")
	await process_frame

	# 托盘车执行 GrabDrop 必须被能力校验拒绝（Program 不得绕过蓝图能力）。
	var bad_source := "automata_scene01_program 2\n[%s:grabDrop]\n" % String(
		tray_blueprint.blueprint_id
	)
	var bad_parsed: Dictionary = ProgramSourceScript.new().parse(bad_source)
	var bad_program = bad_parsed.get("program")
	_check(
		bad_program != null
		and not bool(runner.call("start_program", bad_program))
		and runner.call("get_last_error") == &"program_capability_rejected",
		"托盘车 GrabDrop 被能力校验拒绝"
	)

	var arm_blueprint = CatalogScript.default_blueprints()[0]
	var arm_cell := _find_deploy_cell(manager, arm_blueprint)
	if arm_cell != Vector2i(-1, -1):
		_check(bool(controller.call("deploy_blueprint_vehicle", arm_blueprint, arm_cell, 0)), "抓取蓝图部署成功")
		var arm_actor = manager.get_vehicle_by_id(arm_blueprint.blueprint_id)
		_check(
			arm_actor != null and arm_actor.definition.has_capability("can_grab"),
			"抓取蓝图具备 Grab 能力"
		)
		_check(
			not tray_actor.definition.has_capability("can_grab"),
			"托盘蓝图不具备 Grab 能力"
		)
		_check(
			arm_actor != null
			and (
				arm_actor.get_node_or_null("VisualRoot/TrayCountLabel") == null
				or not arm_actor.get_node("VisualRoot/TrayCountLabel").visible
			),
			"无托盘能力的蓝图车隐藏托盘标签"
		)
		_check(manager.get_vehicle_count() == 4, "第二台蓝图车注册成功")
	else:
		_check(false, "第二台蓝图车部署格")

	# 4. 全向底盘：MoveTo 不改变朝向（holonomic）
	var omni_blueprint = CatalogScript.default_blueprints()[3]
	var omni_cell := _find_deploy_cell(manager, omni_blueprint)
	if omni_cell != Vector2i(-1, -1):
		_check(
			bool(controller.call("deploy_blueprint_vehicle", omni_blueprint, omni_cell, 0)),
			"全向蓝图车部署成功"
		)
		var omni_actor = manager.get_vehicle_by_id(omni_blueprint.blueprint_id)
		if omni_actor != null:
			var omni_target := _find_move_target(scene, manager, omni_actor)
			_check(omni_target != Vector2i(-1, -1), "全向蓝图车有可移动目标")
			if omni_target != Vector2i(-1, -1):
				var facing_before: int = omni_actor.runtime_state.facing
				var omni_source := "automata_scene01_program 2\n[%s:moveTo] %d %d\n" % [
					String(omni_blueprint.blueprint_id), omni_target.x, omni_target.y
				]
				var omni_parsed: Dictionary = ProgramSourceScript.new().parse(omni_source)
				var omni_done := {"value": false, "failed": false}
				runner.execution_completed.connect(func(): omni_done["value"] = true)
				runner.execution_failed.connect(func(_i, _r): omni_done["failed"] = true)
				_check(
					bool(runner.call("start_program", omni_parsed.get("program"))),
					"全向车 Program 启动"
				)
				var omni_frames := 0
				while not omni_done["value"] and not omni_done["failed"] and omni_frames < 900:
					await process_frame
					omni_frames += 1
				_check(omni_done["value"], "全向车 Program 完成")
				_check(
					omni_actor.runtime_state.anchor_cell == omni_target,
					"全向车到达目标格"
				)
				_check(
					omni_actor.runtime_state.facing == facing_before,
					"全向车 MoveTo 不改变朝向（%d）" % facing_before
				)
	else:
		_check(false, "全向蓝图车部署格")

	# 5. HUD 选中蓝图车
	var selection = scene.get_node("SceneRoot/GridRoot/VehicleSelectionController")
	selection.select_vehicle(tray_actor)
	await process_frame
	await process_frame
	var hud = scene.get_node("HUDRoot")
	_check(
		hud.get("selected_label") != null
		and hud.selected_label.text.contains(tray_blueprint.display_name),
		"HUD 显示蓝图车名称"
	)

	# 5. Reset 后蓝图车仍在且回到部署格
	scene.call("reset_scene_state")
	_check(manager.get_vehicle_by_id(tray_blueprint.blueprint_id) != null, "Reset 后蓝图车仍存在")
	_check(
		tray_actor.runtime_state.anchor_cell == tray_cell,
		"Reset 后蓝图车回到部署格"
	)

	# 部署点：工作台直接从每关的可调部署点出场；被占用时拒绝并提示。
	var spawn_blueprint = BlueprintScript.new()
	spawn_blueprint.configure(&"bp_spawn_test", "部署点测试车", &"differential", &"standard", &"")
	var spawn_point = scene.get_node_or_null("LevelDeploymentPoint")
	var spawn_cell := _find_deploy_cell(manager, spawn_blueprint)
	if spawn_point != null and spawn_cell != Vector2i(-1, -1):
		spawn_point.call("set_deploy_cell", spawn_cell)
		var count_before_spawn: int = manager.get_vehicle_count()
		blueprint_ui.set("blueprint", spawn_blueprint)
		var deployed: bool = bool(blueprint_ui.call("_begin_deployment"))
		_check(deployed and manager.get_vehicle_count() == count_before_spawn + 1, "工作台从部署点部署车辆")
		var spawned_actor = manager.get_vehicle_by_id(spawn_blueprint.blueprint_id)
		_check(
			spawned_actor != null and spawned_actor.runtime_state.anchor_cell == spawn_cell,
			"部署车辆落在部署点格"
		)
		var second_deploy: bool = bool(blueprint_ui.call("_begin_deployment"))
		var occupied_status: String = blueprint_ui.get_node("%StatusLabel").text
		_check(
			not second_deploy
			and manager.get_vehicle_count() == count_before_spawn + 1
			and occupied_status.contains("被占用"),
			"部署点被占用时拒绝部署并提示"
		)
		var adjusted_cell := _find_deploy_cell(manager, spawn_blueprint)
		if adjusted_cell != Vector2i(-1, -1):
			spawn_point.call("set_deploy_cell", adjusted_cell)
			_check(
				spawn_point.call("get_deploy_cell") == adjusted_cell,
				"部署点位置可调整"
			)

	scene.queue_free()
	await process_frame
	_finish()


func _find_deploy_cell(manager, blueprint) -> Vector2i:
	for y in range(1, 9):
		for x in range(1, 15):
			var cell := Vector2i(x, y)
			if manager.can_deploy_blueprint(blueprint, cell):
				return cell
	return Vector2i(-1, -1)


func _find_move_target(scene: Node, manager, actor) -> Vector2i:
	var definition = actor.definition
	var anchor: Vector2i = actor.runtime_state.anchor_cell
	for offset in [Vector2i(2, 0), Vector2i(0, 2), Vector2i(-2, 0), Vector2i(0, -2)]:
		var mid: Vector2i = anchor + Vector2i(offset.x / 2, offset.y / 2)
		var target: Vector2i = anchor + offset
		if not bool(scene.call("is_grid_footprint_walkable", mid, definition.footprint)):
			continue
		if not manager.is_footprint_free_of_vehicles(definition, mid):
			continue
		if not bool(scene.call("is_grid_footprint_walkable", target, definition.footprint)):
			continue
		if not manager.is_footprint_free_of_vehicles(definition, target):
			continue
		return target
	return Vector2i(-1, -1)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		_failures += 1
		print("FAIL  ", message)


func _finish() -> void:
	print("FLOW RESULT failures=%d" % _failures)
	quit(0 if _failures == 0 else 1)

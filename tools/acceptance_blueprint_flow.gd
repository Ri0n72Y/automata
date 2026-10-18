extends SceneTree

## 蓝图模块流程验收（不是测试套件，不进 CI）。
## 运行：godot --headless --path . --script res://tools/acceptance_blueprint_flow.gd
## 覆盖：设计数据 → 部署到场景 → Assembly 编译 → Program 执行移动 → 托盘/抓取能力差异。

const CatalogScript := preload("res://scripts/assembly/vehicle_part_catalog.gd")
const AssemblyCapabilitiesScript := preload("res://scripts/assembly/assembly_capabilities.gd")
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

	# 重复部署同一蓝图：预览候选必须与提交候选一致（自动后缀 id）。
	var blueprint_ui = scene.get_node_or_null("BlueprintUIRoot")
	if blueprint_ui != null:
		blueprint_ui.set("blueprint", tray_blueprint)
		blueprint_ui.call("_begin_deployment")
		var candidate = blueprint_ui.get("_deployment_blueprint")
		_check(
			candidate != null and candidate.blueprint_id != tray_blueprint.blueprint_id,
			"重复部署生成唯一候选 id"
		)
		if candidate != null:
			var repeat_cell := _find_deploy_cell(manager, candidate)
			_check(repeat_cell != Vector2i(-1, -1), "候选蓝图有可用部署格")
			if repeat_cell != Vector2i(-1, -1):
				var camera = scene.get_node("SceneRoot/CameraRoot/Scene01CameraRig/SceneCamera")
				var screen_pos: Vector2 = camera.unproject_position(
					scene.grid_cell_to_world(repeat_cell)
				)
				blueprint_ui.call("_update_ghost", screen_pos)
				var ghost_material = blueprint_ui.get("_ghost_material")
				_check(
					ghost_material != null
					and ghost_material.albedo_color.is_equal_approx(
						Color(0.247, 0.776, 0.808, 0.45)
					),
					"预览与提交使用同一候选（ghost 青色）"
				)
		blueprint_ui.call("_cancel_deployment")

		# 重新打开编辑器必须解除放置状态（编辑/放置互斥）。
		blueprint_ui.set("blueprint", tray_blueprint)
		blueprint_ui.call("_begin_deployment")
		_check(bool(blueprint_ui.get("_placing")), "部署模式进入放置状态")
		blueprint_ui.call("_open")
		_check(
			not bool(blueprint_ui.get("_placing"))
			and blueprint_ui.get("_deployment_blueprint") == null,
			"重新打开编辑器会取消放置状态与候选蓝图"
		)
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

	# 3. 抓取蓝图：能力差异（先 Reset 回 READY，部署只允许 READY）
	scene.call("reset_scene_state")
	await process_frame
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
			and not arm_actor.get_node("VisualRoot/TrayCountLabel").visible,
			"无托盘能力的蓝图车隐藏托盘标签"
		)
		_check(manager.get_vehicle_count() == 4, "第二台蓝图车注册成功")
	else:
		_check(false, "第二台蓝图车部署格")

	# 4. HUD 选中蓝图车
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


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		_failures += 1
		print("FAIL  ", message)


func _finish() -> void:
	print("FLOW RESULT failures=%d" % _failures)
	quit(0 if _failures == 0 else 1)

extends SceneTree

## Bean Sorting 流程验收（非测试套件，不进 CI）。
## 运行：godot --headless --path . --script res://tools/acceptance_bean_flow.gd

const BeanBatchScript := preload("res://scripts/beans/bean_batch.gd")
const VehicleRuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const ProgramSourceScript := preload("res://scripts/scene_01/scene_01_program_source.gd")

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/scene_02/scene_02_bean_sorting.tscn") as PackedScene
	_check(packed != null, "Bean Sorting 场景加载")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	await process_frame

	var bean_manager = scene.get_node("SceneRoot/ObjectRoot/Scene01ObjectManager")
	_check(bean_manager.is_initialized(), "豆类对象管理器初始化")
	_check(bean_manager.get_sources().size() == 3, "3 个来源箱")
	_check(bean_manager.get_targets().size() == 5, "5 个目标箱")

	var source_grams := 0
	for source in bean_manager.get_sources():
		source_grams += source.inventory.remaining_grams
	_check(source_grams == 3000, "来源总质量 3000g")
	for index in range(bean_manager.get_targets().size()):
		_check(bean_manager.get_targets()[index].inventory.get_total_grams() == 0, "目标箱初始为空")

	var numbers: Array[int] = []
	for index in range(5):
		numbers.append(scene.get_box_number_for_slot(index))
	numbers.sort()
	_check(numbers == [1, 2, 3, 4, 5], "本局编号为 1-5 的排列")
	_check(
		scene.get_required_number_for_bean(BeanBatchScript.TYPE_SOYBEAN) == 1
		and scene.get_required_number_for_bean(BeanBatchScript.TYPE_MUNG_BEAN) == 2
		and scene.get_required_number_for_bean(BeanBatchScript.TYPE_WHITE_BEAN) == 3,
		"豆种→编号映射固定（1/2/3）"
	)

	var vehicle_manager = scene.get_node("SceneRoot/RobotRoot/Scene01VehicleManager")
	var arm = vehicle_manager.get_vehicle_by_id(&"arm_vehicle")
	var grab_controller = scene.get_node("SceneRoot/GridRoot/VehicleGrabDropController")
	_check(arm != null and arm.definition.has_capability("can_grab"), "机械臂车可抓取")

	scene.call("run_scene")
	await process_frame
	await process_frame
	_check(scene.is_gameplay_running(), "关卡进入运行状态")

	var beans_by_type: Dictionary = {}
	for source in bean_manager.get_sources():
		beans_by_type[source.bean_type] = source

	var target_one = _target_with_number(bean_manager, scene, 1)
	_check(target_one != null, "存在 1 号箱")
	var target_wrong = _target_with_number(bean_manager, scene, 4)
	_check(target_wrong != null, "存在 4 号干扰箱")

	var delivered := 0
	var soybean_source = beans_by_type.get(BeanBatchScript.TYPE_SOYBEAN)
	while soybean_source.inventory.remaining_grams > 0:
		var batch_grams: int = mini(300, soybean_source.inventory.remaining_grams)
		_move_arm_next_to(arm, soybean_source.interaction_cell)
		var grab_result = grab_controller.call("request_vehicle_grab_drop", arm)
		_check(grab_result.is_success(), "抓取黄豆 %d g" % batch_grams)
		var carried = arm.runtime_state.carried_item
		_check(
			carried is BeanBatchScript and (carried as BeanBatch).grams == batch_grams,
			"批次保持克数 %d" % batch_grams
		)
		_move_arm_next_to(arm, target_one.interaction_cell)
		var drop_result = grab_controller.call("request_vehicle_grab_drop", arm)
		_check(drop_result.is_success(), "投入 1 号箱")
		delivered += batch_grams
	_check(target_one.inventory.get_total_grams() == delivered, "1 号箱累计 %d g" % delivered)
	_check(delivered == 1000, "满来源箱形成 300+300+300+100")

	var mung_source = beans_by_type.get(BeanBatchScript.TYPE_MUNG_BEAN)
	_move_arm_next_to(arm, mung_source.interaction_cell)
	_check(grab_controller.call("request_vehicle_grab_drop", arm).is_success(), "抓取绿豆 300 g")
	_move_arm_next_to(arm, target_wrong.interaction_cell)
	_check(grab_controller.call("request_vehicle_grab_drop", arm).is_success(), "错箱接受任意豆种（不实时拒绝）")

	var submitted: bool = bool(scene.call("submit_beans"))
	_check(submitted, "主动提交结算")
	var snapshot: Dictionary = scene.call("get_settlement")
	_check(int(snapshot.get("score", -1)) == 1000, "得分 = 正确交付克数 1000")
	_check(int(snapshot.get("correct_grams", 0)) == 1000, "正确交付 1000g")
	_check(int(snapshot.get("wrong_box_grams", 0)) == 300, "错箱 300g")
	_check(int(snapshot.get("lost_or_unsubmitted_grams", -1)) == 0, "未流失（3000-1300-1700）")
	_check(int(snapshot.get("max_score", 0)) == 3000, "满分 3000")
	var per_bean: Dictionary = snapshot.get("per_bean_correct", {})
	_check(int(per_bean.get(BeanBatchScript.TYPE_SOYBEAN, 0)) == 1000, "黄豆正确 1000g")
	_check(int(per_bean.get(BeanBatchScript.TYPE_MUNG_BEAN, 0)) == 0, "绿豆错箱正确 0g")

	var old_numbers: Array[int] = []
	for index in range(5):
		old_numbers.append(scene.get_box_number_for_slot(index))
	_check(bool(scene.call("reset_scene_state")), "Reset 场景")
	await process_frame
	_check(not bool(scene.call("is_settled")), "Reset 清除结算状态")
	_check(bean_manager.get_sources()[0].inventory.remaining_grams == 1000, "Reset 恢复来源 1000g")
	_check(bean_manager.get_targets()[0].inventory.get_total_grams() == 0, "Reset 清空目标箱")
	var same_numbers := true
	for index in range(5):
		if scene.get_box_number_for_slot(index) != old_numbers[index]:
			same_numbers = false
	_check(same_numbers, "Reset 保留本局编号")

	scene.call("run_scene")
	await process_frame
	_check(scene.is_gameplay_running(), "Reset 后再次开始")
	var arm_cell: Vector2i = arm.runtime_state.anchor_cell
	var target_cell := arm_cell + Vector2i(0, 1)
	var source := "automata_scene01_program 2\n[arm_vehicle:moveTo] %d %d\n" % [
		target_cell.x, target_cell.y
	]
	var parsed: Dictionary = ProgramSourceScript.new().parse(source)
	var runner = scene.get_node("SceneRoot/Scene01ProgramRunner")
	var done := {"value": false, "failed": false}
	runner.execution_completed.connect(func(): done["value"] = true)
	runner.execution_failed.connect(func(_i, _r): done["failed"] = true)
	_check(bool(runner.call("start_program", parsed.get("program"))), "Program 在 Bean 场景启动")
	var frames := 0
	while not done["value"] and not done["failed"] and frames < 900:
		await process_frame
		frames += 1
	_check(done["value"], "Program 执行完成")
	_check(arm.runtime_state.anchor_cell == target_cell, "Program 移动到达目标格")

	scene.call("reset_scene_state")
	var numbers_before: Array[int] = []
	for index in range(5):
		numbers_before.append(scene.get_box_number_for_slot(index))
	_check(bool(scene.call("reroll_round")), "新一局重洗")
	var numbers_after: Array[int] = []
	for index in range(5):
		numbers_after.append(scene.get_box_number_for_slot(index))
	numbers_after.sort()
	_check(numbers_after == [1, 2, 3, 4, 5], "新一局编号仍为 1-5 的排列")
	_check(bean_manager.get_sources()[0].inventory.remaining_grams == 1000, "新一局恢复来源")

	scene.queue_free()
	await process_frame
	_finish()


func _target_with_number(bean_manager, scene, number: int):
	var targets = bean_manager.get_targets()
	for index in range(targets.size()):
		if int(scene.call("get_box_number_for_slot", index)) == number:
			return targets[index]
	return null


func _move_arm_next_to(arm, target_cell: Vector2i) -> void:
	var direction: Vector2i = arm.runtime_state.anchor_cell - target_cell
	var stand_cell := target_cell
	var facing: int = VehicleRuntimeStateScript.Facing.WEST
	if direction.x >= 0:
		stand_cell = target_cell + Vector2i(1, 0)
		facing = VehicleRuntimeStateScript.Facing.WEST
	else:
		stand_cell = target_cell + Vector2i(-1, 0)
		facing = VehicleRuntimeStateScript.Facing.EAST
	arm.runtime_state.anchor_cell = stand_cell
	arm.runtime_state.facing = facing
	arm.sync_from_state()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		_failures += 1
		print("FAIL  ", message)


func _finish() -> void:
	print("BEAN FLOW RESULT failures=%d" % _failures)
	quit(0 if _failures == 0 else 1)
extends SceneTree

## 菜单/关卡入口流程验收（非测试套件，不进 CI）。
## 运行：godot --headless --path . --script res://tools/acceptance_menu_flow.gd

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const LEVEL_ONE := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const LEVEL_TWO := "res://scenes/scene_02/scene_02_bean_sorting.tscn"

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var menu := (load(MENU_SCENE) as PackedScene).instantiate()
	root.add_child(menu)
	await _settle(4)
	_check(menu.get_node_or_null("%SceneOneButton") != null, "主菜单有关卡一入口")
	_check(menu.get_node_or_null("%SceneTwoButton") != null, "主菜单有关卡二入口")
	_check(menu.get_node_or_null("%WorkshopButton") != null, "主菜单有装配工坊入口")
	_check(menu.get_node_or_null("%ShowcaseModelRoot").get_child_count() > 0, "主菜单 3D 展示模型已构建")
	menu.queue_free()
	await _settle(2)

	var level := (load(LEVEL_ONE) as PackedScene).instantiate()
	root.add_child(level)
	await _settle(8)
	var esc = level.get_node_or_null("EscMenu")
	_check(esc != null, "关卡内存在 Esc 菜单")
	esc.call("_open_menu")
	_check(esc.visible and paused, "Esc 菜单打开并暂停关卡")
	esc.call("_close_menu")
	_check(not esc.visible and not paused, "继续关闭菜单并恢复运行")
	level.queue_free()
	await _settle(2)

	GameFlow.start_in_workshop = true
	var workshop_level := (load(LEVEL_ONE) as PackedScene).instantiate()
	root.add_child(workshop_level)
	await _settle(24)
	var blueprint_ui = workshop_level.get_node("BlueprintUIRoot")
	_check(blueprint_ui.visible, "从主菜单进入工坊会直接打开装配工作台")
	_check(not GameFlow.start_in_workshop, "工坊入口标记已消费")
	var workshop_manager = workshop_level.get_node("SceneRoot/RobotRoot/Scene01VehicleManager")
	var count_before: int = workshop_manager.get_vehicle_count()
	_check(bool(blueprint_ui.call("_begin_deployment")), "主菜单工坊部署到场景部署点")
	_check(
		workshop_manager.get_vehicle_count() == count_before + 1,
		"主菜单工坊部署后场景车辆数 +1"
	)
	blueprint_ui.call("_open")
	await _settle(2)
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	esc = workshop_level.get_node("EscMenu")
	esc.call("_input", cancel)
	_check(not esc.visible and not paused, "工作台内按 Esc 不会叠加暂停菜单")
	blueprint_ui.call("_close")
	esc.call("_open_menu")
	esc.call("_open_workshop")
	_check(blueprint_ui.visible and not paused, "Esc 菜单可直接打开工坊且不离开关卡")
	workshop_level.queue_free()
	await _settle(2)

	var level_two := (load(LEVEL_TWO) as PackedScene).instantiate()
	root.add_child(level_two)
	await _settle(8)
	var esc_two = level_two.get_node_or_null("EscMenu")
	_check(esc_two != null, "关卡二也存在 Esc 菜单")
	esc_two.call("_open_menu")
	_check(esc_two.visible and paused, "关卡二 Esc 菜单可打开")
	esc_two.call("_close_menu")
	_check(not paused, "关卡二 Esc 菜单可关闭")
	level_two.queue_free()
	await _settle(2)

	quit(0 if _failures == 0 else 1)


func _settle(frames: int) -> void:
	for _i in range(frames):
		await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		_failures += 1
		print("FAIL  ", message)

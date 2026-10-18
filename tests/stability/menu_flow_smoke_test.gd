extends SceneTree

## PR CI smoke for the new entry flow: main menu, in-level Esc menu and the
## Scene 02 composition/workshop entry points.

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const LEVEL_ONE := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const LEVEL_TWO := "res://scenes/scene_02/scene_02_bean_sorting.tscn"

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var menu := (load(MENU_SCENE) as PackedScene).instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame
	_expect_true(menu.get_node_or_null("%SceneOneButton") != null, "Main menu has Scene 01 entry.")
	_expect_true(menu.get_node_or_null("%SceneTwoButton") != null, "Main menu has Scene 02 entry.")
	_expect_true(menu.get_node_or_null("%WorkshopButton") != null, "Main menu has Workshop entry.")
	var showcase := menu.get_node_or_null("%ShowcaseModelRoot")
	_expect_true(showcase != null and showcase.get_child_count() > 0, "Main menu showcase model is built.")
	menu.queue_free()
	await process_frame

	var level := (load(LEVEL_ONE) as PackedScene).instantiate()
	root.add_child(level)
	await process_frame
	await process_frame
	var esc := level.get_node_or_null("EscMenu")
	_expect_true(esc != null, "Scene 01 has the Esc menu.")
	esc.call("_open_menu")
	_expect_true(esc.visible and paused, "Esc menu opens and pauses the level.")
	esc.call("_close_menu")
	_expect_true(not esc.visible and not paused, "Esc menu closes and resumes the level.")
	_expect_true(level.get_node_or_null("BlueprintUIRoot") != null, "Scene 01 keeps the workshop root.")
	var point := level.get_node_or_null("LevelDeploymentPoint")
	_expect_true(point != null, "Scene 01 has a deployment point.")
	if point != null:
		_expect_equal(point.call("get_deploy_cell"), Vector2i(12, 6), "Scene 01 deployment point is stable.")
	level.queue_free()
	await process_frame

	var bean := (load(LEVEL_TWO) as PackedScene).instantiate()
	root.add_child(bean)
	await process_frame
	await process_frame
	_expect_true(bean.get_node_or_null("EscMenu") != null, "Scene 02 has the Esc menu.")
	_expect_true(bean.get_node_or_null("BlueprintUIRoot") != null, "Scene 02 can open the workshop.")
	var bean_point := bean.get_node_or_null("LevelDeploymentPoint")
	_expect_true(bean_point != null, "Scene 02 has a deployment point.")
	if bean_point != null:
		_expect_equal(bean_point.call("get_deploy_cell"), Vector2i(7, 8), "Scene 02 deployment point is stable.")
	var bean_hud := bean.get_node_or_null("BeanHUDRoot")
	_expect_true(
		bean_hud != null and bean_hud.get_node_or_null("%StateLabel") != null,
		"Scene 02 HUD binds its unique state label."
	)
	bean.queue_free()
	await process_frame

	if failures == 0:
		print("PASS  menu_flow_smoke")
	else:
		push_error("menu_flow_smoke failures: %d" % failures)
	quit(0 if failures == 0 else 1)


func _expect_true(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures += 1
		push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])

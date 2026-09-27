extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const LayoutMetrics := preload("res://scripts/scene_01/scene_01_ui_layout_metrics.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for sidebar UI contract.")
	if packed == null:
		_finish()
		return

	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var scene := packed.instantiate()
	viewport.add_child(scene)
	await process_frame
	await process_frame

	var hud := scene.get_node("HUDRoot")
	var sidebar := hud.get_node("%SidebarPanel") as Control
	var scroll := hud.get_node("%SidebarScroll") as ScrollContainer
	var content := hud.get_node("%Sidebar") as VBoxContainer
	var mission := hud.get_node("%MissionSection") as Control
	var vehicle := hud.get_node("%VehicleSection") as Control
	var status := hud.get_node("%StatusSection") as Control
	var status_card := hud.get_node("%StatusCard") as Control
	var status_collapse := hud.get_node("%StatusCollapseButton") as Button
	var pointer := hud.get_node("%PointerSection") as Control
	var pointer_label := hud.get_node("%PointerLabel") as Label
	var feedback := hud.get_node("%FeedbackLabel") as Label
	var tutorial := hud.get_node("%TutorialSection") as Control
	var tutorial_body := hud.get_node("%TutorialBody") as Control
	var guide := hud.get_node("%GuideSection") as Control
	var tutorial_owner := scene.get_node("SceneRoot/Scene01Tutorial")

	_expect_true(
		sidebar != null and scroll != null and content != null
		and mission != null and vehicle != null and status != null
		and pointer != null and tutorial != null and guide != null,
		"Sidebar should expose mission, vehicle, status, pointer, and learning sections."
	)
	if sidebar == null or scroll == null or status == null or status_card == null or tutorial == null:
		await _cleanup(scene, viewport)
		return

	_expect_true(scene.get_node_or_null("TutorialUIRoot") == null, "Tutorial should not own a separate floating panel.")
	_expect_true(scene.get_node_or_null("UIRoot/RootControl/Panel") == null, "Guide should not own a separate floating panel.")
	_expect_true(
		mission.get_parent() == status.get_parent()
		and vehicle.get_parent() == status.get_parent()
		and pointer.get_parent() == status.get_parent()
		and tutorial.get_parent() == status.get_parent(),
		"Primary information blocks should be sibling sections in one Sidebar."
	)
	_expect_true(status_collapse != null and status_collapse.icon != null and status_collapse.text.is_empty(), "Status should use an icon disclosure control.")
	_expect_true(status_card.is_ancestor_of(feedback), "Status feedback should collapse with the Status body.")
	_expect_true(pointer_label != null, "Pointer coordinates should be lightweight player-facing state.")
	_expect_true(scene.get_node_or_null("DebugUIRoot/RootControl/Panel/Margin/VBox/CoordinatesRow") == null, "Pointer coordinates should not return to Debug.")

	_expect_equal(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "Sidebar should never scroll horizontally.")
	_expect_equal(scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_AUTO, "Sidebar should scroll vertically only when required.")
	var vscroll := scroll.get_v_scroll_bar()
	_expect_true(vscroll.get_theme_constant("scroll_size") <= 6, "Sidebar scrollbar should stay visually thin.")
	var grabber := vscroll.get_theme_stylebox("grabber") as StyleBoxFlat
	_expect_true(grabber != null and grabber.bg_color.a <= 0.3, "Sidebar scrollbar should remain visually quiet.")

	var max_height := LayoutMetrics.left_sidebar_max_height(float(viewport.size.y))
	_expect_near(max_height, float(viewport.size.y) - LayoutMetrics.CONTENT_TOP - LayoutMetrics.CONTENT_BOTTOM_MARGIN, 1.0, "Sidebar maximum should use the available viewport height.")
	_expect_true(sidebar.size.y <= max_height + 1.0, "Sidebar should never exceed its viewport-derived cap.")

	_expect_true(bool(tutorial.call("is_collapsed")), "Tutorial should start collapsed in the compact main state.")
	_expect_false(tutorial_body.visible, "Default collapsed Tutorial should not lengthen the Sidebar.")

	hud.call("set_status_collapsed", true)
	await process_frame
	_expect_true(bool(hud.call("is_status_collapsed")), "Status should support presentation-only collapse.")
	_expect_false(status_card.visible, "Collapsed Status should hide its whole body.")
	_expect_true(mission.visible and vehicle.visible and pointer.visible, "Status collapse should not affect sibling sections.")
	hud.call("set_status_collapsed", false)
	await process_frame
	_expect_true(status_card.visible, "Expanded Status should restore its body.")

	tutorial.call("set_collapsed", false)
	await process_frame
	await process_frame
	_expect_true(tutorial_body.visible, "Expanded Tutorial should restore its body.")
	_expect_true(sidebar.size.y <= LayoutMetrics.left_sidebar_max_height(float(viewport.size.y)) + 1.0, "Expanded Tutorial should scroll inside the capped Sidebar.")

	tutorial_owner.call("skip_tutorial")
	await process_frame
	_expect_false(tutorial.visible, "Skipping Tutorial should hide its presentation section.")
	_expect_true(guide.visible, "Guide should replace Tutorial inside the same Sidebar.")
	_expect_true(sidebar.visible, "Skipping Tutorial should not remove the Sidebar.")

	await _cleanup(scene, viewport)


func _cleanup(scene: Node, viewport: SubViewport) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	if viewport != null and is_instance_valid(viewport):
		viewport.queue_free()
		await process_frame
	_finish()


func _expect_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) <= tolerance:
		return
	failures += 1
	push_error("%s Expected %.2f ± %.2f, got %.2f." % [message, expected, tolerance, actual])


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	failures += 1
	push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])


func _expect_true(value: bool, message: String) -> void:
	if value:
		return
	failures += 1
	push_error(message)


func _expect_false(value: bool, message: String) -> void:
	_expect_true(not value, message)


func _finish() -> void:
	if failures == 0:
		print("Scene 01 sidebar UI contract tests passed.")
	quit(failures)

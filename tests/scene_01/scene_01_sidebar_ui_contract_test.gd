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

	var hud := scene.get_node_or_null("HUDRoot")
	var sidebar := hud.get_node_or_null("%SidebarPanel") as Control if hud != null else null
	var scroll := hud.get_node_or_null("%SidebarScroll") as ScrollContainer if hud != null else null
	var content := hud.get_node_or_null("%Sidebar") as VBoxContainer if hud != null else null
	var mission := hud.get_node_or_null("%MissionSection") as Control if hud != null else null
	var vehicle := hud.get_node_or_null("%VehicleSection") as Control if hud != null else null
	var status := hud.get_node_or_null("%StatusSection") as Control if hud != null else null
	var status_card := hud.get_node_or_null("%StatusCard") as Control if hud != null else null
	var status_collapse := hud.get_node_or_null("%StatusCollapseButton") as Button if hud != null else null
	var pointer := hud.get_node_or_null("%PointerSection") as Control if hud != null else null
	var pointer_label := hud.get_node_or_null("%PointerLabel") as Label if hud != null else null
	var feedback := hud.get_node_or_null("%FeedbackLabel") as Label if hud != null else null
	var tutorial := hud.get_node_or_null("%TutorialSection") as Control if hud != null else null
	var tutorial_body := hud.get_node_or_null("%TutorialBody") as Control if hud != null else null
	var tutorial_collapse := hud.get_node_or_null("%CollapseButton") as Button if hud != null else null
	var tutorial_previous := hud.get_node_or_null("%PreviousButton") as Button if hud != null else null
	var tutorial_next := hud.get_node_or_null("%NextButton") as Button if hud != null else null
	var tutorial_skip := hud.get_node_or_null("%SkipButton") as Button if hud != null else null
	var guide := hud.get_node_or_null("%GuideSection") as Control if hud != null else null
	var tutorial_owner := scene.get_node_or_null("SceneRoot/Scene01Tutorial")

	var dependencies_ready := (
		hud != null
		and sidebar != null
		and scroll != null
		and content != null
		and mission != null
		and vehicle != null
		and status != null
		and status_card != null
		and status_collapse != null
		and pointer != null
		and pointer_label != null
		and feedback != null
		and tutorial != null
		and tutorial_body != null
		and tutorial_collapse != null
		and tutorial_previous != null
		and tutorial_next != null
		and tutorial_skip != null
		and guide != null
		and tutorial_owner != null
	)
	_expect_true(
		dependencies_ready,
		"Sidebar contract dependencies should resolve through stable unique names."
	)
	if not dependencies_ready:
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

	_expect_true(scroll.theme != null, "Sidebar scroll styling should be assigned statically by the scene resource.")
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
	_expect_true(
		tutorial_collapse.text.is_empty() and tutorial_collapse.icon != null,
		"Tutorial disclosure should use the shared chevron icon language instead of +/- glyphs."
	)
	_expect_equal(
		tutorial_collapse.icon.get_class(),
		"DPITexture",
		"Tutorial disclosure SVG should import as DPITexture."
	)
	for button in [tutorial_previous, tutorial_next, tutorial_skip]:
		_expect_true(button.custom_minimum_size.y >= 32.0, "Tutorial navigation buttons should keep a padded minimum height.")
		var normal_style := button.get_theme_stylebox("normal")
		_expect_true(
			normal_style.content_margin_left >= 10.0
			and normal_style.content_margin_right >= 10.0
			and normal_style.content_margin_top >= 5.0
			and normal_style.content_margin_bottom >= 5.0,
			"Tutorial navigation button text should have stable internal padding."
		)

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
	_expect_true(
		tutorial_collapse.text.is_empty() and tutorial_collapse.icon != null,
		"Expanded Tutorial should keep icon-only disclosure geometry."
	)
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

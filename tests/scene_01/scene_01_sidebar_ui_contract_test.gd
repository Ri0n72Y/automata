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
	var rail_collapse := hud.get_node_or_null("%RailCollapseButton") as Button if hud != null else null
	var pointer := hud.get_node_or_null("%PointerSection") as Control if hud != null else null
	var pointer_label := hud.get_node_or_null("%PointerLabel") as Label if hud != null else null
	var feedback := hud.get_node_or_null("%FeedbackLabel") as Label if hud != null else null
	var tutorial := hud.get_node_or_null("%TutorialSection") as Control if hud != null else null
	var tutorial_body := hud.get_node_or_null("%TutorialBody") as Control if hud != null else null
	var tutorial_content_margin := hud.get_node_or_null("%TutorialContentMargin") as MarginContainer if hud != null else null
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
		and rail_collapse != null
		and pointer != null
		and pointer_label != null
		and feedback != null
		and tutorial != null
		and tutorial_body != null
		and tutorial_content_margin != null
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
	_expect_true(rail_collapse.icon != null and rail_collapse.text.is_empty(), "Main rail should expose its own disclosure control.")
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

	for viewport_size in [
		Vector2i(1280, 720),
		Vector2i(1600, 900),
		Vector2i(1920, 1080),
		Vector2i(2264, 1274),
	]:
		viewport.size = viewport_size
		await process_frame
		await process_frame
		_expect_near(
			sidebar.size.x,
			LayoutMetrics.left_rail_width(float(viewport_size.x)),
			2.0,
			"Expanded Sidebar width should follow the reference-derived shared metric."
		)

	viewport.size = Vector2i(1280, 720)
	await process_frame
	await process_frame
	var expanded_height := sidebar.size.y
	_expect_true(rail_collapse.get_parent() == hud.get_node("RootControl"), "Rail disclosure must be a RootControl sibling, not a PanelContainer child.")
	_expect_true(rail_collapse.size.x <= 32.0 and rail_collapse.size.y <= 32.0, "Rail disclosure hitbox should stay limited to the visible control.")
	hud.call("set_rail_collapsed", true)
	await process_frame
	_expect_true(bool(hud.call("is_rail_collapsed")), "Main Sidebar should support presentation-only rail collapse.")
	_expect_near(sidebar.size.x, LayoutMetrics.LEFT_RAIL_COLLAPSED_WIDTH, 1.0, "Collapsed rail should release gameplay width.")
	_expect_near(sidebar.size.y, expanded_height, 1.0, "Collapsed rail should keep the expanded vertical rail geometry.")
	_expect_false(scroll.is_visible_in_tree(), "Collapsed rail should hide its content without changing section ownership.")
	_expect_equal(sidebar.mouse_filter, Control.MOUSE_FILTER_IGNORE, "Collapsed shell must not become a transparent world-input blocker.")
	_expect_equal(rail_collapse.mouse_filter, Control.MOUSE_FILTER_STOP, "Only the real disclosure surface should stop pointer input while collapsed.")
	_expect_equal(rail_collapse.text, "→", "Collapsed rail should use a rightward expand affordance.")
	_expect_true(mission.get_parent() == content and vehicle.get_parent() == content and status.get_parent() == content, "Rail collapse should not reparent domain presentation sections.")
	hud.call("set_rail_collapsed", false)
	await process_frame
	_expect_false(bool(hud.call("is_rail_collapsed")), "Main Sidebar should expand through the same presentation state.")
	_expect_true(scroll.is_visible_in_tree(), "Expanded rail should restore its existing content tree.")
	_expect_equal(sidebar.mouse_filter, Control.MOUSE_FILTER_STOP, "Expanded rail should restore its normal pointer-blocking surface.")
	_expect_equal(rail_collapse.text, "←", "Expanded rail should use a leftward collapse affordance.")

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
	var collapsed_icon: Texture2D = tutorial_collapse.icon
	_expect_tutorial_button_geometry(tutorial_previous)
	_expect_tutorial_button_geometry(tutorial_next)
	_expect_tutorial_button_geometry(tutorial_skip)
	_expect_true(
		tutorial_content_margin.get_theme_constant("margin_left") >= 14
		and tutorial_content_margin.get_theme_constant("margin_right") >= 14
		and tutorial_content_margin.get_theme_constant("margin_top") >= 10
		and tutorial_content_margin.get_theme_constant("margin_bottom") >= 10,
		"Tutorial body text should keep explicit content padding."
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
	_expect_true(
		tutorial_collapse.icon != collapsed_icon,
		"Tutorial disclosure should switch from right chevron when collapsed to down chevron when expanded."
	)
	_expect_equal(
		tutorial_collapse.icon.get_class(),
		"DPITexture",
		"Expanded Tutorial disclosure SVG should remain a DPITexture."
	)
	_expect_true(sidebar.size.y <= LayoutMetrics.left_sidebar_max_height(float(viewport.size.y)) + 1.0, "Expanded Tutorial should scroll inside the capped Sidebar.")

	tutorial_next.grab_focus()
	await process_frame
	_expect_equal(
		viewport.gui_get_focus_owner(),
		tutorial_next,
		"Tutorial fixture should establish focus inside the Tutorial body."
	)
	hud.call("set_status_collapsed", true)
	await process_frame
	_expect_equal(
		viewport.gui_get_focus_owner(),
		tutorial_next,
		"Collapsing Status should not release focus owned by another UI section."
	)
	hud.call("set_status_collapsed", false)
	tutorial.call("set_collapsed", true)
	await process_frame
	_expect_true(
		viewport.gui_get_focus_owner() == null,
		"Collapsing Tutorial should release focus owned by the body being hidden."
	)
	tutorial.call("set_collapsed", false)
	await process_frame

	tutorial_owner.call("skip_tutorial")
	await process_frame
	_expect_false(tutorial.visible, "Skipping Tutorial should hide its presentation section.")
	_expect_true(guide.visible, "Guide should replace Tutorial inside the same Sidebar.")
	_expect_true(sidebar.visible, "Skipping Tutorial should not remove the Sidebar.")

	await _cleanup(scene, viewport)


func _expect_tutorial_button_geometry(button: Button) -> void:
	_expect_true(
		button.custom_minimum_size.y >= 32.0,
		"Tutorial navigation buttons should keep a padded minimum height."
	)
	var normal_style: StyleBoxFlat = button.get_theme_stylebox("normal") as StyleBoxFlat
	_expect_true(
		normal_style != null,
		"Tutorial navigation buttons should expose an explicit normal StyleBoxFlat."
	)
	if normal_style == null:
		return
	var normal_margins := _style_margins(normal_style)
	_expect_true(
		normal_style.content_margin_left >= 10.0
		and normal_style.content_margin_right >= 10.0
		and normal_style.content_margin_top >= 5.0
		and normal_style.content_margin_bottom >= 5.0,
		"Tutorial navigation button text should have stable internal padding."
	)
	var state_names: Array[StringName] = [
		&"hover",
		&"pressed",
		&"hover_pressed",
		&"disabled",
		&"focus",
	]
	for style_name in state_names:
		var state_style: StyleBoxFlat = button.get_theme_stylebox(style_name) as StyleBoxFlat
		_expect_true(
			state_style != null,
			"Tutorial navigation button state '%s' should expose StyleBoxFlat geometry." % String(style_name)
		)
		if state_style != null:
			_expect_equal(
				_style_margins(state_style),
				normal_margins,
				"Tutorial navigation button state '%s' should preserve normal-state geometry." % String(style_name)
			)
	var focus_style: StyleBoxFlat = button.get_theme_stylebox("focus") as StyleBoxFlat
	if focus_style != null:
		_expect_true(
			focus_style.bg_color != normal_style.bg_color
			or focus_style.border_color != normal_style.border_color,
			"Tutorial focus state should remain visibly distinct without changing geometry."
		)


func _style_margins(style: StyleBoxFlat) -> Vector4:
	return Vector4(
		style.content_margin_left,
		style.content_margin_top,
		style.content_margin_right,
		style.content_margin_bottom
	)


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

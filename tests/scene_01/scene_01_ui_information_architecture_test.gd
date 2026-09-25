extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const LayoutMetrics := preload("res://scripts/scene_01/scene_01_ui_layout_metrics.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for UI information architecture checks.")
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

	var sidebar := scene.get_node("HUDRoot/RootControl/SidebarPanel") as Control
	var mission_section := scene.get_node("HUDRoot/RootControl/SidebarPanel/Margin/Sidebar/MissionSection") as Control
	var vehicle_section := scene.get_node("HUDRoot/RootControl/SidebarPanel/Margin/Sidebar/VehicleSection") as Control
	var status_section := scene.get_node("HUDRoot/RootControl/SidebarPanel/Margin/Sidebar/StatusSection") as Control
	var status_card := scene.get_node("HUDRoot/RootControl/SidebarPanel/Margin/Sidebar/StatusSection/StatusCard") as Control
	var pointer_section := scene.get_node("HUDRoot/RootControl/SidebarPanel/Margin/Sidebar/PointerSection") as Control
	var status_collapse := scene.get_node("HUDRoot/RootControl/SidebarPanel/Margin/Sidebar/StatusSection/Header/Margin/Row/StatusCollapseButton") as Button
	var tutorial_section := scene.get_node("HUDRoot/RootControl/SidebarPanel/Margin/Sidebar/TutorialSection") as Control
	var tutorial_body := scene.get_node("HUDRoot/RootControl/SidebarPanel/Margin/Sidebar/TutorialSection/TutorialBody") as Control
	var guide_section := scene.get_node("HUDRoot/RootControl/SidebarPanel/Margin/Sidebar/GuideSection") as Control
	var tutorial_owner := scene.get_node("SceneRoot/Scene01Tutorial")
	var program_ui := scene.get_node("ProgramUIRoot")
	var program_panel := scene.get_node("ProgramUIRoot/RootControl/ProgramPanel") as Control
	var lifecycle_panel := scene.get_node("LifecycleUIRoot/RootControl/Panel") as Control
	var lifecycle_dot := scene.get_node("LifecycleUIRoot/RootControl/Panel/Margin/Controls/StatusGroup/StatusDot") as TextureRect
	var lifecycle_state := scene.get_node("LifecycleUIRoot/RootControl/Panel/Margin/Controls/StatusGroup/StateLabel") as Label
	var lifecycle_time := scene.get_node("LifecycleUIRoot/RootControl/Panel/Margin/Controls/TimeLabel") as Label
	var lifecycle_speed := scene.get_node("LifecycleUIRoot/RootControl/Panel/Margin/Controls/SpeedOption") as OptionButton
	var debug_panel := scene.get_node("DebugUIRoot/RootControl/Panel") as Control
	var hud_root := scene.get_node("HUDRoot/RootControl") as Control
	var program_root := scene.get_node("ProgramUIRoot/RootControl") as Control
	var lifecycle_root := scene.get_node("LifecycleUIRoot/RootControl") as Control
	var debug_root := scene.get_node("DebugUIRoot/RootControl") as Control

	_expect_true(
		sidebar != null
		and mission_section != null
		and vehicle_section != null
		and status_section != null
		and pointer_section != null
		and tutorial_section != null
		and guide_section != null,
		"Scene 01 should expose one main sidebar with mission, vehicle, status, pointer, and learning sections."
	)
	_expect_true(
		lifecycle_dot != null and lifecycle_state != null and lifecycle_time != null and lifecycle_speed != null,
		"Lifecycle capsule should expose a real status dot, state, simulation time, and explicit speed selection."
	)
	_expect_true(lifecycle_panel.size.x <= 354.0, "Lifecycle capsule should match the compact design-width contract.")
	_expect_true(lifecycle_panel.size.y <= 44.0, "Lifecycle capsule should match the compact design-height contract.")
	var run_reset_group := scene.get_node("LifecycleUIRoot/RootControl/Panel/Margin/Controls/RunResetGroup") as PanelContainer
	var run_button := scene.get_node("LifecycleUIRoot/RootControl/Panel/Margin/Controls/RunResetGroup/Controls/RunPauseButton") as Button
	var reset_button := scene.get_node("LifecycleUIRoot/RootControl/Panel/Margin/Controls/RunResetGroup/Controls/ResetButton") as Button
	_expect_true(run_reset_group != null and run_button != null and reset_button != null, "Play/Pause and Reset should share one compact control group.")
	var capsule_style := lifecycle_panel.get_theme_stylebox("panel") as StyleBoxFlat
	var control_group_style := run_reset_group.get_theme_stylebox("panel") as StyleBoxFlat
	_expect_true(capsule_style != null and capsule_style.shadow_size >= 6, "Lifecycle capsule boundary should come from a soft outer shadow.")
	_expect_true(control_group_style != null and control_group_style.shadow_size >= 2, "Run/Reset group should use a lighter nested shadow.")
	_expect_true(
		capsule_style.border_width_left == 0
		and capsule_style.border_width_top == 0
		and capsule_style.border_width_right == 0
		and capsule_style.border_width_bottom == 0,
		"Lifecycle capsule should not reintroduce a hard border."
	)
	_expect_true(
		control_group_style.border_width_left == 0
		and control_group_style.border_width_top == 0
		and control_group_style.border_width_right == 0
		and control_group_style.border_width_bottom == 0,
		"Run/Reset group should also rely on shadow rather than border."
	)
	_expect_true(not lifecycle_speed.fit_to_longest_item, "Speed selector should stay compact instead of reserving long dropdown width.")
	_expect_true(lifecycle_dot.custom_minimum_size.x >= 12.0, "Status dot should keep the larger design-reference size.")
	_expect_equal(lifecycle_dot.size_flags_vertical, Control.SIZE_SHRINK_CENTER, "Status dot should not stretch to the lifecycle row height.")
	_expect_equal(lifecycle_dot.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "Status dot texture should preserve a circular aspect ratio.")
	_expect_true(run_button.text.is_empty() and reset_button.text.is_empty(), "Lifecycle actions should use SVG icons rather than font glyphs.")
	_expect_true(run_button.icon != null and reset_button.icon != null, "Lifecycle action SVG icons should be present.")
	_expect_equal(run_button.icon.get_class(), "DPITexture", "Lifecycle play/pause icon should import as DPITexture for UI oversampling.")
	_expect_equal(reset_button.icon.get_class(), "DPITexture", "Lifecycle reset icon should import as DPITexture for UI oversampling.")
	_expect_true(lifecycle_speed.get_theme_stylebox("normal").content_margin_left >= 8.0, "Speed selector should keep 8px left padding.")
	_expect_true(lifecycle_speed.get_theme_stylebox("normal").content_margin_right >= 8.0, "Speed selector should keep 8px right padding.")
	_expect_true(run_button.size.x <= 30.0 and reset_button.size.x <= 30.0, "Hover hit visuals should remain smaller than the outer run/reset group.")
	_expect_true(run_button.icon_alignment == HORIZONTAL_ALIGNMENT_CENTER and reset_button.icon_alignment == HORIZONTAL_ALIGNMENT_CENTER, "Lifecycle SVG actions should remain centered across interaction states.")
	_expect_true(scene.get_node_or_null("TutorialUIRoot") == null, "Tutorial should no longer own a separate floating panel.")
	_expect_true(scene.get_node_or_null("UIRoot/RootControl/Panel") == null, "Guide should no longer own a separate floating panel.")
	_expect_true(
		mission_section.get_parent() == status_section.get_parent()
		and vehicle_section.get_parent() == status_section.get_parent()
		and pointer_section.get_parent() == status_section.get_parent()
		and tutorial_section.get_parent() == status_section.get_parent(),
		"Primary information blocks must be sibling sections in the same sidebar."
	)
	_expect_true(status_collapse != null and status_collapse.icon != null, "Status section should expose a chevron disclosure control.")
	_expect_true(status_collapse.text.is_empty(), "Status disclosure should use an icon instead of +/- text.")
	_expect_true(
		scene.get_node_or_null("HUDRoot/RootControl/SidebarPanel/Margin/Sidebar/PointerSection/Card/Margin/PointerLabel") != null,
		"Grid coordinates should be lightweight player-facing status."
	)
	_expect_true(
		scene.get_node_or_null("DebugUIRoot/RootControl/Panel/Margin/VBox/CoordinatesRow") == null,
		"Grid coordinates should not be a Debug UI toggle."
	)

	for ui_root in [hud_root, program_root, lifecycle_root, debug_root]:
		_expect_true(ui_root != null and ui_root.theme != null, "Every visible Scene 01 UI surface should use the shared explicit theme.")

	program_ui.call("set_workspace_collapsed", false)

	for viewport_size in [
		Vector2i(1280, 720),
		Vector2i(1600, 900),
		Vector2i(1920, 1080),
	]:
		viewport.size = viewport_size
		await process_frame
		await process_frame
		var expected_left_width := LayoutMetrics.left_rail_width(float(viewport_size.x))
		var expected_program_width := LayoutMetrics.program_rail_width(float(viewport_size.x))
		_expect_near(sidebar.size.x, expected_left_width, 2.0, "Main sidebar width should follow the shared left-rail tier.")
		_expect_near(program_panel.size.x, expected_program_width, 2.0, "Expanded Program width should follow its existing right-rail tier.")
		_expect_near(sidebar.position.x, LayoutMetrics.EDGE_MARGIN, 1.0, "Main sidebar should align to the common edge margin.")
		_expect_near(sidebar.position.y, LayoutMetrics.CONTENT_TOP, 1.0, "Main sidebar should begin below the lifecycle control.")
		_expect_true(sidebar.get_global_rect().end.y <= float(viewport_size.y) - LayoutMetrics.CONTENT_BOTTOM_MARGIN + 1.0, "Main sidebar should fit the supported viewport height.")
		_expect_false(program_panel.get_global_rect().intersects(lifecycle_panel.get_global_rect()), "Program rail must stay below the lifecycle controls.")
		_expect_false(debug_panel.get_global_rect().intersects(program_panel.get_global_rect()), "Collapsed Debug entry must stay above the Program rail.")
		_expect_true(program_panel.get_global_rect().position.x - sidebar.get_global_rect().end.x >= 400.0, "Supported desktop sizes should preserve at least 400px of central gameplay width.")

	var hud_ui := scene.get_node("HUDRoot")
	hud_ui.call("set_status_collapsed", true)
	await process_frame
	_expect_true(bool(hud_ui.call("is_status_collapsed")), "Status section should support presentation-only collapse.")
	_expect_false(status_card.visible, "Collapsed Status should hide only its card body.")
	_expect_true(mission_section.visible and vehicle_section.visible and pointer_section.visible, "Collapsing Status must not affect sibling information sections.")
	hud_ui.call("set_status_collapsed", false)
	await process_frame
	_expect_true(status_card.visible, "Expanded Status should restore its card body.")

	tutorial_section.call("set_collapsed", true)
	await process_frame
	_expect_true(bool(tutorial_section.call("is_collapsed")), "Tutorial section should support presentation-only collapse.")
	_expect_false(tutorial_body.visible, "Collapsed Tutorial should hide only its body inside the sidebar.")
	_expect_true(status_section.visible, "Collapsing Tutorial must not affect Status.")
	tutorial_section.call("set_collapsed", false)
	await process_frame
	_expect_true(tutorial_body.visible, "Expanded Tutorial should restore its body.")

	tutorial_owner.call("skip_tutorial")
	await process_frame
	_expect_false(tutorial_section.visible, "Skipping Tutorial should hide its section presentation.")
	_expect_true(guide_section.visible, "Guide should replace Tutorial inside the same sidebar after skip.")
	_expect_true(sidebar.visible, "Skipping Tutorial must not remove the main sidebar.")

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
		print("Scene 01 UI information architecture tests passed.")
	quit(failures)

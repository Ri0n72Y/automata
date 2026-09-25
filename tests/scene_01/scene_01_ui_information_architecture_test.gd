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

	var hud_panel := scene.get_node("HUDRoot/RootControl/StatusPanel") as Control
	var tutorial_panel := scene.get_node("TutorialUIRoot/RootControl/TutorialPanel") as Control
	var tutorial_ui := scene.get_node("TutorialUIRoot")
	var manual_ui := scene.get_node("UIRoot")
	var manual_root := scene.get_node("UIRoot/RootControl") as Control
	var manual_panel := scene.get_node("UIRoot/RootControl/Panel") as Control
	var program_ui := scene.get_node("ProgramUIRoot")
	var program_panel := scene.get_node("ProgramUIRoot/RootControl/ProgramPanel") as Control
	var lifecycle_panel := scene.get_node("LifecycleUIRoot/RootControl/Panel") as Control
	var debug_panel := scene.get_node("DebugUIRoot/RootControl/Panel") as Control
	var tutorial_owner := scene.get_node("SceneRoot/Scene01Tutorial")
	var hud_root := scene.get_node("HUDRoot/RootControl") as Control
	var tutorial_root := scene.get_node("TutorialUIRoot/RootControl") as Control
	var program_root := scene.get_node("ProgramUIRoot/RootControl") as Control
	var lifecycle_root := scene.get_node("LifecycleUIRoot/RootControl") as Control
	var debug_root := scene.get_node("DebugUIRoot/RootControl") as Control

	_expect_true(
		hud_panel != null
		and tutorial_panel != null
		and manual_panel != null
		and program_panel != null
		and lifecycle_panel != null
		and debug_panel != null,
		"Scene 01 should expose all primary UI panels."
	)
	if (
		hud_panel == null
		or tutorial_panel == null
		or manual_panel == null
		or program_panel == null
		or lifecycle_panel == null
		or debug_panel == null
	):
		await _cleanup(scene, viewport)
		return

	_expect_true(
		scene.get_node_or_null("TutorialUIRoot/RootControl/TutorialPanel/Margin/VBox/CapabilityLabel") == null,
		"Tutorial should not expose internal Assembly Compile capability presentation."
	)
	_expect_equal(
		(scene.get_node("HUDRoot/RootControl/StatusPanel/Margin/VBox/Header/Title") as Label).text,
		"状态查看",
		"HUD title should express the player-facing inspection role."
	)
	_expect_true(
		scene.get_node_or_null("HUDRoot/RootControl/StatusPanel/Margin/VBox/PointerLabel") != null,
		"Grid coordinates should be available as lightweight player-facing pointer state."
	)
	_expect_true(
		scene.get_node_or_null("DebugUIRoot/RootControl/Panel/Margin/VBox/CoordinatesRow") == null,
		"Grid coordinates should no longer be presented as a debug toggle."
	)
	_expect_equal(
		(scene.get_node("TutorialUIRoot/RootControl/TutorialPanel/Margin/VBox/Header/Title") as Label).text,
		"教学",
		"Tutorial title should avoid redundant scene naming."
	)
	_expect_equal(
		(scene.get_node("UIRoot/RootControl/Panel/Margin/VBox/HeaderRow/Title") as Label).text,
		"操作指南",
		"Guide title should avoid redundant scene naming."
	)

	for ui_root in [hud_root, tutorial_root, manual_root, program_root, lifecycle_root, debug_root]:
		_expect_true(ui_root != null and ui_root.theme != null, "Every Scene 01 UI surface should use the shared explicit theme.")

	program_ui.call("set_workspace_collapsed", false)
	manual_ui.call("set_collapsed", false)

	for viewport_size in [
		Vector2i(1280, 720),
		Vector2i(1600, 900),
		Vector2i(1920, 1080),
	]:
		viewport.size = viewport_size
		await process_frame
		await process_frame
		_assert_layout(viewport_size, hud_panel, tutorial_panel, manual_panel, program_panel, lifecycle_panel, debug_panel)

	tutorial_ui.call("set_collapsed", true)
	await process_frame
	_expect_true(bool(tutorial_ui.call("is_collapsed")), "Tutorial should support presentation-only collapse.")
	_expect_near(tutorial_panel.size.y, 54.0, 2.0, "Collapsed Tutorial should reduce to a compact header.")
	tutorial_ui.call("set_collapsed", false)
	await process_frame

	_expect_true(tutorial_panel.visible, "Tutorial should own the auxiliary left-rail slot while Tutorial presentation is visible.")
	_expect_false(manual_root.visible, "Guide presentation should stay hidden while Tutorial owns the auxiliary slot.")
	tutorial_owner.call("skip_tutorial")
	await process_frame
	_expect_false(tutorial_panel.visible, "Skipping Tutorial should hide only Tutorial presentation.")
	_expect_true(manual_root.visible, "Guide should reclaim the same auxiliary left-rail slot after Tutorial is hidden.")
	_expect_true(
		absf(manual_panel.position.y - LayoutMetrics.LEFT_AUX_TOP) <= 1.0,
		"Guide should reuse the shared auxiliary left-rail top."
	)

	await _cleanup(scene, viewport)


func _assert_layout(
	viewport_size: Vector2i,
	hud_panel: Control,
	tutorial_panel: Control,
	manual_panel: Control,
	program_panel: Control,
	lifecycle_panel: Control,
	debug_panel: Control
) -> void:
	var expected_left_width := LayoutMetrics.left_rail_width(float(viewport_size.x))
	var expected_program_width := LayoutMetrics.program_rail_width(float(viewport_size.x))

	_expect_near(hud_panel.size.x, expected_left_width, 2.0, "HUD width should follow the shared left-rail tier.")
	_expect_near(tutorial_panel.size.x, expected_left_width, 2.0, "Tutorial width should follow the shared left-rail tier.")
	_expect_near(manual_panel.size.x, expected_left_width, 2.0, "Guide width should follow the shared left-rail tier.")
	_expect_near(program_panel.size.x, expected_program_width, 2.0, "Expanded Program width should follow the shared right-rail tier.")

	_expect_near(hud_panel.position.x, LayoutMetrics.EDGE_MARGIN, 1.0, "HUD should align to the common edge margin.")
	_expect_near(hud_panel.position.y, LayoutMetrics.CONTENT_TOP, 1.0, "HUD should start below the lifecycle band.")
	_expect_near(tutorial_panel.position.y, LayoutMetrics.LEFT_AUX_TOP, 1.0, "Tutorial should sit directly below the primary status card.")
	_expect_near(manual_panel.position.y, LayoutMetrics.LEFT_AUX_TOP, 1.0, "Guide should share the Tutorial auxiliary slot.")

	_expect_false(hud_panel.get_global_rect().intersects(tutorial_panel.get_global_rect()), "HUD and Tutorial must not overlap.")
	_expect_false(hud_panel.get_global_rect().intersects(manual_panel.get_global_rect()), "HUD and Guide must not overlap.")
	_expect_false(program_panel.get_global_rect().intersects(lifecycle_panel.get_global_rect()), "Program rail must stay below the lifecycle controls.")
	_expect_false(debug_panel.get_global_rect().intersects(program_panel.get_global_rect()), "Collapsed Debug entry must stay above the Program rail.")

	var left_edge := hud_panel.get_global_rect().end.x
	var right_edge := program_panel.get_global_rect().position.x
	_expect_true(right_edge > left_edge, "Left and right rails must preserve a central gameplay corridor.")
	_expect_true(
		right_edge - left_edge >= 400.0,
		"Supported desktop sizes should preserve at least 400px of central gameplay width."
	)
	_expect_true(
		tutorial_panel.get_global_rect().end.y <= float(viewport_size.y) - LayoutMetrics.CONTENT_BOTTOM_MARGIN + 1.0,
		"Tutorial should stay within the viewport content frame."
	)
	_expect_true(
		manual_panel.get_global_rect().end.y <= float(viewport_size.y) - LayoutMetrics.CONTENT_BOTTOM_MARGIN + 1.0,
		"Expanded Guide should stay within the viewport content frame."
	)
	_expect_true(
		program_panel.get_global_rect().end.y <= float(viewport_size.y) - LayoutMetrics.CONTENT_BOTTOM_MARGIN + 1.0,
		"Program rail should stay within the viewport content frame."
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
		print("Scene 01 UI information architecture tests passed.")
	quit(failures)

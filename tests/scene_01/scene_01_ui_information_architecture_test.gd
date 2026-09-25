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
	var status_section := scene.get_node("HUDRoot/RootControl/SidebarPanel/Margin/Sidebar/StatusSection") as Control
	var tutorial_section := scene.get_node("HUDRoot/RootControl/SidebarPanel/Margin/Sidebar/TutorialSection") as Control
	var tutorial_body := scene.get_node("HUDRoot/RootControl/SidebarPanel/Margin/Sidebar/TutorialSection/TutorialBody") as Control
	var guide_section := scene.get_node("HUDRoot/RootControl/SidebarPanel/Margin/Sidebar/GuideSection") as Control
	var tutorial_owner := scene.get_node("SceneRoot/Scene01Tutorial")
	var program_ui := scene.get_node("ProgramUIRoot")
	var program_panel := scene.get_node("ProgramUIRoot/RootControl/ProgramPanel") as Control
	var lifecycle_panel := scene.get_node("LifecycleUIRoot/RootControl/Panel") as Control
	var lifecycle_state := scene.get_node("LifecycleUIRoot/RootControl/Panel/Margin/Controls/StatusGroup/StateLabel") as Label
	var lifecycle_time := scene.get_node("LifecycleUIRoot/RootControl/Panel/Margin/Controls/TimeLabel") as Label
	var lifecycle_speed := scene.get_node("LifecycleUIRoot/RootControl/Panel/Margin/Controls/SpeedOption") as OptionButton
	var debug_panel := scene.get_node("DebugUIRoot/RootControl/Panel") as Control
	var hud_root := scene.get_node("HUDRoot/RootControl") as Control
	var program_root := scene.get_node("ProgramUIRoot/RootControl") as Control
	var lifecycle_root := scene.get_node("LifecycleUIRoot/RootControl") as Control
	var debug_root := scene.get_node("DebugUIRoot/RootControl") as Control

	_expect_true(
		sidebar != null and status_section != null and tutorial_section != null and guide_section != null,
		"Scene 01 should expose one main sidebar with status and learning sections."
	)
	_expect_true(
		lifecycle_state != null and lifecycle_time != null and lifecycle_speed != null,
		"Lifecycle capsule should expose state, simulation time, and explicit speed selection."
	)
	_expect_true(lifecycle_panel.size.y <= 56.0, "Lifecycle capsule should stay visually compact.")
	_expect_true(scene.get_node_or_null("TutorialUIRoot") == null, "Tutorial should no longer own a separate floating panel.")
	_expect_true(scene.get_node_or_null("UIRoot/RootControl/Panel") == null, "Guide should no longer own a separate floating panel.")
	_expect_true(status_section.get_parent() == tutorial_section.get_parent(), "Status and Tutorial must be sibling sections in the same sidebar.")
	_expect_true(
		scene.get_node_or_null("HUDRoot/RootControl/SidebarPanel/Margin/Sidebar/StatusSection/PointerLabel") != null,
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

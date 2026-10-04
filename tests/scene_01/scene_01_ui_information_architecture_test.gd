extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const LayoutMetrics := preload("res://scripts/scene_01/scene_01_ui_layout_metrics.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for unified right-rail architecture checks.")
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
	var operations_ui := scene.get_node_or_null("OperationsUIRoot")
	var lifecycle_ui := scene.get_node_or_null("LifecycleUIRoot")
	var sidebar := hud.get_node_or_null("%SidebarPanel") as Control if hud != null else null
	var panel := operations_ui.get_node_or_null("%OperationsPanel") as Control if operations_ui != null else null
	var authoring := operations_ui.get_node_or_null("RootControl/OperationsPanel/Margin/VBox/ProgramAuthoring") as Control if operations_ui != null else null
	var lifecycle_panel := lifecycle_ui.get_node_or_null("%Panel") as Control if lifecycle_ui != null else null
	var debug_panel := scene.get_node_or_null("DebugUIRoot/RootControl/Panel") as Control
	var hud_root := scene.get_node_or_null("HUDRoot/RootControl") as Control
	var operations_root := scene.get_node_or_null("OperationsUIRoot/RootControl") as Control
	var lifecycle_root := scene.get_node_or_null("LifecycleUIRoot/RootControl") as Control
	var debug_root := scene.get_node_or_null("DebugUIRoot/RootControl") as Control

	var dependencies_ready := (
		hud != null
		and operations_ui != null
		and lifecycle_ui != null
		and sidebar != null
		and panel != null
		and authoring != null
		and lifecycle_panel != null
		and debug_panel != null
		and hud_root != null
		and operations_root != null
		and lifecycle_root != null
		and debug_root != null
	)
	_expect_true(dependencies_ready, "Unified right-rail dependencies should resolve before layout assertions.")
	if not dependencies_ready:
		await _cleanup(scene, viewport)
		return

	_expect_true(scene.get_node_or_null("ProgramUIRoot") == null, "Operations / Program must have only one right-side main panel.")
	for ui_root in [hud_root, operations_root, lifecycle_root, debug_root]:
		_expect_true(ui_root.theme != null, "Every visible Scene 01 UI surface should use the shared explicit theme.")

	for viewport_size in [
		Vector2i(1280, 720),
		Vector2i(1600, 900),
		Vector2i(1920, 1080),
	]:
		viewport.size = viewport_size
		operations_ui.call("set_authoring_mode", false)
		await process_frame
		await process_frame
		_expect_near(sidebar.size.x, LayoutMetrics.PRIMARY_RAIL_WIDTH, 2.0, "Main Sidebar should use the shared primary rail width.")
		_expect_near(panel.size.x, LayoutMetrics.PRIMARY_RAIL_WIDTH, 2.0, "Default right rail should mirror the accepted 240px main rail.")
		_expect_near(panel.position.x, float(viewport_size.x) - LayoutMetrics.EDGE_MARGIN - LayoutMetrics.PRIMARY_RAIL_WIDTH, 1.0, "Default right rail should mirror left-edge geometry.")
		_expect_near(panel.get_global_rect().end.x, float(viewport_size.x) - LayoutMetrics.EDGE_MARGIN, 1.0, "Default right rail should use the shared outer margin.")
		_expect_near(panel.position.y, LayoutMetrics.CONTENT_TOP, 1.0, "Unified right rail should start at the shared content top.")
		_expect_false(authoring.visible, "Daily mode should not retain a second resident Program surface.")

		operations_ui.call("set_authoring_mode", true)
		await process_frame
		await process_frame
		_expect_true(authoring.is_visible_in_tree(), "Expanded mode should reveal Program authoring inside the same panel.")
		_expect_near(panel.size.x, LayoutMetrics.program_rail_width(float(viewport_size.x)), 2.0, "Expanded unified panel should reuse established authoring width tiers.")
		_expect_near(panel.get_global_rect().end.y, float(viewport_size.y) - LayoutMetrics.CONTENT_BOTTOM_MARGIN, 1.0, "Expanded authoring should stay within viewport safe area.")
		_expect_false(panel.get_global_rect().intersects(lifecycle_panel.get_global_rect()), "Unified right rail should stay below lifecycle controls.")
		_expect_false(debug_panel.get_global_rect().intersects(panel.get_global_rect()), "Collapsed Debug entry should stay above the unified right rail.")
		_expect_true(panel.get_global_rect().position.x - sidebar.get_global_rect().end.x >= 400.0, "Supported desktop sizes should preserve central gameplay width beside expanded authoring.")
		_expect_true(authoring.get_global_rect().end.y <= panel.get_global_rect().end.y + 1.0, "1280x720 authoring content must remain accessible inside the single panel.")

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
		print("Scene 01 unified right-rail architecture tests passed.")
	quit(failures)

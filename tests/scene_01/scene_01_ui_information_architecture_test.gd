extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const LayoutMetrics := preload("res://scripts/scene_01/scene_01_ui_layout_metrics.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for cross-rail UI architecture checks.")
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
	var program_ui := scene.get_node_or_null("ProgramUIRoot")
	var lifecycle_ui := scene.get_node_or_null("LifecycleUIRoot")
	var sidebar := hud.get_node_or_null("%SidebarPanel") as Control if hud != null else null
	var operations_panel := operations_ui.get_node_or_null("%OperationsPanel") as Control if operations_ui != null else null
	var program_panel := program_ui.get_node_or_null("RootControl/ProgramPanel") as Control if program_ui != null else null
	var lifecycle_panel := lifecycle_ui.get_node_or_null("%Panel") as Control if lifecycle_ui != null else null
	var debug_panel := scene.get_node_or_null("DebugUIRoot/RootControl/Panel") as Control
	var hud_root := scene.get_node_or_null("HUDRoot/RootControl") as Control
	var operations_root := scene.get_node_or_null("OperationsUIRoot/RootControl") as Control
	var program_root := scene.get_node_or_null("ProgramUIRoot/RootControl") as Control
	var lifecycle_root := scene.get_node_or_null("LifecycleUIRoot/RootControl") as Control
	var debug_root := scene.get_node_or_null("DebugUIRoot/RootControl") as Control

	var dependencies_ready := (
		hud != null
		and operations_ui != null
		and program_ui != null
		and lifecycle_ui != null
		and sidebar != null
		and operations_panel != null
		and program_panel != null
		and lifecycle_panel != null
		and debug_panel != null
		and hud_root != null
		and operations_root != null
		and program_root != null
		and lifecycle_root != null
		and debug_root != null
	)
	_expect_true(dependencies_ready, "Cross-rail UI contract dependencies should resolve before layout assertions.")
	if not dependencies_ready:
		await _cleanup(scene, viewport)
		return

	for ui_root in [hud_root, operations_root, program_root, lifecycle_root, debug_root]:
		_expect_true(ui_root.theme != null, "Every visible Scene 01 UI surface should use the shared explicit theme.")

	program_ui.call("set_workspace_collapsed", false)

	for viewport_size in [
		Vector2i(1280, 720),
		Vector2i(1600, 900),
		Vector2i(1920, 1080),
		Vector2i(2264, 1274),
	]:
		viewport.size = viewport_size
		await process_frame
		await process_frame
		_expect_near(sidebar.size.x, LayoutMetrics.left_rail_width(float(viewport_size.x)), 2.0, "Main Sidebar width should follow the shared tier.")
		_expect_near(operations_panel.size.x, LayoutMetrics.program_rail_width(float(viewport_size.x)), 2.0, "Operations width should follow the shared right-rail tier.")
		_expect_near(program_panel.size.x, LayoutMetrics.program_rail_width(float(viewport_size.x)), 2.0, "Expanded Program width should follow the shared tier.")
		_expect_near(sidebar.position.x, LayoutMetrics.EDGE_MARGIN, 1.0, "Main Sidebar should align to the common edge margin.")
		_expect_near(sidebar.position.y, LayoutMetrics.CONTENT_TOP, 1.0, "Main Sidebar should begin below lifecycle controls.")
		_expect_true(sidebar.get_global_rect().end.y <= float(viewport_size.y) - LayoutMetrics.CONTENT_BOTTOM_MARGIN + 1.0, "Main Sidebar should remain within the viewport safe area.")
		_expect_near(operations_panel.position.y, LayoutMetrics.CONTENT_TOP, 1.0, "Operations should begin at the shared content top.")
		_expect_near(operations_panel.size.y, operations_panel.get_combined_minimum_size().y, 1.0, "Operations should follow its visible-content natural height.")
		_expect_false(operations_panel.get_global_rect().intersects(program_panel.get_global_rect()), "Operations and Program should be explicit stacked right-rail sections.")
		_expect_false(operations_panel.get_global_rect().intersects(lifecycle_panel.get_global_rect()), "Operations should stay below lifecycle controls.")
		_expect_false(program_panel.get_global_rect().intersects(lifecycle_panel.get_global_rect()), "Program rail should stay below lifecycle controls.")
		_expect_false(debug_panel.get_global_rect().intersects(program_panel.get_global_rect()), "Collapsed Debug entry should stay above the Program rail.")
		_expect_true(operations_panel.get_global_rect().position.x - sidebar.get_global_rect().end.x >= 400.0, "Supported desktop sizes should preserve central gameplay width beside Operations.")
		_expect_true(program_panel.get_global_rect().position.x - sidebar.get_global_rect().end.x >= 400.0, "Supported desktop sizes should preserve central gameplay width beside Program.")

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
		print("Scene 01 cross-rail UI architecture tests passed.")
	quit(failures)

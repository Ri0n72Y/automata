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

	var hud := scene.get_node("HUDRoot")
	var program_ui := scene.get_node("ProgramUIRoot")
	var lifecycle_ui := scene.get_node("LifecycleUIRoot")
	var sidebar := hud.get_node("%SidebarPanel") as Control
	var program_panel := program_ui.get_node("RootControl/ProgramPanel") as Control
	var lifecycle_panel := lifecycle_ui.get_node("%Panel") as Control
	var debug_panel := scene.get_node("DebugUIRoot/RootControl/Panel") as Control
	var roots := [
		scene.get_node("HUDRoot/RootControl") as Control,
		scene.get_node("ProgramUIRoot/RootControl") as Control,
		scene.get_node("LifecycleUIRoot/RootControl") as Control,
		scene.get_node("DebugUIRoot/RootControl") as Control,
	]

	for ui_root in roots:
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
		_expect_near(sidebar.size.x, LayoutMetrics.left_rail_width(float(viewport_size.x)), 2.0, "Main Sidebar width should follow the shared tier.")
		_expect_near(program_panel.size.x, LayoutMetrics.program_rail_width(float(viewport_size.x)), 2.0, "Expanded Program width should follow the shared tier.")
		_expect_near(sidebar.position.x, LayoutMetrics.EDGE_MARGIN, 1.0, "Main Sidebar should align to the common edge margin.")
		_expect_near(sidebar.position.y, LayoutMetrics.CONTENT_TOP, 1.0, "Main Sidebar should begin below lifecycle controls.")
		_expect_true(sidebar.get_global_rect().end.y <= float(viewport_size.y) - LayoutMetrics.CONTENT_BOTTOM_MARGIN + 1.0, "Main Sidebar should remain within the viewport safe area.")
		_expect_false(program_panel.get_global_rect().intersects(lifecycle_panel.get_global_rect()), "Program rail should stay below lifecycle controls.")
		_expect_false(debug_panel.get_global_rect().intersects(program_panel.get_global_rect()), "Collapsed Debug entry should stay above the Program rail.")
		_expect_true(program_panel.get_global_rect().position.x - sidebar.get_global_rect().end.x >= 400.0, "Supported desktop sizes should preserve central gameplay width.")

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

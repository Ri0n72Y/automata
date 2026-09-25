extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const GRID_DEBUG_VIEW_SCRIPT := preload("res://scripts/grid/grid_debug_view.gd")
const DEBUG_CONTROLS_SCRIPT := preload("res://scripts/scene_01/scene_01_debug_controls.gd")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for Debug UI smoke test.")
	if packed == null:
		_finish()
		return

	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame

	var debug_ui := scene.get_node_or_null("DebugUIRoot") as DEBUG_CONTROLS_SCRIPT
	var debug_view := scene.get_node_or_null(
		"SceneRoot/GridRoot/GridDebugView"
	) as GRID_DEBUG_VIEW_SCRIPT
	var debug_panel := scene.get_node_or_null("DebugUIRoot/RootControl/Panel") as Control
	var coordinates_row := scene.get_node_or_null(
		"DebugUIRoot/RootControl/Panel/Margin/VBox/CoordinatesRow"
	)

	_expect_true(debug_ui != null, "Scene 01 should contain the separate Debug UI.")
	_expect_true(debug_view != null, "Debug UI test requires GridDebugView.")
	_expect_true(debug_panel != null, "Debug UI should expose its disclosure panel.")
	_expect_true(coordinates_row == null, "Player-facing coordinates should not remain a Debug UI control.")
	if debug_ui == null or debug_view == null or debug_panel == null:
		await _finish_scene(scene)
		return

	_expect_true(
		debug_panel.size.x <= 140.0 and debug_panel.size.y <= 50.0,
		"Collapsed Debug entry should remain visually secondary to player controls."
	)
	_expect_false(debug_view.show_coordinates, "Legacy world-coordinate labels should remain disabled.")
	_expect_equal(debug_view.get_debug_label_count(), 0, "Disabled legacy coordinate labels should create no world text.")

	debug_ui.set_collapsed(false)
	await process_frame
	_expect_true(debug_ui.get_node_or_null("RootControl/Panel/Margin/VBox/RotateRow") != null, "Debug should retain grid transform tools.")
	debug_ui.set_collapsed(true)

	await _finish_scene(scene)


func _finish_scene(scene: Node) -> void:
	scene.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	if failures == 0:
		print("Scene 01 Debug UI smoke tests passed.")
		quit(0)
		return
	push_error("Scene 01 Debug UI smoke tests failed: %d failure(s)." % failures)
	quit(1)


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
	if not value:
		return
	failures += 1
	push_error(message)

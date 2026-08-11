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
	var coordinates_button := scene.get_node_or_null(
		"DebugUIRoot/RootControl/Panel/Margin/VBox/CoordinatesRow/CoordinatesButton"
	) as Button

	_expect_true(debug_ui != null, "Scene 01 should contain the separate Debug UI.")
	_expect_true(debug_view != null, "Debug UI test requires GridDebugView.")
	_expect_true(coordinates_button != null, "Debug UI should expose its coordinate toggle button.")
	if debug_ui == null or debug_view == null or coordinates_button == null:
		await _finish_scene(scene)
		return

	_expect_false(debug_view.show_coordinates, "Coordinates should start hidden.")
	_expect_equal(debug_view.get_debug_label_count(), 0, "Hidden coordinates should create no labels.")
	_expect_equal(coordinates_button.text, "显示场地坐标", "Debug button should initially offer to show coordinates.")

	debug_ui._on_coordinates_pressed()
	await process_frame
	_expect_true(debug_view.show_coordinates, "Debug button should enable coordinates.")
	_expect_equal(debug_view.get_debug_label_count(), 160, "Enabling coordinates should draw the 16 x 10 label set.")
	_expect_equal(coordinates_button.text, "隐藏场地坐标", "Debug button should switch to the hide action.")

	debug_ui._on_coordinates_pressed()
	await process_frame
	_expect_false(debug_view.show_coordinates, "Second Debug button press should hide coordinates.")
	_expect_equal(debug_view.get_debug_label_count(), 0, "Hiding coordinates should clear all labels.")
	_expect_equal(coordinates_button.text, "显示场地坐标", "Debug button should return to the show action.")

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

extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const SOURCE_HEADER := "automata_scene01_program 2\n"
const LayoutMetrics := preload("res://scripts/scene_01/scene_01_ui_layout_metrics.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for unified Program authoring test.")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var ui = scene.get_node("OperationsUIRoot")
	var selection = scene.get_node("SceneRoot/GridRoot/VehicleSelectionController")
	var manager = scene.get_node("SceneRoot/RobotRoot/Scene01VehicleManager")
	var panel := ui.get_node("%OperationsPanel") as Control
	var source_editor := ui.get_node("%SourceEditor") as CodeEdit
	var repeat_row := ui.get_node("%RepeatRow") as HBoxContainer
	var add_repeat := ui.get_node("%AddRepeatButton") as Button
	var clear_button := ui.get_node("%ClearButton") as Button
	var save_button := ui.get_node("%SaveButton") as Button
	var load_button := ui.get_node("%LoadButton") as Button
	var run_button := ui.get_node("%RunButton") as Button
	var repeat_count := ui.get_node("%RepeatCount") as SpinBox
	var repeat_target_option := ui.get_node("%RepeatTargetOption") as OptionButton
	var status_label := ui.get_node("%StatusLabel") as Label
	var authoring := ui.get_node("RootControl/OperationsPanel/Margin/VBox/ProgramAuthoring") as Control
	var sidebar_panel := scene.get_node("HUDRoot/RootControl/SidebarPanel") as Control
	var operations_root := ui.get_node("RootControl") as Control

	_expect_true(scene.get_node_or_null("ProgramUIRoot") == null, "Program authoring must not own a sibling panel.")
	_expect_true(source_editor != null, "Unified workspace should expose one canonical SourceEditor.")
	_expect_equal(ui.call("get_source_text"), SOURCE_HEADER, "Workspace should initialize from the scene-authored v2 source header.")
	_expect_equal(status_label.text, "语法有效 · 0 条语句", "Initial Program status should be serialized in the authoring scene.")
	_expect_true(not authoring.visible, "Program authoring should start collapsed inside Operations.")
	_expect_near(panel.size.x, LayoutMetrics.PRIMARY_RAIL_WIDTH, 2.0, "Default unified rail should preserve the 240px baseline.")
	_expect_true(operations_root.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Fullscreen presentation root must not intercept central gameplay input.")
	_expect_true(panel.mouse_filter == Control.MOUSE_FILTER_STOP, "Visible unified panel must stop clicks from leaking into gameplay.")

	ui.call("set_authoring_mode", true)
	await process_frame
	_expect_true(authoring.is_visible_in_tree(), "Explicit expand should reveal authoring content.")
	_expect_true(source_editor.is_visible_in_tree(), "Expanded unified rail should expose canonical source.")
	_expect_near(panel.size.x, LayoutMetrics.program_rail_width(float(scene.get_viewport().get_visible_rect().size.x)), 2.0, "Expanded authoring should reuse the established Program width tiers.")
	_expect_near(sidebar_panel.size.x, LayoutMetrics.PRIMARY_RAIL_WIDTH, 2.0, "Left rail should retain the shared 240px baseline.")
	_expect_true(repeat_row.is_visible_in_tree(), "Repeat remains a source-level Program tool without creating a second command palette.")
	_expect_true(ui.find_child("BuilderScroll", true, false) == null, "Legacy duplicate Program command builder should be removed.")
	_expect_true(ui.find_child("VehicleSelectionLabel", true, false) == null, "Vehicle selection presentation should remain on the unified Operations surface.")
	_expect_true(source_editor.get_parent() == authoring, "Canonical SourceEditor should live directly in embedded Program authoring content.")

	var arm = manager.call("get_vehicle_by_id", &"arm_vehicle")
	_expect_true(arm != null and selection.call("select_vehicle", arm), "Authoring test should select Arm through gameplay selection truth.")
	await process_frame

	ui.call("set_source_text", "automata_scene01_program 2\n[arm_vehicle:grabDrop]\n\n[arm_vehicle:grabDrop]\n")
	source_editor.set_caret_line(2)
	source_editor.set_caret_column(0)
	ui.get_node("%MoveButton").emit_signal("pressed")
	var inserted := String(ui.call("get_source_text"))
	_expect_true(inserted.find("[arm_vehicle:moveTo] 0 0") > inserted.find("[arm_vehicle:grabDrop]"), "Operations insertion should use the current canonical caret line.")
	_expect_true(inserted.find("[arm_vehicle:moveTo] 0 0") < inserted.rfind("[arm_vehicle:grabDrop]"), "Operations insertion should not append blindly to the end.")

	repeat_count.value = 2
	_expect_true(repeat_target_option.item_count > 0, "Repeat picker should derive legal targets from parsed canonical source.")
	add_repeat.emit_signal("pressed")
	_expect_true(String(ui.call("get_source_text")).contains("repeat 2 "), "Repeat should write directly into canonical source.")

	var valid_source := "automata_scene01_program 2\n[arm_vehicle:grabDrop]\n"
	ui.call("set_source_text", valid_source)
	_expect_equal(ui.call("get_source_text"), valid_source, "Direct typing API should replace canonical source exactly.")
	_expect_true(ui.call("get_program") != null, "Valid canonical source should produce a derived runtime snapshot.")
	_expect_true(status_label.text.contains("语法有效"), "Editor status should describe parser validity.")

	source_editor.grab_focus()
	await process_frame
	_expect_true(scene.get_viewport().gui_get_focus_owner() == source_editor, "SourceEditor should own focus before world-click regression.")
	var world_click := InputEventMouseButton.new()
	world_click.button_index = MOUSE_BUTTON_LEFT
	world_click.pressed = true
	world_click.position = Vector2(8, 8)
	Input.parse_input_event(world_click)
	await process_frame
	_expect_true(scene.get_viewport().gui_get_focus_owner() != source_editor, "A real world click outside the unified panel should release CodeEdit focus.")

	save_button.emit_signal("pressed")
	ui.call("set_source_text", SOURCE_HEADER)
	load_button.emit_signal("pressed")
	_expect_equal(ui.call("get_source_text"), valid_source, "Save/Load should round-trip the same canonical text buffer.")
	clear_button.emit_signal("pressed")
	_expect_equal(ui.call("get_source_text"), SOURCE_HEADER, "Clear All should return to deterministic header-only source.")
	_expect_true(ui.call("get_program") != null, "Header-only source should still parse to an empty runtime program.")

	ui.call("set_source_text", "automata_scene01_program 2\n[missing_vehicle:grabDrop]\n")
	run_button.emit_signal("pressed")
	_expect_true(status_label.text.contains("程序车辆不存在"), "Run should preserve existing Program preflight validation ownership.")

	ui.call("set_authoring_mode", false)
	await process_frame
	_expect_false(authoring.visible, "Collapse should hide Program authoring content.")
	_expect_near(panel.size.x, LayoutMetrics.PRIMARY_RAIL_WIDTH, 2.0, "Collapse should restore daily 240px Operations.")

	var save_path := ProjectSettings.globalize_path("user://scene_01_program.txt")
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	scene.queue_free()
	await process_frame
	_finish()


func _expect_true(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures += 1
		push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])


func _expect_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		failures += 1
		push_error("%s Expected %.2f ± %.2f, got %.2f." % [message, expected, tolerance, actual])


func _finish() -> void:
	if failures == 0:
		print("Scene 01 unified Program authoring tests passed.")
	quit(failures)

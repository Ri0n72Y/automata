extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const SOURCE_HEADER := "automata_scene01_program 2\n"

var failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for Program workspace test.")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var ui = scene.get_node("ProgramUIRoot")
	var hud = scene.get_node("HUDRoot") as CanvasLayer
	var program_panel := ui.get_node("RootControl/ProgramPanel") as Control
	var lifecycle_panel := scene.get_node("LifecycleUIRoot/RootControl/Panel") as Control
	var source_editor := ui.get_node("%SourceEditor") as CodeEdit
	var add_move := ui.get_node("%AddMoveButton") as Button
	var add_grab := ui.get_node("%AddGrabButton") as Button
	var add_repeat := ui.get_node("%AddRepeatButton") as Button
	var clear_button := ui.get_node("%ClearButton") as Button
	var save_button := ui.get_node("%SaveButton") as Button
	var load_button := ui.get_node("%LoadButton") as Button
	var run_button := ui.get_node("%RunButton") as Button
	var target_x := ui.get_node("%TargetX") as SpinBox
	var target_y := ui.get_node("%TargetY") as SpinBox
	var repeat_count := ui.get_node("%RepeatCount") as SpinBox
	var repeat_target_option := ui.get_node("%RepeatTargetOption") as OptionButton
	var status_label := ui.get_node("%StatusLabel") as Label
	var builder_body := ui.get_node("%BuilderBody") as Control
	var tutorial_panel := scene.get_node("TutorialUIRoot/RootControl/TutorialPanel") as Control
	var hud_panel := scene.get_node("HUDRoot/RootControl/StatusPanel") as Control
	var program_root := ui.get_node("RootControl") as Control
	var tutorial_root := scene.get_node("TutorialUIRoot/RootControl") as Control
	var hud_root := scene.get_node("HUDRoot/RootControl") as Control
	var manual_root := scene.get_node("UIRoot/RootControl") as Control
	_expect_true(source_editor != null, "Program workspace should expose one canonical SourceEditor.")
	_expect_equal(ui.call("get_source_text"), SOURCE_HEADER, "Workspace should initialize with only the v2 source header.")
	_expect_true(ui.find_child("ProgramList", true, false) == null, "Legacy mutable ProgramList should be removed.")
	_expect_true(ui.find_child("ConnectButton", true, false) == null, "Legacy graph Connect control should be removed.")
	_expect_true(ui.find_child("DeleteButton", true, false) == null, "Legacy graph Delete control should be removed.")
	_expect_true(add_move.get_parent() is VBoxContainer, "MoveTo add button should occupy its own VBox row.")
	_expect_true(add_grab.get_parent() is VBoxContainer, "GrabDrop add button should occupy its own VBox row.")
	_expect_true(add_repeat.get_parent() is VBoxContainer, "Repeat add button should occupy its own VBox row.")
	_expect_true(source_editor.get_parent() is VBoxContainer, "Canonical SourceEditor should be the primary single-column workspace content.")
	_expect_true(ui.find_child("Workspace", true, false) == null, "Legacy side-by-side workspace container should be removed.")
	_expect_true(bool(ui.call("is_workspace_collapsed")), "Program rail should start collapsed so gameplay remains visible.")
	_expect_true(not builder_body.visible, "Add Command should start collapsed behind its accordion.")
	_expect_true(program_panel.size.x <= 53.0, "Collapsed Program rail should stay near the 52px spec width.")
	ui.call("set_workspace_collapsed", false)
	await process_frame
	_expect_true(not bool(ui.call("is_workspace_collapsed")), "Program rail should expand on explicit player action.")
	_expect_true(source_editor.is_visible_in_tree(), "Expanded Program rail should expose the canonical source editor.")
	var viewport_width := float(scene.get_viewport().get_visible_rect().size.x)
	var expected_program_width := 520.0 if viewport_width >= 1920.0 else (440.0 if viewport_width >= 1600.0 else 420.0)
	var expected_left_width := clampf(viewport_width * 0.2, 300.0, 360.0)
	_expect_true(absf(program_panel.size.x - expected_program_width) <= 2.0, "Expanded Program rail should follow the desktop width tier.")
	_expect_true(tutorial_panel.size.x <= expected_left_width + 2.0 and hud_panel.size.x <= expected_left_width + 2.0, "Left-rail panels should follow the same bounded viewport-width formula.")
	var central_width := program_panel.get_global_rect().position.x - (tutorial_panel.get_global_rect().position.x + tutorial_panel.get_global_rect().size.x)
	_expect_true(central_width > 0.0, "Program and left rails must leave a non-overlapping central gameplay region.")
	_expect_true(not tutorial_panel.get_global_rect().intersects(hud_panel.get_global_rect()), "Tutorial and HUD must occupy separate vertical slots in the left rail.")
	_expect_true(program_root.mouse_filter == Control.MOUSE_FILTER_IGNORE and tutorial_root.mouse_filter == Control.MOUSE_FILTER_IGNORE and hud_root.mouse_filter == Control.MOUSE_FILTER_IGNORE and manual_root.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Fullscreen presentation roots must not intercept central gameplay input.")
	ui.call("set_command_builder_expanded", true)
	_expect_true(bool(ui.call("is_command_builder_expanded")) and builder_body.visible, "Add Command should expand only inside Program UI presentation state.")
	_expect_true(not program_panel.get_global_rect().intersects(lifecycle_panel.get_global_rect()), "Program workspace must not cover lifecycle controls.")
	_expect_true((ui as CanvasLayer).layer < hud.layer, "HUD completion results must render above the Program workspace.")
	target_x.value = 4
	target_y.value = 5
	add_move.emit_signal("pressed")
	_expect_true(String(ui.call("get_source_text")).contains("[arm_vehicle:moveTo] 4 5\n"), "Add MoveTo should write directly into source.")
	add_grab.emit_signal("pressed")
	_expect_true(String(ui.call("get_source_text")).contains("[arm_vehicle:grabDrop]\n"), "Add GrabDrop should write directly into source.")
	repeat_count.value = 2
	_expect_equal(int(repeat_target_option.get_item_metadata(0)), 1, "First Repeat target should use the first source statement number.")
	add_repeat.emit_signal("pressed")
	_expect_true(String(ui.call("get_source_text")).contains("repeat 2 1\n"), "Add Repeat should write the selected source statement number.")
	_expect_true(ui.call("get_program") != null, "Valid edited source should produce a runtime snapshot.")
	_expect_true(add_repeat.disabled, "After a Repeat, UI must require a new vehicle command before another Repeat can be added.")
	var numbered_source := """automata_scene01_program 2
[arm_vehicle:moveTo] 1 3
repeat 2 1
[transport_vehicle:moveTo] 8 4
"""
	ui.call("set_source_text", numbered_source)
	_expect_equal(repeat_target_option.item_count, 1, "Repeat picker should exclude targets whose range would contain an earlier Repeat.")
	_expect_equal(int(repeat_target_option.get_item_metadata(0)), 3, "Only the vehicle command after the latest Repeat should remain a legal target.")
	var valid_source := "automata_scene01_program 2\n[transport_vehicle:moveTo] 8 4\n"
	ui.call("set_source_text", valid_source)
	_expect_equal(ui.call("get_source_text"), valid_source, "Direct typing API should replace the canonical source exactly.")
	_expect_true(ui.call("get_program") != null, "Directly typed valid source should parse.")
	_expect_true(status_label.text.contains("语法有效"), "Editor status should describe parser validity without claiming full Program validation.")
	var exposed_program := ui.call("get_program") as Scene01Program
	_expect_true(exposed_program != null, "Workspace accessor should expose a snapshot copy.")
	if exposed_program != null:
		exposed_program.set_statement_vehicle(0, &"arm_vehicle")
	var fresh_program := ui.call("get_program") as Scene01Program
	_expect_true(fresh_program != null, "Workspace should retain its derived snapshot after external copy mutation.")
	if fresh_program != null:
		_expect_equal(StringName(fresh_program.get_statement(0).get("vehicle_id", &"")), &"transport_vehicle", "External snapshot mutation must not change the workspace-derived Program.")
	_expect_equal(ui.call("get_source_text"), valid_source, "External snapshot mutation must not change canonical source.")
	ui.call("set_source_text", "automata_scene01_program 2\n[arm_vehicle:moveTo] x 4\n")
	_expect_true(ui.call("get_program") == null, "Invalid text must not leave a stale mutable Program snapshot.")
	_expect_true(status_label.text.contains("第 2 行"), "Syntax diagnostics should identify the physical source line.")
	var semantic_source := "automata_scene01_program 2\n\n# comment\n\n[arm_vehicle:moveTo] 1 3\nrepeat 0 1\n"
	ui.call("set_source_text", semantic_source)
	_expect_true(ui.call("get_program") != null, "Semantic fixture should remain syntactically parseable.")
	_expect_true(status_label.text.contains("语法有效"), "Semantic-invalid text should only be labeled syntax-valid before Run validation.")
	run_button.emit_signal("pressed")
	_expect_true(status_label.text.contains("第 6 行"), "Validator rejection should map statement index back to physical source line.")
	_expect_true(status_label.text.contains("Repeat"), "Semantic failure should preserve the useful rejection reason.")
	var missing_vehicle_source := "automata_scene01_program 2\n\n# typo\n[missing_vehicle:grabDrop]\n"
	ui.call("set_source_text", missing_vehicle_source)
	run_button.emit_signal("pressed")
	_expect_true(status_label.text.contains("第 4 行"), "Preflight vehicle rejection should map statement index back to physical source line.")
	_expect_true(status_label.text.contains("程序车辆不存在"), "Preflight vehicle rejection should preserve the useful reason.")
	ui.call("set_source_text", valid_source)
	save_button.emit_signal("pressed")
	ui.call("set_source_text", SOURCE_HEADER)
	load_button.emit_signal("pressed")
	_expect_equal(ui.call("get_source_text"), valid_source, "Save/Load should round-trip the same canonical text buffer.")
	clear_button.emit_signal("pressed")
	_expect_equal(ui.call("get_source_text"), SOURCE_HEADER, "Clear All should return to the deterministic header-only source.")
	_expect_true(ui.call("get_program") != null, "Header-only source should still parse to an empty runtime program.")
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
func _finish() -> void:
	if failures == 0:
		print("Scene 01 Program workspace tests passed.")
	quit(failures)

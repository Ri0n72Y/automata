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
	var source_editor := ui.get_node("%SourceEditor") as CodeEdit
	var add_move := ui.get_node("%AddMoveButton") as Button
	var add_grab := ui.get_node("%AddGrabButton") as Button
	var add_repeat := ui.get_node("%AddRepeatButton") as Button
	var clear_button := ui.get_node("%ClearButton") as Button
	var save_button := ui.get_node("%SaveButton") as Button
	var load_button := ui.get_node("%LoadButton") as Button
	var target_x := ui.get_node("%TargetX") as SpinBox
	var target_y := ui.get_node("%TargetY") as SpinBox
	var repeat_count := ui.get_node("%RepeatCount") as SpinBox
	var repeat_target := ui.get_node("%RepeatTarget") as SpinBox
	var status_label := ui.get_node("%StatusLabel") as Label

	_expect_true(source_editor != null, "Program workspace should expose one canonical SourceEditor.")
	_expect_equal(ui.call("get_source_text"), SOURCE_HEADER, "Workspace should initialize with only the v2 source header.")
	_expect_true(ui.find_child("ProgramList", true, false) == null, "Legacy mutable ProgramList should be removed.")
	_expect_true(ui.find_child("ConnectButton", true, false) == null, "Legacy graph Connect control should be removed.")
	_expect_true(ui.find_child("DeleteButton", true, false) == null, "Legacy graph Delete control should be removed.")
	_expect_true(add_move.get_parent() is VBoxContainer, "MoveTo add button should occupy its own VBox row.")
	_expect_true(add_grab.get_parent() is VBoxContainer, "GrabDrop add button should occupy its own VBox row.")
	_expect_true(add_repeat.get_parent() is VBoxContainer, "Repeat add button should occupy its own VBox row.")

	target_x.value = 4
	target_y.value = 5
	add_move.emit_signal("pressed")
	_expect_true(String(ui.call("get_source_text")).contains("[arm_vehicle:moveTo] 4 5\n"), "Add MoveTo should write directly into source.")
	add_grab.emit_signal("pressed")
	_expect_true(String(ui.call("get_source_text")).contains("[arm_vehicle:grabDrop]\n"), "Add GrabDrop should write directly into source.")
	repeat_count.value = 2
	repeat_target.value = 1
	add_repeat.emit_signal("pressed")
	_expect_true(String(ui.call("get_source_text")).contains("repeat 2 1\n"), "Add Repeat should write directly into source.")
	_expect_true(ui.call("get_program") != null, "Valid edited source should produce a runtime snapshot.")

	var valid_source := "automata_scene01_program 2\n[transport_vehicle:moveTo] 8 4\n"
	ui.call("set_source_text", valid_source)
	_expect_equal(ui.call("get_source_text"), valid_source, "Direct typing API should replace the canonical source exactly.")
	_expect_true(ui.call("get_program") != null, "Directly typed valid source should parse.")

	ui.call("set_source_text", "automata_scene01_program 2\n[arm_vehicle:moveTo] x 4\n")
	_expect_true(ui.call("get_program") == null, "Invalid text must not leave a stale mutable Program snapshot.")
	_expect_true(status_label.text.contains("第 2 行"), "Source diagnostics should identify the physical source line.")

	ui.call("set_source_text", valid_source)
	save_button.emit_signal("pressed")
	ui.call("set_source_text", SOURCE_HEADER)
	load_button.emit_signal("pressed")
	_expect_equal(ui.call("get_source_text"), valid_source, "Save/Load should round-trip the same canonical text buffer.")

	clear_button.emit_signal("pressed")
	_expect_equal(ui.call("get_source_text"), SOURCE_HEADER, "Clear All should return to the deterministic header-only source.")
	var cleared_program = ui.call("get_program")
	_expect_true(cleared_program != null, "Header-only source should still parse to an empty runtime program.")

	var save_path := ProjectSettings.globalize_path("user://scene_01_program.txt")
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)

	scene.queue_free()
	await process_frame
	_finish()


func _expect_true(value: bool, message: String) -> void:
	if value:
		return
	failures += 1
	push_error(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	failures += 1
	push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])


func _finish() -> void:
	if failures == 0:
		print("Scene 01 Program workspace tests passed.")
	quit(failures)

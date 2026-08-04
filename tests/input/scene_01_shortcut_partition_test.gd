extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const CAMERA_RIG := preload("res://scripts/camera/scene_01_camera_rig.gd")
const MANUAL_CONTROLS := preload("res://scripts/scene_01/scene_01_manual_controls.gd")
const CONTRACT := preload("res://tests/support/contract_test.gd")

var test := CONTRACT.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := (load(SCENE_PATH) as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var rig := scene.get_node_or_null("SceneRoot/CameraRoot/Scene01CameraRig") as CAMERA_RIG
	var controls := scene.get_node_or_null("UIRoot") as MANUAL_CONTROLS
	var grid_root := scene.get_node_or_null("SceneRoot/GridRoot") as Node3D
	test.expect_true(rig != null and controls != null and grid_root != null, "Shortcut dependencies should exist.")
	if rig != null and controls != null and grid_root != null:
		_test_action_registration()
		_test_shift_partition(scene, rig, controls, grid_root)
		await _test_camera_key_event_boundaries(scene, rig)
	current_scene = null
	scene.queue_free()
	await process_frame
	test.finish(self, "Scene 01 shortcut partition tests")


func _test_action_registration() -> void:
	test.expect_true(InputMap.has_action(CAMERA_RIG.ROTATE_CLOCKWISE_ACTION), "Clockwise action should exist.")
	test.expect_true(InputMap.has_action(CAMERA_RIG.ROTATE_COUNTERCLOCKWISE_ACTION), "Counterclockwise action should exist.")


func _test_shift_partition(scene: Node, rig, controls, grid_root: Node3D) -> void:
	scene.call("preview_restore_grid_transform")
	rig.set_view_direction(CAMERA_RIG.ViewDirection.SOUTHEAST, false)
	var restored_basis := grid_root.basis
	controls._unhandled_key_input(_key(KEY_Q, true, false))
	test.expect_true(grid_root.basis.is_equal_approx(restored_basis), "Plain Q should not rotate GridRoot.")

	scene.call("preview_rotate_grid", 1)
	var positive_basis := grid_root.basis
	scene.call("preview_restore_grid_transform")
	controls._unhandled_key_input(_key(KEY_Q, true, false, true))
	test.expect_true(grid_root.basis.is_equal_approx(positive_basis), "Shift+Q should rotate GridRoot +90 degrees.")
	test.expect_equal(rig.get_view_direction(), CAMERA_RIG.ViewDirection.SOUTHEAST, "Shift+Q should preserve camera direction.")

	scene.call("preview_restore_grid_transform")
	scene.call("preview_rotate_grid", -1)
	var negative_basis := grid_root.basis
	scene.call("preview_restore_grid_transform")
	controls._unhandled_key_input(_key(KEY_E, true, false, true))
	test.expect_true(grid_root.basis.is_equal_approx(negative_basis), "Shift+E should rotate GridRoot -90 degrees.")
	scene.call("preview_restore_grid_transform")


func _test_camera_key_event_boundaries(scene: Node, rig) -> void:
	rig.set_view_direction(CAMERA_RIG.ViewDirection.SOUTHEAST, false)
	var emitted: Array[int] = []
	rig.view_direction_changed.connect(func(direction: int) -> void: emitted.append(direction))
	rig._unhandled_input(_key(KEY_Q, true, false))
	test.expect_equal(rig.get_view_direction(), CAMERA_RIG.ViewDirection.SOUTHWEST, "Pressed Q should rotate clockwise.")
	test.expect_equal(emitted, [CAMERA_RIG.ViewDirection.SOUTHWEST], "Pressed Q should emit one direction change.")

	var ignored_events := [
		_key(KEY_Q, false, false),
		_key(KEY_Q, true, true),
		_key(KEY_Q, true, false, true),
	]
	for event in ignored_events:
		rig._unhandled_input(event)
	test.expect_equal(rig.get_view_direction(), CAMERA_RIG.ViewDirection.SOUTHWEST, "Release, echo, and Shift+Q should not add camera turns.")
	await create_timer(maxf(rig.rotation_duration * 1.1, 0.32)).timeout

	for text_control in [LineEdit.new(), TextEdit.new(), CodeEdit.new()]:
		text_control.focus_mode = Control.FOCUS_ALL
		scene.add_child(text_control)
		text_control.grab_focus()
		await process_frame
		var direction_before := rig.get_view_direction()
		var signals_before := emitted.size()
		rig._unhandled_input(_key(KEY_Q, true, false))
		rig._unhandled_input(_key(KEY_E, true, false))
		test.expect_equal(rig.get_view_direction(), direction_before, "Focused %s should block camera shortcuts." % text_control.get_class())
		test.expect_equal(emitted.size(), signals_before, "Focused %s should emit no direction changes." % text_control.get_class())
		text_control.release_focus()
		text_control.queue_free()
		await process_frame

	rig._unhandled_input(_key(KEY_E, true, false))
	test.expect_equal(rig.get_view_direction(), CAMERA_RIG.ViewDirection.SOUTHEAST, "E should rotate counterclockwise after focus release.")
	test.expect_equal(emitted.size(), 2, "E should emit one additional direction change.")


func _key(keycode: Key, pressed: bool, echo: bool, shift_pressed: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	event.echo = echo
	event.shift_pressed = shift_pressed
	return event

extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for lifecycle UI contract.")
	if packed == null:
		_finish()
		return

	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame

	var lifecycle_ui := scene.get_node_or_null("LifecycleUIRoot")
	var panel := lifecycle_ui.get_node_or_null("%Panel") as PanelContainer if lifecycle_ui != null else null
	var dot := lifecycle_ui.get_node_or_null("%StatusDot") as TextureRect if lifecycle_ui != null else null
	var state := lifecycle_ui.get_node_or_null("%StateLabel") as Label if lifecycle_ui != null else null
	var time := lifecycle_ui.get_node_or_null("%TimeLabel") as Label if lifecycle_ui != null else null
	var speed := lifecycle_ui.get_node_or_null("%SpeedOption") as OptionButton if lifecycle_ui != null else null
	var group := lifecycle_ui.get_node_or_null("%RunResetGroup") as PanelContainer if lifecycle_ui != null else null
	var run := lifecycle_ui.get_node_or_null("%RunPauseButton") as Button if lifecycle_ui != null else null
	var reset := lifecycle_ui.get_node_or_null("%ResetButton") as Button if lifecycle_ui != null else null

	_expect_true(
		panel != null and dot != null and state != null and time != null and speed != null
		and group != null and run != null and reset != null,
		"Lifecycle capsule should expose its stable unique-name component contract."
	)
	if panel == null or dot == null or speed == null or group == null or run == null or reset == null:
		await _cleanup(scene)
		return

	_expect_true(panel.size.x <= 354.0 and panel.size.y <= 44.0, "Lifecycle capsule should stay within the compact design envelope.")
	var capsule_style := panel.get_theme_stylebox("panel") as StyleBoxFlat
	var group_style := group.get_theme_stylebox("panel") as StyleBoxFlat
	_expect_true(capsule_style != null and capsule_style.shadow_size >= 6, "Lifecycle capsule boundary should come from a soft shadow.")
	_expect_true(group_style != null and group_style.shadow_size >= 2, "Run/Reset group should use a lighter nested shadow.")
	_expect_true(_has_zero_border(capsule_style), "Lifecycle capsule should not use a hard border.")
	_expect_true(_has_zero_border(group_style), "Run/Reset group should not use a hard border.")
	_expect_true(run.get_parent() == reset.get_parent(), "Play/Pause and Reset should share one compact control row.")
	_expect_true(run.text.is_empty() and reset.text.is_empty(), "Lifecycle actions should use icons instead of font glyphs.")
	_expect_true(run.icon != null and reset.icon != null, "Lifecycle action SVG icons should be present.")
	if run.icon != null:
		_expect_equal(run.icon.get_class(), "DPITexture", "Play/Pause icon should import as DPITexture.")
	if reset.icon != null:
		_expect_equal(reset.icon.get_class(), "DPITexture", "Reset icon should import as DPITexture.")
	_expect_equal(dot.size_flags_vertical, Control.SIZE_SHRINK_CENTER, "Status dot should stay vertically centered without stretching.")
	_expect_equal(dot.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "Status dot should preserve its circular aspect ratio.")
	_expect_true(dot.custom_minimum_size.x >= 12.0, "Status dot should keep the reference visual size.")
	_expect_true(not speed.fit_to_longest_item, "Speed selector should stay compact.")
	_expect_true(speed.get_theme_stylebox("normal").content_margin_left >= 8.0, "Speed selector should keep 8px left padding.")
	_expect_true(speed.get_theme_stylebox("normal").content_margin_right >= 8.0, "Speed selector should keep 8px right padding.")
	_expect_true(run.size.x <= 30.0 and reset.size.x <= 30.0, "Hover visuals should remain inset from the outer control group.")

	await _cleanup(scene)


func _has_zero_border(style: StyleBoxFlat) -> bool:
	return (
		style != null
		and style.border_width_left == 0
		and style.border_width_top == 0
		and style.border_width_right == 0
		and style.border_width_bottom == 0
	)


func _cleanup(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	_finish()


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


func _finish() -> void:
	if failures == 0:
		print("Scene 01 lifecycle UI contract tests passed.")
	quit(failures)

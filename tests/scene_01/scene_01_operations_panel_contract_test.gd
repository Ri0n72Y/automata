extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const AvailabilityScript := preload("res://scripts/input/vehicle_command_availability.gd")
const ManualAvailabilityScript := preload("res://scripts/input/vehicle_manual_interaction_availability.gd")
const LayoutMetrics := preload("res://scripts/scene_01/scene_01_ui_layout_metrics.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for unified right-rail contract.")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var operations := scene.get_node_or_null("OperationsUIRoot")
	var panel := operations.get_node_or_null("%OperationsPanel") as PanelContainer if operations != null else null
	var vehicle_label := operations.get_node_or_null("%VehicleLabel") as Label if operations != null else null
	var move_row := operations.get_node_or_null("%MoveRow") as Control if operations != null else null
	var move_status := operations.get_node_or_null("%MoveStatus") as Label if operations != null else null
	var move_button := operations.get_node_or_null("%MoveButton") as Button if operations != null else null
	var rotate_row := operations.get_node_or_null("%RotateRow") as Control if operations != null else null
	var rotate_status := operations.get_node_or_null("%RotateStatus") as Label if operations != null else null
	var rotate_left := operations.get_node_or_null("%RotateLeftButton") as Button if operations != null else null
	var rotate_right := operations.get_node_or_null("%RotateRightButton") as Button if operations != null else null
	var grab_row := operations.get_node_or_null("%GrabDropRow") as Control if operations != null else null
	var grab_status := operations.get_node_or_null("%GrabDropStatus") as Label if operations != null else null
	var grab_button := operations.get_node_or_null("%GrabDropButton") as Button if operations != null else null
	var authoring := operations.get_node_or_null("RootControl/OperationsPanel/Margin/VBox/ProgramAuthoring") as Control if operations != null else null
	var mode_button := operations.get_node_or_null("%AuthoringModeButton") as Button if operations != null else null
	var selection := scene.get_node("SceneRoot/GridRoot/VehicleSelectionController")
	var move_controller := scene.get_node("SceneRoot/GridRoot/VehicleMoveController")
	var grab_controller := scene.get_node("SceneRoot/GridRoot/VehicleGrabDropController")
	var grid_selection := scene.get_node("SceneRoot/GridRoot/GridSelectionController")
	var manager := scene.get_node("SceneRoot/RobotRoot/Scene01VehicleManager")

	_expect_true(
		panel != null and vehicle_label != null and move_row != null and move_status != null and move_button != null
		and rotate_row != null and rotate_status != null and rotate_left != null and rotate_right != null
		and grab_row != null and grab_status != null and grab_button != null and authoring != null and mode_button != null,
		"Unified right rail should expose one stable static presentation contract."
	)
	if panel == null or move_button == null or rotate_left == null or rotate_right == null or grab_button == null:
		await _cleanup(scene)
		return

	_expect_true(scene.get_node_or_null("ProgramUIRoot") == null, "Scene 01 must not keep a sibling Program panel.")
	_expect_false(bool(operations.call("is_authoring_mode")), "Operations must remain the default right-rail mode.")
	_expect_false(authoring.visible, "Program authoring content should start hidden inside the unified panel.")
	_expect_near(panel.size.x, LayoutMetrics.PRIMARY_RAIL_WIDTH, 1.0, "Default Operations should preserve the shared 240px primary rail width.")
	_expect_true(panel.get_combined_minimum_size().x <= LayoutMetrics.PRIMARY_RAIL_WIDTH + 1.0, "Default Operations child minimum width must fit inside the primary rail.")
	_assert_horizontal_fit(panel, [vehicle_label, move_row, move_status, move_button, rotate_row, rotate_status, rotate_left, rotate_right, grab_row, grab_status, grab_button])

	_expect_equal(vehicle_label.text, "当前车辆 · 未选择", "No-selection state should not invent a default vehicle.")
	_expect_true(move_button.disabled and rotate_left.disabled and rotate_right.disabled and grab_button.disabled, "No-selection state should disable every operation tool.")

	var arm = manager.call("get_vehicle_by_id", &"arm_vehicle")
	_expect_true(arm != null and selection.call("select_vehicle", arm), "Contract should select Arm through VehicleSelectionController.")
	await process_frame
	_expect_true(vehicle_label.text.contains("机械臂车"), "Unified rail should project selected Arm.")
	var arm_panel_height := panel.size.y
	_expect_true(grab_row.visible, "Arm should expose supported GrabDrop.")
	_assert_manual_projection(move_controller, grab_controller, move_button, rotate_left, rotate_right, grab_button)

	var move_availability := StringName(move_controller.call("get_selected_move_interaction_availability"))
	if move_availability == AvailabilityScript.AVAILABLE:
		move_button.emit_signal("pressed")
		await process_frame
		_expect_true(bool(grid_selection.call("is_live_target_mode")), "Default Move should still use the existing gameplay targeting entrypoint.")
		move_button.emit_signal("pressed")
		await process_frame
		_expect_false(bool(grid_selection.call("is_live_target_mode")), "Default Move should still cancel through the same gameplay owner.")

	operations.call("set_authoring_mode", true)
	await process_frame
	_expect_true(bool(operations.call("is_authoring_mode")), "Expand should enter authoring mode on the same right-rail owner.")
	_expect_true(authoring.is_visible_in_tree(), "Program authoring content should become visible inside the same panel.")
	_expect_true(panel.size.x > LayoutMetrics.PRIMARY_RAIL_WIDTH, "Authoring mode may widen the same panel without creating another rail.")
	_expect_near(panel.get_global_rect().end.y, float(scene.get_viewport().get_visible_rect().size.y) - LayoutMetrics.CONTENT_BOTTOM_MARGIN, 1.0, "Authoring mode should consume bounded vertical workspace.")
	_expect_equal(move_button.text, "插入", "Move surface should switch from gameplay execution to source insertion.")
	_expect_equal(grab_button.text, "插入", "GrabDrop surface should switch from gameplay execution to source insertion.")

	var source_editor := authoring.get_node("%SourceEditor") as CodeEdit
	_expect_true(source_editor != null, "Unified panel should contain the one canonical CodeEdit source.")
	operations.call("set_source_text", "automata_scene01_program 2\n[arm_vehicle:grabDrop]\n\n")
	source_editor.set_caret_line(2)
	source_editor.set_caret_column(0)
	var source_before_move := String(operations.call("get_source_text"))
	var anchor_before_move: Vector2i = arm.runtime_state.anchor_cell
	var move_requests: Array[Vector2i] = []
	move_controller.move_requested.connect(
		func(_vehicle_id: StringName, target: Vector2i) -> void:
			move_requests.append(target)
	)
	move_button.emit_signal("pressed")
	await process_frame
	_expect_true(bool(grid_selection.call("is_live_target_mode")), "Authoring Move should enter the existing live target selector.")
	_expect_equal(String(operations.call("get_source_text")), source_before_move, "Authoring Move should not insert source before target confirmation.")
	_expect_equal(move_button.text, "取消目标", "Authoring Move should expose target cancellation while selection is active.")

	var authored_target := anchor_before_move + Vector2i(1, 0)
	grid_selection.set("selected_cell", authored_target)
	_expect_true(bool(grid_selection.call("confirm_selection")), "Authoring Move target should confirm through GridSelectionController.")
	await process_frame
	var expected_move := "[arm_vehicle:moveTo] %d %d" % [authored_target.x, authored_target.y]
	var source_after_move := String(operations.call("get_source_text"))
	_expect_true(source_after_move.contains(expected_move + "\n"), "Authoring Move should insert the confirmed selected target coordinate.")
	_expect_true(source_after_move.find(expected_move) > source_after_move.find("[arm_vehicle:grabDrop]"), "Insertion should remain relative to the original source caret.")
	_expect_equal(move_requests.size(), 0, "Authoring Move confirmation must not invoke gameplay Move.")
	_expect_equal(arm.runtime_state.anchor_cell, anchor_before_move, "Authoring Move confirmation must not mutate vehicle runtime position.")
	_expect_false(bool(grid_selection.call("is_live_target_mode")), "Authoring Move confirmation should finish target-selection mode.")

	var source_before_cancel := String(operations.call("get_source_text"))
	move_button.emit_signal("pressed")
	await process_frame
	_expect_true(bool(grid_selection.call("is_live_target_mode")), "Second Authoring Move should re-enter target selection.")
	move_button.emit_signal("pressed")
	await process_frame
	_expect_false(bool(grid_selection.call("is_live_target_mode")), "Authoring Move button should cancel pending target selection.")
	_expect_equal(String(operations.call("get_source_text")), source_before_cancel, "Cancelling Authoring Move must insert nothing.")

	rotate_right.emit_signal("pressed")
	grab_button.emit_signal("pressed")
	var authored := String(operations.call("get_source_text"))
	_expect_true(authored.contains("[arm_vehicle:rotate] clockwise\n"), "Authoring Rotate should write canonical source without executing gameplay.")
	_expect_true(authored.contains("[arm_vehicle:grabDrop]\n"), "Authoring GrabDrop should write canonical source.")
	_expect_false(bool(arm.call("is_turning")), "Authoring Rotate must not reuse the manual execution path.")

	scene.call("reset_scene")
	await process_frame
	var transport = manager.call("get_vehicle_by_id", &"transport_vehicle")
	_expect_true(transport != null and selection.call("select_vehicle", transport), "Contract should select Transport through VehicleSelectionController.")
	await process_frame
	_expect_false(grab_row.visible, "Authoritative NO_CAPABILITY should hide unsupported GrabDrop in both modes.")
	_expect_true(move_row.visible and rotate_row.visible, "Supported Transport tools should remain visible.")

	move_button.emit_signal("pressed")
	await process_frame
	_expect_true(bool(grid_selection.call("is_live_target_mode")), "Pending Authoring Move should be active before collapse.")
	operations.call("set_authoring_mode", false)
	await process_frame
	_expect_false(bool(grid_selection.call("is_live_target_mode")), "Collapsing Program should cancel pending Authoring Move targeting.")
	_expect_false(authoring.visible, "Collapse should restore daily Operations presentation.")
	_expect_near(panel.size.x, LayoutMetrics.PRIMARY_RAIL_WIDTH, 1.0, "Collapse should restore the accepted 240px baseline.")
	_expect_true(panel.size.y < float(scene.get_viewport().get_visible_rect().size.y) - LayoutMetrics.CONTENT_TOP, "Collapsed daily Operations should return to natural content height.")
	_expect_true(panel.size.y < arm_panel_height, "Transport daily Operations should still shrink when unsupported rows are hidden.")
	_expect_true(panel.mouse_filter == Control.MOUSE_FILTER_STOP, "Unified surface must stop pointer clicks from leaking into gameplay.")

	await _cleanup(scene)


func _assert_horizontal_fit(panel: Control, controls: Array) -> void:
	var panel_rect := panel.get_global_rect()
	for control_variant in controls:
		var control := control_variant as Control
		if control == null or not control.is_visible_in_tree():
			continue
		var rect := control.get_global_rect()
		_expect_true(
			rect.position.x >= panel_rect.position.x - 1.0
			and rect.end.x <= panel_rect.end.x + 1.0,
			"Visible Operations controls must stay inside the default 240px panel width."
		)


func _assert_manual_projection(move_controller: Node, grab_controller: Node, move_button: Button, rotate_left: Button, rotate_right: Button, grab_button: Button) -> void:
	var move_status := StringName(move_controller.call("get_selected_move_interaction_availability"))
	var rotate_status := StringName(grab_controller.call("get_selected_rotate_interaction_availability"))
	var grab_status := StringName(grab_controller.call("get_selected_grab_drop_interaction_availability"))
	_expect_equal(move_button.disabled, not _move_actionable(move_status), "Manual Move enablement should directly project interaction availability.")
	_expect_equal(rotate_left.disabled, rotate_status != AvailabilityScript.AVAILABLE, "Manual Rotate enablement should directly project interaction availability.")
	_expect_equal(rotate_right.disabled, rotate_status != AvailabilityScript.AVAILABLE, "Manual Rotate enablement should directly project interaction availability.")
	_expect_equal(grab_button.disabled, grab_status != AvailabilityScript.AVAILABLE, "Manual GrabDrop enablement should directly project interaction availability.")


func _move_actionable(status: StringName) -> bool:
	return status == AvailabilityScript.AVAILABLE or status == AvailabilityScript.BLOCKED or status == ManualAvailabilityScript.TARGETING


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
		print("Scene 01 unified right-rail contract tests passed.")
	quit(failures)

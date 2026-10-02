extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const AvailabilityScript := preload("res://scripts/input/vehicle_command_availability.gd")
const ManualAvailabilityScript := preload("res://scripts/input/vehicle_manual_interaction_availability.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for Operations Panel contract.")
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
	var move_status := operations.get_node_or_null("%MoveStatus") as Label if operations != null else null
	var move_button := operations.get_node_or_null("%MoveButton") as Button if operations != null else null
	var rotate_status := operations.get_node_or_null("%RotateStatus") as Label if operations != null else null
	var rotate_left := operations.get_node_or_null("%RotateLeftButton") as Button if operations != null else null
	var rotate_right := operations.get_node_or_null("%RotateRightButton") as Button if operations != null else null
	var grab_status := operations.get_node_or_null("%GrabDropStatus") as Label if operations != null else null
	var grab_button := operations.get_node_or_null("%GrabDropButton") as Button if operations != null else null
	var selection := scene.get_node("SceneRoot/GridRoot/VehicleSelectionController")
	var move_controller := scene.get_node("SceneRoot/GridRoot/VehicleMoveController")
	var grab_controller := scene.get_node("SceneRoot/GridRoot/VehicleGrabDropController")
	var grid_selection := scene.get_node("SceneRoot/GridRoot/GridSelectionController")
	var manager := scene.get_node("SceneRoot/RobotRoot/Scene01VehicleManager")

	_expect_true(
		panel != null and vehicle_label != null and move_status != null and move_button != null
		and rotate_status != null and rotate_left != null and rotate_right != null
		and grab_status != null and grab_button != null,
		"Operations Panel should expose one stable static presentation contract."
	)
	if panel == null or move_button == null or rotate_left == null or rotate_right == null or grab_button == null:
		await _cleanup(scene)
		return

	_expect_equal(vehicle_label.text, "当前车辆 · 未选择", "No-selection state should not invent a default vehicle.")
	_expect_equal(StringName(move_controller.call("get_selected_move_interaction_availability")), AvailabilityScript.NO_VEHICLE, "Move owner should report no vehicle.")
	_expect_equal(StringName(grab_controller.call("get_selected_rotate_interaction_availability")), AvailabilityScript.NO_VEHICLE, "Rotate owner should report no vehicle.")
	_expect_equal(StringName(grab_controller.call("get_selected_grab_drop_interaction_availability")), AvailabilityScript.NO_VEHICLE, "GrabDrop owner should report no vehicle.")
	_expect_true(move_button.disabled and rotate_left.disabled and rotate_right.disabled and grab_button.disabled, "No-selection state should disable every manual action.")

	var arm = manager.call("get_vehicle_by_id", &"arm_vehicle")
	_expect_true(arm != null and selection.call("select_vehicle", arm), "Operations contract should select Arm through VehicleSelectionController.")
	await process_frame
	_expect_true(vehicle_label.text.contains("机械臂车"), "Operations vehicle label should project the selected Arm.")
	_assert_projection(move_controller, grab_controller, move_button, rotate_left, rotate_right, grab_button)

	var move_availability := StringName(move_controller.call("get_selected_move_interaction_availability"))
	if move_availability == AvailabilityScript.AVAILABLE:
		move_button.emit_signal("pressed")
		await process_frame
		_expect_true(bool(grid_selection.call("is_live_target_mode")), "Move button should enter the existing grid target interaction.")
		_expect_equal(StringName(move_controller.call("get_selected_move_interaction_availability")), ManualAvailabilityScript.TARGETING, "Move controller should remain the targeting truth.")
		_expect_equal(move_status.text, "选择目标中", "Operations should present targeting without rebuilding target state.")
		_expect_false(move_button.disabled, "Targeting Move button should remain actionable so the existing interaction can be cancelled.")
		_expect_true(rotate_left.disabled and rotate_right.disabled and grab_button.disabled, "Other operations should follow their TARGETING interaction availability.")
		move_button.emit_signal("pressed")
		await process_frame
		_expect_false(bool(grid_selection.call("is_live_target_mode")), "Move button should cancel through the same grid interaction entrypoint.")

	var rotate_availability := StringName(grab_controller.call("get_selected_rotate_interaction_availability"))
	if rotate_availability == AvailabilityScript.AVAILABLE:
		rotate_right.emit_signal("pressed")
		await process_frame
		_expect_true(bool(arm.call("is_turning")), "Rotate button should reuse the existing selected-vehicle turn request.")
		_expect_equal(StringName(grab_controller.call("get_selected_rotate_interaction_availability")), AvailabilityScript.ROTATING, "Rotate owner should report the in-flight turn.")
		_expect_equal(rotate_status.text, "旋转中", "Operations should refresh from the authoritative rotating status.")

	scene.call("reset_scene")
	await process_frame
	var transport = manager.call("get_vehicle_by_id", &"transport_vehicle")
	_expect_true(transport != null and selection.call("select_vehicle", transport), "Operations contract should select Transport through VehicleSelectionController.")
	await process_frame
	_expect_true(vehicle_label.text.contains("运输车"), "Operations vehicle label should project the selected Transport.")
	_expect_equal(StringName(grab_controller.call("get_selected_grab_drop_interaction_availability")), AvailabilityScript.NO_CAPABILITY, "Transport GrabDrop should be unavailable from the authoritative controller.")
	_expect_equal(grab_status.text, "当前车辆不支持", "Unsupported command presentation should come from NO_CAPABILITY.")
	_expect_true(grab_button.disabled, "Unsupported GrabDrop should stay disabled.")
	_assert_projection(move_controller, grab_controller, move_button, rotate_left, rotate_right, grab_button)

	if bool(scene.call("ensure_gameplay_running")):
		scene.call("pause_scene")
		await process_frame
		_expect_equal(StringName(move_controller.call("get_selected_move_interaction_availability")), AvailabilityScript.PAUSED, "Paused lifecycle should flow through Move availability.")
		_expect_equal(StringName(grab_controller.call("get_selected_rotate_interaction_availability")), AvailabilityScript.PAUSED, "Paused lifecycle should flow through Rotate availability.")
		_expect_equal(StringName(grab_controller.call("get_selected_grab_drop_interaction_availability")), AvailabilityScript.PAUSED, "Paused lifecycle should flow through GrabDrop availability.")
		_expect_equal(move_status.text, "已暂停", "Operations should refresh lifecycle changes.")
		_expect_equal(rotate_status.text, "已暂停", "Rotate presentation should refresh lifecycle changes.")
		_expect_equal(grab_status.text, "已暂停", "GrabDrop presentation should refresh lifecycle changes.")
		_expect_true(move_button.disabled and rotate_left.disabled and rotate_right.disabled and grab_button.disabled, "Paused lifecycle should disable Operations actions from availability.")

	var program_panel := scene.get_node("ProgramUIRoot/RootControl/ProgramPanel") as Control
	_expect_true(not panel.get_global_rect().intersects(program_panel.get_global_rect()), "Operations and Program must occupy explicit non-overlapping right-rail sections.")
	_expect_true((operations as CanvasLayer).layer == (scene.get_node("ProgramUIRoot") as CanvasLayer).layer, "Operations and Program should remain sibling presentation surfaces.")
	_expect_true(panel.mouse_filter == Control.MOUSE_FILTER_STOP, "Operations surface must stop pointer clicks from leaking into gameplay.")

	await _cleanup(scene)


func _assert_projection(move_controller: Node, grab_controller: Node, move_button: Button, rotate_left: Button, rotate_right: Button, grab_button: Button) -> void:
	var move_status := StringName(move_controller.call("get_selected_move_interaction_availability"))
	var rotate_status := StringName(grab_controller.call("get_selected_rotate_interaction_availability"))
	var grab_status := StringName(grab_controller.call("get_selected_grab_drop_interaction_availability"))
	_expect_equal(move_button.disabled, not _move_actionable(move_status), "Move enablement should be a direct interaction-availability projection.")
	_expect_equal(rotate_left.disabled, rotate_status != AvailabilityScript.AVAILABLE, "Rotate-left enablement should be a direct interaction-availability projection.")
	_expect_equal(rotate_right.disabled, rotate_status != AvailabilityScript.AVAILABLE, "Rotate-right enablement should be a direct interaction-availability projection.")
	_expect_equal(grab_button.disabled, grab_status != AvailabilityScript.AVAILABLE, "GrabDrop enablement should be a direct interaction-availability projection.")


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


func _expect_true(value: bool, message: String) -> void:
	if value:
		return
	failures += 1
	push_error(message)


func _expect_false(value: bool, message: String) -> void:
	_expect_true(not value, message)


func _finish() -> void:
	if failures == 0:
		print("Scene 01 Operations Panel contract tests passed.")
	quit(failures)

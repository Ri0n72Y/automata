extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const ContractTestScript := preload("res://tests/support/contract_test.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const RuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const GrabDropControllerScript := preload("res://scripts/input/vehicle_grab_drop_controller.gd")
const StandardBlockScript := preload("res://scripts/objects/standard_block.gd")

var test := ContractTestScript.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	test.expect_true(packed != null, "Scene 01 should load for HUD test.")
	if packed == null:
		test.finish(self, "Scene 01 HUD tests")
		return

	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame

	var hud := scene.get_node_or_null("HUDRoot")
	var selection := scene.get_node_or_null("SceneRoot/GridRoot/VehicleSelectionController")
	var grid_selection := scene.get_node_or_null("SceneRoot/GridRoot/GridSelectionController")
	var move_controller := scene.get_node_or_null("SceneRoot/GridRoot/VehicleMoveController")
	var grab_drop_controller := scene.get_node_or_null(
		"SceneRoot/GridRoot/VehicleGrabDropController"
	) as GrabDropControllerScript
	var manager := scene.get_node_or_null(
		"SceneRoot/RobotRoot/Scene01VehicleManager"
	) as VehicleManagerScript
	var object_manager := scene.get_node_or_null("SceneRoot/ObjectRoot/Scene01ObjectManager")
	test.expect_true(hud != null, "Production Scene 01 should expose HUDRoot.")
	test.expect_true(
		selection != null
		and grid_selection != null
		and move_controller != null
		and grab_drop_controller != null,
		"HUD test requires command controllers."
	)
	test.expect_true(manager != null and object_manager != null, "HUD test requires domain owners.")
	if (
		hud == null
		or selection == null
		or grid_selection == null
		or move_controller == null
		or grab_drop_controller == null
		or manager == null
		or object_manager == null
	):
		await _cleanup(scene)
		test.finish(self, "Scene 01 HUD tests")
		return

	var selected_label := hud.get_node(
		"RootControl/SidebarPanel/Margin/SidebarScroll/Sidebar/VehicleSection/Card/Margin/SelectedLabel"
	) as Label
	var mission_label := hud.get_node(
		"RootControl/SidebarPanel/Margin/SidebarScroll/Sidebar/MissionSection/Card/Margin/VBox/Row/MissionLabel"
	) as Label
	var mission_value_label := hud.get_node(
		"RootControl/SidebarPanel/Margin/SidebarScroll/Sidebar/MissionSection/Card/Margin/VBox/Row/MissionValueLabel"
	) as Label
	var mission_progress := hud.get_node(
		"RootControl/SidebarPanel/Margin/SidebarScroll/Sidebar/MissionSection/Card/Margin/VBox/MissionProgress"
	) as ProgressBar
	var position_value := hud.get_node(
		"RootControl/SidebarPanel/Margin/SidebarScroll/Sidebar/StatusSection/StatusCard/Margin/StatusBody/PositionRow/PositionValueLabel"
	) as Label
	var facing_value := hud.get_node(
		"RootControl/SidebarPanel/Margin/SidebarScroll/Sidebar/StatusSection/StatusCard/Margin/StatusBody/FacingRow/FacingValueLabel"
	) as Label
	var cargo_name := hud.get_node(
		"RootControl/SidebarPanel/Margin/SidebarScroll/Sidebar/StatusSection/StatusCard/Margin/StatusBody/CargoRow/CargoNameLabel"
	) as Label
	var cargo_value := hud.get_node(
		"RootControl/SidebarPanel/Margin/SidebarScroll/Sidebar/StatusSection/StatusCard/Margin/StatusBody/CargoRow/CargoValueLabel"
	) as Label
	var move_value := hud.get_node(
		"RootControl/SidebarPanel/Margin/SidebarScroll/Sidebar/StatusSection/StatusCard/Margin/StatusBody/MoveRow/MoveValueLabel"
	) as Label
	var rotate_value := hud.get_node(
		"RootControl/SidebarPanel/Margin/SidebarScroll/Sidebar/StatusSection/StatusCard/Margin/StatusBody/RotateRow/RotateValueLabel"
	) as Label
	var grab_value := hud.get_node(
		"RootControl/SidebarPanel/Margin/SidebarScroll/Sidebar/StatusSection/StatusCard/Margin/StatusBody/GrabRow/GrabValueLabel"
	) as Label
	var feedback_label := hud.get_node(
		"RootControl/SidebarPanel/Margin/SidebarScroll/Sidebar/StatusSection/FeedbackLabel"
	) as Label
	var completion_panel := hud.get_node("RootControl/CompletionPanel") as PanelContainer

	test.expect_equal(mission_label.text, "标准箱", "HUD mission card should label the StandardBox target.")
	test.expect_true(
		mission_value_label.text.find("3") >= 0 and mission_value_label.text.find("8") >= 0,
		"HUD should expose initial box progress."
	)
	test.expect_equal(
		int(mission_progress.value),
		3,
		"HUD mission progress bar should project the real StandardBox count."
	)
	test.expect_equal(move_value.text, "—", "HUD should keep capability rows compact before selection.")
	test.expect_false(completion_panel.visible, "Completion panel should start hidden.")

	test.expect_false(
		bool(move_controller.call("request_selected_vehicle_move", Vector2i(2, 2))),
		"Move without a selected vehicle should be rejected."
	)
	test.expect_true(
		feedback_label.text.find("未选择车辆") >= 0,
		"HUD should preserve player-visible rejection feedback."
	)

	var arm = manager.get_vehicle_by_id(VehicleManagerScript.ARM_VEHICLE_ID)
	var transport = manager.get_vehicle_by_id(VehicleManagerScript.TRANSPORT_VEHICLE_ID)
	test.expect_true(arm != null and transport != null, "HUD test requires both vehicles.")
	if arm == null or transport == null:
		await _cleanup(scene)
		test.finish(self, "Scene 01 HUD tests")
		return

	arm.runtime_state.anchor_cell = Vector2i(1, 3)
	arm.runtime_state.facing = RuntimeStateScript.Facing.WEST
	arm.sync_from_state()
	test.expect_true(bool(selection.call("select_vehicle", arm)), "Arm should be selectable for HUD binding test.")
	test.expect_true(
		selected_label.text.find("机械臂车") >= 0,
		"HUD should show selected vehicle display name."
	)
	test.expect_equal(position_value.text, "1, 3", "HUD should project the selected vehicle position.")
	test.expect_equal(facing_value.text, "西", "HUD should project the selected vehicle facing.")
	test.expect_equal(move_value.text, "可用", "Waiting movable vehicle should expose Move as available.")
	test.expect_equal(rotate_value.text, "可用", "Waiting rotatable vehicle should expose Rotate as available.")
	test.expect_equal(grab_value.text, "可用", "Arm facing the pile should expose GrabDrop as available.")

	test.expect_true(
		bool(grid_selection.call("activate_live_target_mode")),
		"Move target mode should activate for HUD availability transition."
	)
	test.expect_equal(rotate_value.text, "选点中", "Move target mode should disable Rotate in HUD.")
	test.expect_equal(grab_value.text, "选点中", "Move target mode should disable GrabDrop in HUD.")
	grid_selection.call("deactivate_live_target_mode")
	test.expect_equal(
		grab_value.text,
		"可用",
		"Leaving Move target mode should restore current GrabDrop availability."
	)

	test.expect_true(grab_drop_controller.rotate_selected_vehicle(1), "Arm should rotate away from the pile.")
	test.expect_equal(
		rotate_value.text,
		"旋转中",
		"HUD should expose in-flight Rotate state from the real vehicle owner."
	)
	test.expect_equal(
		move_value.text,
		"忙碌",
		"HUD Move availability should follow the same turn-busy owner contract."
	)
	test.expect_false(
		bool(grid_selection.call("is_live_target_available")),
		"Rotate should disable Move target availability while the turn is in flight."
	)
	test.expect_false(
		bool(grid_selection.call("activate_live_target_mode")),
		"Pressing M during Rotate must not enter Move target mode."
	)
	test.expect_false(
		bool(grid_selection.call("is_live_target_mode")),
		"Rotate must keep Move target mode inactive."
	)
	test.expect_false(
		bool(move_controller.call("is_target_preview_visible")),
		"Rotate must not expose a Move target preview."
	)
	test.expect_false(
		bool(move_controller.call("is_path_preview_visible")),
		"Rotate must not expose a Move path preview."
	)
	var turn_frames := 0
	while arm.is_turning() and turn_frames < 120:
		await physics_frame
		turn_frames += 1
	test.expect_true(turn_frames < 120, "HUD rotation fixture should complete.")
	test.expect_equal(rotate_value.text, "可用", "Completed turn should restore Rotate availability.")
	test.expect_equal(move_value.text, "可用", "Completed turn should restore Move availability.")
	test.expect_true(
		bool(grid_selection.call("is_live_target_available")),
		"Completed turn should restore Move target availability."
	)
	test.expect_equal(
		grab_value.text,
		"无目标",
		"Completed facing changes should refresh GrabDrop availability."
	)

	test.expect_true(
		bool(selection.call("select_vehicle", transport)),
		"Transport should be selectable for capability feedback."
	)
	test.expect_equal(
		rotate_value.text,
		"可用",
		"Transport should expose its independent Rotate capability in HUD."
	)
	test.expect_equal(grab_value.text, "不可用", "HUD should explain GrabDrop capability absence.")
	test.expect_true(bool(selection.call("select_vehicle", arm)), "Arm should be reselected for state binding checks.")

	test.expect_true(arm.runtime_state.begin_move_planning(), "HUD state fixture should enter PLANNING.")
	test.expect_equal(move_value.text, "规划中", "HUD should react to observable vehicle state changes.")
	test.expect_equal(grab_value.text, "忙碌", "Planning should explain GrabDrop unavailability.")
	arm.runtime_state.reset()
	test.expect_equal(move_value.text, "可用", "HUD should restore Move availability after owner reset.")

	test.expect_true(
		arm.runtime_state.claim_carried_item(StandardBlockScript.create()),
		"Arm inventory fixture should claim a block."
	)
	test.expect_true(
		cargo_name.text == "手持" and cargo_value.text == "方块",
		"HUD should react to arm cargo changes."
	)
	test.expect_true(
		transport.runtime_state.tray_state.put_item(StandardBlockScript.create()).is_success(),
		"Tray fixture should accept a block."
	)
	test.expect_true(
		bool(selection.call("select_vehicle", transport)),
		"Transport should be selectable for tray projection."
	)
	test.expect_true(
		cargo_name.text == "托盘" and cargo_value.text == "1",
		"HUD should react to tray count changes."
	)
	test.expect_true(
		bool(selection.call("select_vehicle", arm)),
		"Arm should be reselected after tray projection check."
	)

	scene.call("pause_scene")
	test.expect_equal(move_value.text, "暂停", "Pause should explain Move unavailability.")
	test.expect_equal(rotate_value.text, "暂停", "Pause should explain Rotate unavailability.")
	test.expect_equal(grab_value.text, "暂停", "Pause should explain GrabDrop unavailability.")
	scene.call("run_scene")

	var box = object_manager.get_standard_box()
	while box.get_current_count() < box.get_capacity():
		test.expect_true(
			box.put_item(StandardBlockScript.create()).is_success(),
			"HUD completion fixture should fill StandardBox."
		)
	test.expect_true(completion_panel.visible, "HUD should show completion panel from Mission COMPLETED.")
	test.expect_equal(int(mission_progress.value), 8, "HUD mission progress should reach the real completed target.")

	test.expect_true(bool(scene.call("reset_scene")), "Scene Reset should succeed for HUD reset binding.")
	await process_frame
	test.expect_false(completion_panel.visible, "Reset should hide completion panel.")
	test.expect_true(
		mission_value_label.text.find("3") >= 0 and mission_value_label.text.find("8") >= 0,
		"Reset should restore box progress in HUD."
	)
	test.expect_equal(int(mission_progress.value), 3, "Reset should restore mission progress bar.")
	test.expect_true(selected_label.text.find("未选择") >= 0, "Reset should clear selected vehicle in HUD.")
	test.expect_equal(cargo_value.text, "—", "Reset should clear selected vehicle cargo projection.")
	test.expect_true(
		feedback_label.text.find("场景已重置") >= 0,
		"HUD should provide visible Reset feedback."
	)

	await _cleanup(scene)
	test.finish(self, "Scene 01 HUD tests")


func _cleanup(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
		await process_frame

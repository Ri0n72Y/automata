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
	var move_controller := scene.get_node_or_null("SceneRoot/GridRoot/VehicleMoveController")
	var grab_drop_controller := scene.get_node_or_null(
		"SceneRoot/GridRoot/VehicleGrabDropController"
	) as GrabDropControllerScript
	var manager := scene.get_node_or_null("SceneRoot/RobotRoot/Scene01VehicleManager") as VehicleManagerScript
	var object_manager := scene.get_node_or_null("SceneRoot/ObjectRoot/Scene01ObjectManager")
	test.expect_true(hud != null, "Production Scene 01 should expose HUDRoot.")
	test.expect_true(
		selection != null and move_controller != null and grab_drop_controller != null,
		"HUD test requires command controllers."
	)
	test.expect_true(manager != null and object_manager != null, "HUD test requires domain owners.")
	if (
		hud == null
		or selection == null
		or move_controller == null
		or grab_drop_controller == null
		or manager == null
		or object_manager == null
	):
		await _cleanup(scene)
		test.finish(self, "Scene 01 HUD tests")
		return

	var selected_label := hud.get_node("RootControl/StatusPanel/Margin/VBox/SelectedLabel") as Label
	var vehicle_state_label := hud.get_node("RootControl/StatusPanel/Margin/VBox/VehicleStateLabel") as Label
	var inventory_label := hud.get_node("RootControl/StatusPanel/Margin/VBox/InventoryLabel") as Label
	var mission_label := hud.get_node("RootControl/StatusPanel/Margin/VBox/MissionLabel") as Label
	var pause_label := hud.get_node("RootControl/StatusPanel/Margin/VBox/Header/PauseLabel") as Label
	var commands_label := hud.get_node("RootControl/StatusPanel/Margin/VBox/CommandsLabel") as Label
	var feedback_label := hud.get_node("RootControl/StatusPanel/Margin/VBox/FeedbackLabel") as Label
	var completion_panel := hud.get_node("RootControl/CompletionPanel") as PanelContainer

	test.expect_true(mission_label.text.find("READY") >= 0, "HUD should expose initial Mission READY.")
	test.expect_true(mission_label.text.find("3/8") >= 0, "HUD should expose initial box progress.")
	test.expect_true(commands_label.text.find("未选择车辆") >= 0, "HUD should explain unavailable commands before selection.")
	test.expect_false(completion_panel.visible, "Completion panel should start hidden.")

	test.expect_false(
		bool(move_controller.call("request_selected_vehicle_move", Vector2i(2, 2))),
		"Move without a selected vehicle should be rejected."
	)
	test.expect_true(feedback_label.text.find("未选择车辆") >= 0, "HUD should show command rejection reason.")

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
	test.expect_true(selected_label.text.find("Arm Vehicle") >= 0, "HUD should show selected vehicle display name.")
	test.expect_true(vehicle_state_label.text.find("WAITING") >= 0, "HUD should show selected vehicle state.")
	test.expect_true(commands_label.text.find("M 移动 可用") >= 0, "Waiting movable vehicle should expose Move as available.")
	test.expect_true(commands_label.text.find("X 停止 车辆未移动") >= 0, "Waiting vehicle should explain why Stop is unavailable.")
	test.expect_true(commands_label.text.find("C 抓放 可用") >= 0, "Arm facing the pile should expose GrabDrop as available.")

	test.expect_true(grab_drop_controller.rotate_selected_arm(1), "Arm should rotate away from the pile.")
	test.expect_true(
		commands_label.text.find("C 抓放 无有效交互目标") >= 0,
		"Facing changes should refresh GrabDrop availability immediately."
	)

	test.expect_true(bool(selection.call("select_vehicle", transport)), "Transport should be selectable for capability feedback.")
	test.expect_true(
		commands_label.text.find("C 抓放 车辆无机械臂") >= 0,
		"HUD should explain GrabDrop capability absence."
	)
	test.expect_true(bool(selection.call("select_vehicle", arm)), "Arm should be reselected for state binding checks.")

	test.expect_true(arm.runtime_state.begin_move_planning(), "HUD state fixture should enter PLANNING.")
	test.expect_true(vehicle_state_label.text.find("PLANNING") >= 0, "HUD should react to observable vehicle state changes.")
	test.expect_true(commands_label.text.find("M 移动 车辆忙碌") >= 0, "Planning should explain Move unavailability.")
	test.expect_true(commands_label.text.find("C 抓放 车辆忙碌") >= 0, "Planning should explain GrabDrop unavailability.")
	arm.runtime_state.reset()
	test.expect_true(vehicle_state_label.text.find("WAITING") >= 0, "HUD should return to WAITING after owner reset.")

	test.expect_true(arm.runtime_state.claim_carried_item(StandardBlockScript.create()), "Arm inventory fixture should claim a block.")
	test.expect_true(inventory_label.text.find("持有方块") >= 0, "HUD should react to arm cargo changes.")
	test.expect_true(
		transport.runtime_state.tray_state.put_item(StandardBlockScript.create()).is_success(),
		"Tray fixture should accept a block."
	)
	test.expect_true(inventory_label.text.find("托盘：1") >= 0, "HUD should react to tray count changes.")

	scene.call("pause_scene")
	test.expect_true(pause_label.visible, "HUD should show an explicit PAUSED indicator.")
	test.expect_true(commands_label.text.find("M 移动 暂停") >= 0, "Pause should explain Move unavailability.")
	test.expect_true(commands_label.text.find("X 停止 暂停") >= 0, "Pause should explain Stop unavailability.")
	test.expect_true(commands_label.text.find("C 抓放 暂停") >= 0, "Pause should explain GrabDrop unavailability.")
	scene.call("run_scene")
	test.expect_false(pause_label.visible, "HUD pause indicator should clear after Resume.")

	var box = object_manager.get_standard_box()
	while box.get_current_count() < box.get_capacity():
		test.expect_true(
			box.put_item(StandardBlockScript.create()).is_success(),
			"HUD completion fixture should fill StandardBox."
		)
	test.expect_true(completion_panel.visible, "HUD should show completion panel from Mission COMPLETED.")
	test.expect_true(mission_label.text.find("COMPLETED") >= 0, "HUD should expose Mission COMPLETED explicitly.")

	test.expect_true(bool(scene.call("reset_scene")), "Scene Reset should succeed for HUD reset binding.")
	await process_frame
	test.expect_false(completion_panel.visible, "Reset should hide completion panel.")
	test.expect_true(mission_label.text.find("READY") >= 0, "Reset should restore Mission READY in HUD.")
	test.expect_true(mission_label.text.find("3/8") >= 0, "Reset should restore box progress in HUD.")
	test.expect_true(selected_label.text.find("未选择") >= 0, "Reset should clear selected vehicle in HUD.")
	test.expect_true(inventory_label.text.find("托盘：0") >= 0, "Reset should expose cleared tray in HUD.")
	test.expect_true(inventory_label.text.find("机械臂：空") >= 0, "Reset should expose cleared arm cargo in HUD.")
	test.expect_true(feedback_label.text.find("场景已重置") >= 0, "HUD should provide visible Reset feedback.")

	await _cleanup(scene)
	test.finish(self, "Scene 01 HUD tests")


func _cleanup(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
		await process_frame

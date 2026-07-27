extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const VEHICLE_SELECTION_SCRIPT := preload("res://scripts/input/vehicle_selection_controller.gd")
const VEHICLE_MOVE_SCRIPT := preload("res://scripts/input/vehicle_move_controller.gd")
const GRID_SELECTION_SCRIPT := preload("res://scripts/input/grid_selection_controller.gd")
const VEHICLE_MANAGER_SCRIPT := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene := load(SCENE_PATH) as PackedScene
	_expect_true(packed_scene != null, "Scene 01 should load for hover prediction tests.")
	if packed_scene == null:
		_finish()
		return

	var scene := packed_scene.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame

	var grid_root := scene.get_node_or_null("SceneRoot/GridRoot") as Node3D
	var vehicle_selection := scene.get_node_or_null(
		"SceneRoot/GridRoot/VehicleSelectionController"
	) as VEHICLE_SELECTION_SCRIPT
	var move_controller := scene.get_node_or_null(
		"SceneRoot/GridRoot/VehicleMoveController"
	) as VEHICLE_MOVE_SCRIPT
	var grid_selection := scene.get_node_or_null(
		"SceneRoot/GridRoot/GridSelectionController"
	) as GRID_SELECTION_SCRIPT
	var manager := scene.get_node_or_null(
		"SceneRoot/RobotRoot/Scene01VehicleManager"
	) as VEHICLE_MANAGER_SCRIPT

	_expect_true(grid_root != null, "GridRoot should exist.")
	_expect_true(vehicle_selection != null, "Vehicle selection controller should exist.")
	_expect_true(move_controller != null, "Vehicle move controller should exist.")
	_expect_true(grid_selection != null, "Grid selection controller should exist.")
	_expect_true(manager != null, "Vehicle manager should exist.")

	if (
		grid_root != null
		and vehicle_selection != null
		and move_controller != null
		and grid_selection != null
		and manager != null
	):
		_test_hover_prediction(
			scene,
			grid_root,
			vehicle_selection,
			move_controller,
			grid_selection,
			manager
		)

	scene.queue_free()
	await process_frame
	_finish()


func _test_hover_prediction(
	scene: Node,
	grid_root: Node3D,
	vehicle_selection: VEHICLE_SELECTION_SCRIPT,
	move_controller: VEHICLE_MOVE_SCRIPT,
	grid_selection: GRID_SELECTION_SCRIPT,
	manager: VEHICLE_MANAGER_SCRIPT
) -> void:
	var arm = manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.ARM_VEHICLE_ID)
	_expect_true(arm != null, "Arm vehicle should exist.")
	if arm == null:
		return

	_expect_true(vehicle_selection.select_vehicle(arm), "Arm vehicle should be selectable.")
	_expect_true(grid_selection.is_live_target_mode(), "Selecting a vehicle should enable live target mode.")
	_expect_equal(
		grid_selection.get_target_footprint(),
		Vector2i(2, 2),
		"Live target snapping should use the selected vehicle footprint."
	)

	var hover_world := grid_root.to_global(Vector3(5.08, 0.0, 4.02))
	_expect_true(
		grid_selection.update_hover_from_world_position(hover_world),
		"Mouse hover over the field should update prediction without a click."
	)
	var expected_anchor := Vector2i(4, 3)
	_expect_equal(
		grid_selection.selected_cell,
		expected_anchor,
		"2x2 hover should snap to the nearest grid-line intersection."
	)
	_expect_true(move_controller.is_target_preview_visible(), "Live hover should show footprint prediction.")
	_expect_true(move_controller.is_target_preview_valid(), "Reachable live hover should be valid.")
	_expect_true(move_controller.is_path_preview_visible(), "Reachable live hover should show a path line.")

	var preview_path := move_controller.get_preview_path()
	_expect_true(preview_path.size() >= 2, "Prediction path should contain at least one segment.")
	if preview_path.size() >= 2:
		_expect_equal(
			preview_path.front(),
			arm.runtime_state.anchor_cell,
			"Prediction path should start from the vehicle anchor."
		)
		_expect_equal(
			preview_path.back(),
			expected_anchor,
			"Prediction path should end at the hovered footprint anchor."
		)
		var start_center: Vector3 = scene.call(
			"grid_footprint_center_to_world",
			preview_path.front(),
			arm.definition.footprint
		)
		var target_center: Vector3 = scene.call(
			"grid_footprint_center_to_world",
			preview_path.back(),
			arm.definition.footprint
		)
		_expect_vector3_approx(
			start_center,
			arm.global_position,
			"2x2 prediction should start at the vehicle footprint center."
		)
		_expect_vector3_approx(
			target_center,
			grid_root.to_global(Vector3(5.0, 0.0, 4.0)),
			"2x2 prediction target should lie on the four-cell intersection."
		)

	var hover_highlight := grid_selection.get_node_or_null("HoverHighlight") as MeshInstance3D
	var selected_highlight := grid_selection.get_node_or_null("SelectedHighlight") as MeshInstance3D
	_expect_true(
		hover_highlight != null and not hover_highlight.visible,
		"Live vehicle prediction should hide the filled single-cell hover highlight."
	)
	_expect_true(
		selected_highlight != null and not selected_highlight.visible,
		"Live vehicle prediction should hide the filled single-cell selected highlight."
	)

	move_controller.set_vehicle_ui_open(true)
	_expect_true(not grid_selection.is_live_target_mode(), "Opening vehicle UI should pause live prediction.")
	_expect_true(not move_controller.is_target_preview_visible(), "Opening vehicle UI should hide target prediction.")
	_expect_true(not move_controller.is_path_preview_visible(), "Opening vehicle UI should hide path prediction.")
	move_controller.set_vehicle_ui_open(false)
	_expect_true(grid_selection.is_live_target_mode(), "Closing vehicle UI should restore live prediction.")
	_expect_true(move_controller.is_target_preview_visible(), "Closing vehicle UI should restore hovered target prediction.")
	_expect_true(move_controller.is_path_preview_visible(), "Closing vehicle UI should restore hovered path prediction.")

	vehicle_selection.cancel_selection()
	_expect_true(not grid_selection.is_live_target_mode(), "Cancelling vehicle selection should disable live prediction.")
	_expect_true(not move_controller.is_target_preview_visible(), "Cancelling vehicle selection should hide target prediction.")
	_expect_true(not move_controller.is_path_preview_visible(), "Cancelling vehicle selection should hide path prediction.")


func _finish() -> void:
	if failures == 0:
		print("Scene 01 hover prediction smoke tests passed.")
		quit(0)
		return
	push_error("Scene 01 hover prediction tests failed: %d failure(s)." % failures)
	quit(1)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	failures += 1
	push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])


func _expect_vector3_approx(actual: Vector3, expected: Vector3, message: String) -> void:
	if actual.is_equal_approx(expected):
		return
	failures += 1
	push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])


func _expect_true(value: bool, message: String) -> void:
	if value:
		return
	failures += 1
	push_error(message)
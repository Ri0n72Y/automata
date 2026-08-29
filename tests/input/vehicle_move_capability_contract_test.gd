extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const LifecycleStateScript := preload("res://scripts/scene_01/scene_01_lifecycle_state.gd")
const VehicleDefinitionScript := preload("res://scripts/vehicles/vehicle_definition.gd")
const VehicleRuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const VehicleSelectionScript := preload("res://scripts/input/vehicle_selection_controller.gd")
const VehicleMoveScript := preload("res://scripts/input/vehicle_move_controller.gd")
const GridSelectionScript := preload("res://scripts/input/grid_selection_controller.gd")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for MoveTo capability tests.")
	if packed == null:
		_finish()
		return

	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame

	var manager := scene.get_node_or_null("SceneRoot/RobotRoot/Scene01VehicleManager") as VehicleManagerScript
	var selection := scene.get_node_or_null("SceneRoot/GridRoot/VehicleSelectionController") as VehicleSelectionScript
	var move := scene.get_node_or_null("SceneRoot/GridRoot/VehicleMoveController") as VehicleMoveScript
	var grid_selection := scene.get_node_or_null("SceneRoot/GridRoot/GridSelectionController") as GridSelectionScript
	_expect_true(
		manager != null and selection != null and move != null and grid_selection != null,
		"MoveTo capability test requires the shared movement controllers."
	)
	if manager == null or selection == null or move == null or grid_selection == null:
		await _cleanup(scene)
		_finish()
		return

	var arm := manager.get_vehicle_by_id(VehicleManagerScript.ARM_VEHICLE_ID)
	_expect_true(arm != null, "MoveTo capability test requires the arm vehicle.")
	if arm == null:
		await _cleanup(scene)
		_finish()
		return

	var definition := VehicleDefinitionScript.new()
	_expect_true(
		definition.configure(
			VehicleManagerScript.ARM_VEHICLE_ID,
			"Arm Without Drive",
			VehicleDefinitionScript.VehicleKind.ARM,
			Vector2i(2, 2),
			2.0,
			18.0,
			20.0,
			30.0,
			PackedStringArray([
				VehicleDefinitionScript.CAPABILITY_CAN_GRAB,
				VehicleDefinitionScript.CAPABILITY_CAN_CARRY,
			]),
			0.25,
			0
		),
		"Fixture definition without can_move should configure."
	)
	var runtime := VehicleRuntimeStateScript.new()
	_expect_true(
		runtime.configure(definition, arm.runtime_state.anchor_cell, arm.runtime_state.facing),
		"Fixture runtime should configure against the no-move definition."
	)
	arm.definition = definition
	arm.runtime_state = runtime
	arm.sync_from_state()

	_expect_true(selection.select_vehicle(arm), "No-move vehicle should remain selectable as a simulation object.")
	move._sync_live_target_mode()
	_expect_false(
		grid_selection.is_live_target_available(),
		"A vehicle without can_move must not advertise M / MoveTo target mode."
	)

	var target := Vector2i(4, 2)
	_expect_false(
		move.request_selected_vehicle_move(target),
		"The shared MoveTo service must reject a vehicle without can_move."
	)
	_expect_equal(
		move.get_last_rejection_reason(),
		VehicleMoveScript.REJECTION_NO_MOVE_CAPABILITY,
		"Manual and future ProgramRunner MoveTo should receive the same no_move_capability result."
	)
	_expect_equal(
		runtime.motion_state,
		VehicleRuntimeStateScript.MotionState.WAITING,
		"Capability rejection must occur before move planning mutates runtime state."
	)
	_expect_true(runtime.active_move_command == null, "Capability rejection must not create a MoveCommand.")
	_expect_equal(
		int(scene.call("get_lifecycle_state")),
		LifecycleStateScript.State.RUNNING,
		"A domain capability rejection should not roll a successfully started simulation back to READY."
	)

	await _cleanup(scene)
	_finish()


func _cleanup(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
		await process_frame


func _finish() -> void:
	if failures == 0:
		print("Vehicle MoveTo capability contract tests passed.")
		quit(0)
		return
	push_error("Vehicle MoveTo capability contract tests failed: %d failure(s)." % failures)
	quit(1)


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
	if not value:
		return
	failures += 1
	push_error(message)

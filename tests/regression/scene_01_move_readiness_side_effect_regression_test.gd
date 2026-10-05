extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const LifecycleStateScript := preload("res://scripts/scene_01/scene_01_lifecycle_state.gd")
const VehicleDefinitionScript := preload("res://scripts/vehicles/vehicle_definition.gd")
const VehicleRuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const VehicleMoveScript := preload("res://scripts/input/vehicle_move_controller.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Regression fixture should load Scene 01.")
	if packed == null:
		_finish()
		return

	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame

	var manager = scene.get_node_or_null("SceneRoot/RobotRoot/Scene01VehicleManager")
	var selection = scene.get_node_or_null("SceneRoot/GridRoot/VehicleSelectionController")
	var move = scene.get_node_or_null("SceneRoot/GridRoot/VehicleMoveController")
	var grid_selection = scene.get_node_or_null("SceneRoot/GridRoot/GridSelectionController")
	var arm = (
		manager.get_vehicle_by_id(VehicleManagerScript.ARM_VEHICLE_ID)
		if manager != null else null
	)
	_expect_true(
		arm != null and selection != null and move != null and grid_selection != null,
		"Move readiness regression fixture should expose gameplay owners."
	)
	if arm == null or selection == null or move == null or grid_selection == null:
		await _cleanup(scene)
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
		"No-move regression definition should configure."
	)
	var runtime := VehicleRuntimeStateScript.new()
	_expect_true(
		runtime.configure(definition, arm.runtime_state.anchor_cell, arm.runtime_state.facing),
		"No-move regression runtime should configure."
	)
	arm.definition = definition
	arm.runtime_state = runtime
	arm.sync_from_state()

	_expect_true(selection.select_vehicle(arm), "No-move Arm should remain selectable.")
	_expect_false(
		grid_selection.is_live_target_available(),
		"Readiness probe must report unavailable without mutating lifecycle truth."
	)

	_expect_false(
		move.request_selected_vehicle_move(Vector2i(4, 2)),
		"MoveTo must reject a vehicle without can_move."
	)
	_expect_equal(
		move.get_last_rejection_reason(),
		VehicleMoveScript.REJECTION_NO_MOVE_CAPABILITY,
		"Capability rejection reason must survive readiness probing."
	)
	_expect_equal(
		int(scene.call("get_lifecycle_state")),
		LifecycleStateScript.State.RUNNING,
		"Capability rejection must not roll a started lifecycle back to READY."
	)

	await _cleanup(scene)


func _cleanup(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	_finish()


func _finish() -> void:
	if failures == 0:
		print("Move readiness side-effect regression test passed.")
		quit(0)
		return
	push_error("Move readiness side-effect regression test failed: %d failure(s)." % failures)
	quit(1)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures += 1
		push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])


func _expect_true(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func _expect_false(value: bool, message: String) -> void:
	_expect_true(not value, message)

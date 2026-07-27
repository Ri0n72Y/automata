extends SceneTree

const VEHICLE_DEFINITION_SCRIPT := preload("res://scripts/vehicles/vehicle_definition.gd")
const VEHICLE_RUNTIME_STATE_SCRIPT := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const VEHICLE_ACTOR_SCRIPT := preload("res://scripts/vehicles/vehicle_actor.gd")
const MOVE_COMMAND_SCRIPT := preload("res://scripts/vehicles/move_command.gd")

var failures: int = 0


class FakeController extends Node3D:
	var grid_transform: Transform3D = Transform3D.IDENTITY

	func grid_footprint_center_to_world(anchor: Vector2i, footprint: Vector2i) -> Vector3:
		var local_center := Vector3(
			float(anchor.x) + float(footprint.x - 1) * 0.5,
			0.0,
			float(anchor.y) + float(footprint.y - 1) * 0.5
		)
		return grid_transform * local_center

	func get_grid_world_basis() -> Basis:
		return grid_transform.basis


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var definition := VEHICLE_DEFINITION_SCRIPT.new()
	_expect_true(
		definition.configure(
			&"test_vehicle",
			"Test Vehicle",
			VEHICLE_DEFINITION_SCRIPT.VehicleKind.ARM,
			Vector2i(2, 2),
			2.0,
			10.0,
			0.0,
			5.0,
			PackedStringArray([
				VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_MOVE,
				VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_GRAB,
			]),
			0.25
		),
		"Vehicle definition should configure."
	)

	var runtime_state := VEHICLE_RUNTIME_STATE_SCRIPT.new()
	_expect_true(
		runtime_state.configure(definition, Vector2i(1, 1)),
		"Vehicle runtime state should configure."
	)

	var controller := FakeController.new()
	root.add_child(controller)
	var actor := VEHICLE_ACTOR_SCRIPT.new()
	root.add_child(actor)
	_expect_true(
		actor.configure(definition, runtime_state, controller, 1.0),
		"Vehicle actor should configure."
	)

	var completed_targets: Array[Vector2i] = []
	actor.move_completed.connect(
		func(target: Vector2i) -> void:
			completed_targets.append(target)
	)

	var command := MOVE_COMMAND_SCRIPT.new()
	command.configure(
		Vector2i(3, 1),
		[Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]
	)
	_expect_true(actor.start_move(command), "A valid path should start moving.")
	actor.advance_move(0.25)
	_expect_equal(runtime_state.anchor_cell, Vector2i(1, 1), "Anchor must remain at the last reached node.")
	_expect_float_approx(actor.get_segment_progress(), 0.5, "Movement should advance in logical cell units.")
	var expected_midpoint := controller.grid_footprint_center_to_world(
		Vector2i(1, 1),
		definition.footprint
	).lerp(
		controller.grid_footprint_center_to_world(Vector2i(2, 1), definition.footprint),
		0.5
	)
	_expect_vector3_approx(actor.global_position, expected_midpoint, "Actor should interpolate between grid anchors.")

	controller.grid_transform = Transform3D(
		Basis(Vector3.UP, PI * 0.5).scaled(Vector3(1.5, 1.0, 0.75)),
		Vector3(5.0, 0.0, -2.0)
	)
	actor.sync_from_state()
	var transformed_midpoint := controller.grid_footprint_center_to_world(
		Vector2i(1, 1),
		definition.footprint
	).lerp(
		controller.grid_footprint_center_to_world(Vector2i(2, 1), definition.footprint),
		0.5
	)
	_expect_vector3_approx(
		actor.global_position,
		transformed_midpoint,
		"GridRoot-style transform changes should preserve logical segment progress."
	)
	_expect_vector3_approx(actor.global_basis.x, controller.grid_transform.basis.x, "Actor basis X should follow grid basis.")
	_expect_vector3_approx(actor.global_basis.z, controller.grid_transform.basis.z, "Actor basis Z should follow grid basis.")

	actor.advance_move(0.25)
	_expect_equal(runtime_state.anchor_cell, Vector2i(2, 1), "Reaching the next node should update anchor.")
	_expect_equal(command.state, MOVE_COMMAND_SCRIPT.State.MOVING, "Intermediate node should remain Moving.")
	actor.advance_move(0.5)
	_expect_equal(runtime_state.anchor_cell, Vector2i(3, 1), "Vehicle should reach its target anchor.")
	_expect_equal(runtime_state.motion_state, VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.WAITING, "Arrival should restore Waiting.")
	_expect_true(runtime_state.active_move_command == null, "Arrival should release the active command.")
	_expect_equal(completed_targets, [Vector2i(3, 1)], "Completion signal should fire once with the target.")

	actor.reset_actor()
	_expect_true(runtime_state.set_arm_has_item(true), "Arm runtime should accept carried-item state.")
	var carrying_command := MOVE_COMMAND_SCRIPT.new()
	carrying_command.configure(Vector2i(2, 1), [Vector2i(1, 1), Vector2i(2, 1)])
	_expect_true(actor.start_move(carrying_command), "Carrying move should start.")
	actor.advance_move(1.0)
	_expect_float_approx(
		actor.get_segment_progress(),
		0.5,
		"Quarter-speed carrying rule should advance half a cell in one second."
	)
	actor.reset_actor()
	_expect_equal(runtime_state.anchor_cell, Vector2i(1, 1), "Reset should restore the initial anchor.")
	_expect_equal(runtime_state.motion_state, VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.WAITING, "Reset should restore Waiting.")
	_expect_float_approx(actor.get_segment_progress(), 0.0, "Reset should clear segment progress.")

	actor.queue_free()
	controller.queue_free()
	await process_frame
	_finish()


func _finish() -> void:
	if failures == 0:
		print("Vehicle move execution smoke tests passed.")
		quit(0)
		return
	push_error("Vehicle move execution smoke tests failed: %d failure(s)." % failures)
	quit(1)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	failures += 1
	push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])


func _expect_float_approx(actual: float, expected: float, message: String) -> void:
	if is_equal_approx(actual, expected):
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

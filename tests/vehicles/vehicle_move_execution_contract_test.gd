extends SceneTree

const DEFINITION := preload("res://scripts/vehicles/vehicle_definition.gd")
const RUNTIME := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const ACTOR := preload("res://scripts/vehicles/vehicle_actor.gd")
const COMMAND := preload("res://scripts/vehicles/move_command.gd")
const CONTRACT := preload("res://tests/support/contract_test.gd")

var test := CONTRACT.new()


class FakeController extends Node3D:
	var grid_transform := Transform3D.IDENTITY

	func grid_footprint_center_to_world(anchor: Vector2i, footprint: Vector2i) -> Vector3:
		var center := Vector3(
			float(anchor.x) + float(footprint.x - 1) * 0.5,
			0.0,
			float(anchor.y) + float(footprint.y - 1) * 0.5
		)
		return grid_transform * center

	func get_grid_world_basis() -> Basis:
		return grid_transform.basis


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var fixture := _fixture(true)
	_test_start_boundaries(fixture)
	_test_time_boundaries(fixture)
	_test_transform_boundary(fixture)
	_test_speed_modes(fixture)
	_test_cancel_and_reset(fixture)
	_test_non_movable_definition()
	_free_fixture(fixture)
	await process_frame
	test.finish(self, "Vehicle move execution contract tests")


func _fixture(can_move: bool) -> Dictionary:
	var tags := PackedStringArray([DEFINITION.CAPABILITY_CAN_GRAB])
	if can_move:
		tags.append(DEFINITION.CAPABILITY_CAN_MOVE)
	var definition := DEFINITION.new()
	test.expect_true(definition.configure(
		&"test_vehicle", "Test Vehicle", DEFINITION.VehicleKind.ARM,
		Vector2i(2, 2), 2.0, 10.0, 0.0, 5.0, tags, 0.25
	), "Definition should configure.")
	var runtime := RUNTIME.new()
	test.expect_true(runtime.configure(definition, Vector2i(1, 1)), "Runtime should configure.")
	var controller := FakeController.new()
	root.add_child(controller)
	var actor := ACTOR.new()
	root.add_child(actor)
	test.expect_true(actor.configure(definition, runtime, controller, 1.0), "Actor should configure.")
	return {"definition": definition, "runtime": runtime, "controller": controller, "actor": actor}


func _test_start_boundaries(fixture: Dictionary) -> void:
	var actor = fixture["actor"]
	var runtime = fixture["runtime"]
	test.expect_false(actor.start_move(null), "Null commands should be rejected.")
	var mismatched := _command(Vector2i(3, 1), [Vector2i(2, 1), Vector2i(3, 1)])
	test.expect_false(actor.start_move(mismatched), "Command start must match the current anchor.")
	test.expect_equal(runtime.motion_state, RUNTIME.MotionState.WAITING, "Rejected starts preserve Waiting.")


func _test_time_boundaries(fixture: Dictionary) -> void:
	_reset(fixture)
	var actor = fixture["actor"]
	var runtime = fixture["runtime"]
	var controller = fixture["controller"]
	var definition = fixture["definition"]
	var completed: Array[Vector2i] = []
	actor.move_completed.connect(func(target: Vector2i) -> void: completed.append(target), CONNECT_ONE_SHOT)
	var command := _command(Vector2i(3, 1), [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)])
	test.expect_true(actor.start_move(command), "Valid commands should start.")

	actor.advance_move(0.0)
	test.expect_float_approx(actor.get_segment_progress(), 0.0, "Zero delta preserves progress.")
	actor.advance_move(0.25)
	test.expect_equal(runtime.anchor_cell, Vector2i(1, 1), "Segment-interior movement preserves the last reached anchor.")
	test.expect_float_approx(actor.get_segment_progress(), 0.5, "Quarter second advances half a cell at speed two.")
	var midpoint := controller.grid_footprint_center_to_world(Vector2i(1, 1), definition.footprint).lerp(
		controller.grid_footprint_center_to_world(Vector2i(2, 1), definition.footprint), 0.5
	)
	test.expect_vector3_approx(actor.global_position, midpoint, "Segment-interior position interpolates between centers.")

	actor.advance_move(0.25)
	test.expect_equal(runtime.anchor_cell, Vector2i(2, 1), "Exact segment completion updates the anchor.")
	test.expect_equal(command.state, COMMAND.State.MOVING, "Intermediate arrival remains Moving.")
	actor.advance_move(1.0)
	test.expect_equal(runtime.anchor_cell, Vector2i(3, 1), "Overflow delta reaches the final target.")
	test.expect_equal(runtime.motion_state, RUNTIME.MotionState.WAITING, "Final arrival restores Waiting.")
	test.expect_equal(completed, [Vector2i(3, 1)], "Completion emits once.")

	_reset(fixture)
	var long_command := _command(
		Vector2i(4, 1),
		[Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1)]
	)
	test.expect_true(actor.start_move(long_command), "Long commands should start.")
	actor.advance_move(2.0)
	test.expect_equal(runtime.anchor_cell, Vector2i(4, 1), "Large delta consumes multiple complete segments.")
	test.expect_float_approx(actor.get_segment_progress(), 0.0, "Finished movement discards overflow progress.")


func _test_transform_boundary(fixture: Dictionary) -> void:
	_reset(fixture)
	var actor = fixture["actor"]
	var controller = fixture["controller"]
	var definition = fixture["definition"]
	test.expect_true(actor.start_move(_command(Vector2i(2, 1), [Vector2i(1, 1), Vector2i(2, 1)])), "Transform command should start.")
	actor.advance_move(0.25)
	controller.grid_transform = Transform3D(
		Basis(Vector3.UP, PI * 0.5).scaled(Vector3(1.5, 1.0, 0.75)),
		Vector3(5.0, 0.0, -2.0)
	)
	actor.sync_from_state()
	var midpoint := controller.grid_footprint_center_to_world(Vector2i(1, 1), definition.footprint).lerp(
		controller.grid_footprint_center_to_world(Vector2i(2, 1), definition.footprint), 0.5
	)
	test.expect_float_approx(actor.get_segment_progress(), 0.5, "Transform changes preserve logical progress.")
	test.expect_vector3_approx(actor.global_position, midpoint, "Transform changes remap the logical position.")


func _test_speed_modes(fixture: Dictionary) -> void:
	_reset(fixture)
	var actor = fixture["actor"]
	var runtime = fixture["runtime"]
	test.expect_true(runtime.set_arm_has_item(true), "Arm state should accept a carried item.")
	test.expect_true(actor.start_move(_command(Vector2i(2, 1), [Vector2i(1, 1), Vector2i(2, 1)])), "Carrying command should start.")
	actor.advance_move(1.0)
	test.expect_float_approx(actor.get_segment_progress(), 0.5, "Quarter-speed carrying advances half a cell in one second.")


func _test_cancel_and_reset(fixture: Dictionary) -> void:
	_reset(fixture)
	var actor = fixture["actor"]
	var runtime = fixture["runtime"]
	test.expect_true(actor.start_move(_command(Vector2i(2, 1), [Vector2i(1, 1), Vector2i(2, 1)])), "Cancelable command should start.")
	actor.advance_move(0.25)
	actor.cancel_move()
	test.expect_equal(runtime.motion_state, RUNTIME.MotionState.BLOCKED, "Cancel enters Blocked.")
	test.expect_equal(runtime.anchor_cell, Vector2i(1, 1), "Cancel preserves the last reached anchor.")
	test.expect_float_approx(actor.get_segment_progress(), 0.0, "Cancel clears segment progress.")
	actor.reset_actor()
	test.expect_equal(runtime.motion_state, RUNTIME.MotionState.WAITING, "Reset restores Waiting.")
	test.expect_false(runtime.arm_has_item, "Reset clears carried-item state.")


func _test_non_movable_definition() -> void:
	var fixture := _fixture(false)
	var actor = fixture["actor"]
	test.expect_false(
		actor.start_move(_command(Vector2i(2, 1), [Vector2i(1, 1), Vector2i(2, 1)])),
		"Definitions without can_move reject commands."
	)
	_free_fixture(fixture)


func _command(target: Vector2i, path: Array[Vector2i]):
	var command := COMMAND.new()
	test.expect_true(command.configure(target, path), "Test command should configure.")
	return command


func _reset(fixture: Dictionary) -> void:
	fixture["controller"].grid_transform = Transform3D.IDENTITY
	fixture["actor"].reset_actor()


func _free_fixture(fixture: Dictionary) -> void:
	fixture["actor"].queue_free()
	fixture["controller"].queue_free()

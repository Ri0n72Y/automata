extends SceneTree

const VEHICLE_DEFINITION_SCRIPT := preload("res://scripts/vehicles/vehicle_definition.gd")
const VEHICLE_RUNTIME_STATE_SCRIPT := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const VEHICLE_ACTOR_SCRIPT := preload("res://scripts/vehicles/vehicle_actor.gd")
const MOVE_COMMAND_SCRIPT := preload("res://scripts/vehicles/move_command.gd")

var failures: int = 0


class FakeController extends Node:
	func grid_footprint_center_to_world(anchor: Vector2i, footprint: Vector2i) -> Vector3:
		return Vector3(
			float(anchor.x) + float(footprint.x) * 0.5,
			0.0,
			float(anchor.y) + float(footprint.y) * 0.5
		)

	func get_grid_world_basis() -> Basis:
		return Basis.IDENTITY


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
			PackedStringArray([VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_MOVE])
		),
		"Vehicle definition should configure."
	)

	var runtime_state := VEHICLE_RUNTIME_STATE_SCRIPT.new()
	_expect_true(
		runtime_state.configure(definition, Vector2i(1, 1)),
		"Vehicle runtime state should configure."
	)

	var controller := FakeController.new()
	get_root().add_child(controller)
	var actor := VEHICLE_ACTOR_SCRIPT.new()
	get_root().add_child(actor)
	_expect_true(
		actor.configure(definition, runtime_state, controller, 1.0),
		"Vehicle actor should configure."
	)

	var command := MOVE_COMMAND_SCRIPT.new()
	command.configure(
		Vector2i(3, 1),
		[Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]
	)
	_expect_true(actor.start_move(command), "A valid planned path should start moving.")
	_expect_equal(
		runtime_state.motion_state,
		VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.MOVING,
		"Starting a move should set runtime state to Moving."
	)
	_expect_true(runtime_state.active_move_command == command, "Runtime state should own the active command.")

	actor.advance_move(0.25)
	_expect_equal(
		runtime_state.anchor_cell,
		Vector2i(1, 1),
		"Anchor should not change before reaching the next path node."
	)
	actor.advance_move(0.25)
	_expect_equal(
		runtime_state.anchor_cell,
		Vector2i(2, 1),
		"Anchor should update after reaching the next path node."
	)
	_expect_equal(command.path_index, 1, "Command should advance exactly one path node.")

	actor.advance_move(0.5)
	_expect_equal(runtime_state.anchor_cell, Vector2i(3, 1), "Vehicle should reach its target anchor.")
	_expect_equal(
		runtime_state.motion_state,
		VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.WAITING,
		"Vehicle should return to Waiting after arrival."
	)
	_expect_true(runtime_state.active_move_command == null, "Completed commands should be released from runtime state.")
	_expect_equal(command.state, MOVE_COMMAND_SCRIPT.State.WAITING, "Completed command should enter Waiting.")

	var invalid_command := MOVE_COMMAND_SCRIPT.new()
	invalid_command.configure(Vector2i(4, 1), [])
	_expect_true(not actor.start_move(invalid_command), "A blocked command must not start.")

	var reset_command := MOVE_COMMAND_SCRIPT.new()
	reset_command.configure(
		Vector2i(4, 1),
		[Vector2i(3, 1), Vector2i(4, 1)]
	)
	_expect_true(actor.start_move(reset_command), "A second valid command should start.")
	actor.advance_move(0.1)
	actor.reset_actor()
	_expect_equal(runtime_state.anchor_cell, Vector2i(1, 1), "Reset should restore the initial anchor.")
	_expect_equal(
		runtime_state.motion_state,
		VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.WAITING,
		"Reset should restore Waiting state."
	)
	_expect_true(runtime_state.active_move_command == null, "Reset should clear the active command.")

	actor.queue_free()
	controller.queue_free()
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


func _expect_true(value: bool, message: String) -> void:
	if value:
		return
	failures += 1
	push_error(message)

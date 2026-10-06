extends SceneTree

const DEFINITION := preload("res://scripts/vehicles/vehicle_definition.gd")
const RUNTIME := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const ACTOR := preload("res://scripts/vehicles/vehicle_actor.gd")
const SELECTION := preload("res://scripts/input/vehicle_selection_controller.gd")
const GRID_SELECTION := preload("res://scripts/input/grid_selection_controller.gd")
const MOVE_CONTROLLER := preload("res://scripts/input/vehicle_move_controller.gd")
const CONTRACT := preload("res://tests/support/contract_test.gd")

var test := CONTRACT.new()


class FakeController extends Node3D:
	func grid_footprint_center_to_world(anchor: Vector2i, footprint: Vector2i) -> Vector3:
		return Vector3(
			float(anchor.x) + float(footprint.x) * 0.5,
			0.0,
			float(anchor.y) + float(footprint.y) * 0.5
		)

	func get_grid_world_basis() -> Basis:
		return Basis.IDENTITY


class FakeManager extends Node:
	var vehicle: Node

	func get_vehicle_by_id(vehicle_id: StringName) -> Node:
		if vehicle != null and vehicle.call("get_vehicle_id") == vehicle_id:
			return vehicle
		return null


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var definition := DEFINITION.new()
	test.expect_true(definition.configure(
		&"test_vehicle",
		"Test Vehicle",
		DEFINITION.VehicleKind.ARM,
		Vector2i.ONE,
		2.0,
		10.0,
		0.0,
		5.0,
		PackedStringArray([DEFINITION.CAPABILITY_CAN_MOVE]),
		1.0
	), "Move-capable definition should configure.")

	var runtime := RUNTIME.new()
	test.expect_true(runtime.configure(definition, Vector2i(1, 1)), "Runtime should configure.")

	var controller := FakeController.new()
	root.add_child(controller)
	var actor := ACTOR.new()
	root.add_child(actor)
	test.expect_true(actor.configure(definition, runtime, controller, 1.0), "Actor should configure.")

	var manager := FakeManager.new()
	manager.vehicle = actor
	var selection := SELECTION.new()
	selection.configure(null, manager)
	test.expect_true(selection.select_vehicle(actor), "Selection fixture should own the test vehicle.")

	var grid_selection := GRID_SELECTION.new()
	var move_controller := MOVE_CONTROLLER.new()
	move_controller.configure(controller, selection, grid_selection, null)

	var move_requests: Array[Vector2i] = []
	var selected_targets: Array[Dictionary] = []
	move_controller.move_requested.connect(
		func(_vehicle_id: StringName, target: Vector2i) -> void:
			move_requests.append(target)
	)
	move_controller.move_target_selected.connect(
		func(vehicle_id: StringName, target: Vector2i) -> void:
			selected_targets.append({"vehicle_id": vehicle_id, "target": target})
	)

	var author_target := Vector2i(4, 3)
	test.expect_true(
		move_controller.begin_selected_move_target_selection(MOVE_CONTROLLER.TargetCommitMode.SELECT_ONLY),
		"SELECT_ONLY should reuse the existing live target selector."
	)
	grid_selection.selection_confirmed.emit(author_target)
	test.expect_equal(move_requests.size(), 0, "SELECT_ONLY confirmation must not dispatch gameplay Move.")
	test.expect_equal(selected_targets.size(), 1, "SELECT_ONLY confirmation should surface one target result.")
	if selected_targets.size() == 1:
		test.expect_equal(selected_targets[0].get("vehicle_id"), &"test_vehicle", "Target result should preserve selected vehicle id.")
		test.expect_equal(selected_targets[0].get("target"), author_target, "Target result should preserve confirmed grid cell.")
	test.expect_equal(runtime.anchor_cell, Vector2i(1, 1), "SELECT_ONLY confirmation must not mutate runtime position.")
	test.expect_equal(runtime.motion_state, RUNTIME.MotionState.WAITING, "SELECT_ONLY confirmation must not start gameplay lifecycle.")
	test.expect_false(grid_selection.is_live_target_mode(), "SELECT_ONLY confirmation should finish live target mode.")

	test.expect_true(
		move_controller.begin_selected_move_target_selection(MOVE_CONTROLLER.TargetCommitMode.EXECUTE),
		"EXECUTE should still enter the same live target selector."
	)
	test.expect_true(runtime.begin_move_planning(), "Fixture should make execution reject before pathfinding.")
	var manual_target := Vector2i(2, 1)
	grid_selection.selection_confirmed.emit(manual_target)
	test.expect_equal(move_requests, [manual_target], "EXECUTE confirmation must still dispatch the gameplay Move entrypoint.")
	test.expect_equal(selected_targets.size(), 1, "EXECUTE confirmation must not surface a SELECT_ONLY result.")
	runtime.fail_move_planning()
	grid_selection.deactivate_live_target_mode()

	manager.vehicle = null
	move_controller.free()
	grid_selection.free()
	selection.free()
	manager.free()
	actor.queue_free()
	controller.queue_free()
	await process_frame
	test.finish(self, "Move target commit boundary stability tests")

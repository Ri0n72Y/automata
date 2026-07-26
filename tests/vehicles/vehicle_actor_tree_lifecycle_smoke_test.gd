extends SceneTree

const VEHICLE_DEFINITION_SCRIPT := preload("res://scripts/vehicles/vehicle_definition.gd")
const VEHICLE_RUNTIME_STATE_SCRIPT := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const VEHICLE_ACTOR_SCRIPT := preload("res://scripts/vehicles/vehicle_actor.gd")

var failures: int = 0


class ControllerStub extends Node3D:
	func grid_footprint_center_to_world(
		anchor_cell: Vector2i,
		footprint: Vector2i
	) -> Vector3:
		return Vector3(
			float(anchor_cell.x) + float(footprint.x) * 0.5,
			0.0,
			float(anchor_cell.y) + float(footprint.y) * 0.5
		)

	func get_grid_world_basis() -> Basis:
		return Basis.IDENTITY


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame

	var definition: VehicleDefinition = _create_definition()
	var runtime := VEHICLE_RUNTIME_STATE_SCRIPT.new()
	var controller := ControllerStub.new()
	var actor := VEHICLE_ACTOR_SCRIPT.new()

	_expect_true(definition != null, "Definition should configure.")
	if definition == null:
		_finish(actor, controller)
		return
	_expect_true(
		runtime.configure(definition, Vector2i(2, 3)),
		"Runtime should configure."
	)
	_expect_true(
		actor.configure(definition, runtime, controller, 1.0),
		"Detached actor should configure without requiring a global transform."
	)
	_expect_false(actor.is_inside_tree(), "Actor should still be detached after configure.")

	root.add_child(controller)
	controller.add_child(actor)
	await process_frame

	_expect_true(actor.is_inside_tree(), "Actor should enter the tree after attachment.")
	if actor.is_inside_tree():
		_expect_equal(
			actor.global_position,
			Vector3(3.0, 0.0, 4.0),
			"Actor should apply its runtime transform after entering the tree."
		)

	_finish(actor, controller)


func _create_definition() -> VehicleDefinition:
	var definition := VEHICLE_DEFINITION_SCRIPT.new()
	if not definition.configure(
		&"tree_lifecycle_vehicle",
		"Tree Lifecycle Vehicle",
		VEHICLE_DEFINITION_SCRIPT.VehicleKind.ARM,
		Vector2i(2, 2),
		2.0,
		10.0,
		10.0,
		20.0,
		PackedStringArray([VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_MOVE]),
		1.0,
		0
	):
		return null
	return definition


func _finish(actor: Node, controller: Node) -> void:
	if actor != null and is_instance_valid(actor):
		if actor.get_parent() != null:
			actor.get_parent().remove_child(actor)
		actor.free()
	if controller != null and is_instance_valid(controller):
		if controller.get_parent() != null:
			controller.get_parent().remove_child(controller)
		controller.free()

	if failures == 0:
		print("Vehicle actor tree lifecycle smoke tests passed.")
		quit(0)
		return
	push_error("Vehicle actor tree lifecycle smoke tests failed: %d failure(s)." % failures)
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

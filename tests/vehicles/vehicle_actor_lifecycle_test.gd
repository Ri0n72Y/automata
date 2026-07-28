extends SceneTree

const DEFINITION := preload("res://scripts/vehicles/vehicle_definition.gd")
const RUNTIME := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const ACTOR := preload("res://scripts/vehicles/vehicle_actor.gd")
const CONTRACT := preload("res://tests/support/contract_test.gd")

var test := CONTRACT.new()


class ControllerStub extends Node3D:
	func grid_footprint_center_to_world(anchor: Vector2i, footprint: Vector2i) -> Vector3:
		return Vector3(
			float(anchor.x) + float(footprint.x - 1) * 0.5,
			0.0,
			float(anchor.y) + float(footprint.y - 1) * 0.5
		)

	func get_grid_world_basis() -> Basis:
		return global_basis


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var definition := _definition()
	var runtime := RUNTIME.new()
	var controller := ControllerStub.new()
	var actor := ACTOR.new()
	test.expect_true(definition != null, "Lifecycle definition should configure.")
	if definition != null:
		test.expect_true(runtime.configure(definition, Vector2i(2, 3), RUNTIME.Facing.NORTH), "Lifecycle runtime should configure.")
		test.expect_true(actor.configure(definition, runtime, controller, 1.0), "Detached Actor should configure.")
		test.expect_false(actor.is_inside_tree(), "Configure should not require Actor tree attachment.")
		test.expect_equal(actor.global_position, Vector3.ZERO, "Detached Actor should not attempt global transform synchronization.")

		root.add_child(controller)
		controller.add_child(actor)
		await process_frame
		test.expect_true(actor.is_inside_tree(), "Actor should enter the tree after attachment.")
		test.expect_vector3_approx(actor.global_position, Vector3(2.5, 0.0, 3.5), "Tree entry should synchronize the runtime anchor.")

		controller.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(4.0, 0.0, -2.0))
		actor.sync_from_state()
		test.expect_vector3_approx(
			actor.global_position,
			controller.grid_footprint_center_to_world(runtime.anchor_cell, definition.footprint),
			"Attached Actor should follow controller transforms."
		)

		controller.remove_child(actor)
		test.expect_false(actor.is_inside_tree(), "Actor should leave the tree after detachment.")
		actor.sync_from_state()
		test.expect_false(actor.is_inside_tree(), "Detached synchronization should remain safe.")

	actor.free()
	if controller.get_parent() != null:
		controller.get_parent().remove_child(controller)
	controller.free()
	test.finish(self, "Vehicle actor lifecycle tests")


func _definition():
	var definition := DEFINITION.new()
	if not definition.configure(
		&"tree_lifecycle_vehicle", "Tree Lifecycle Vehicle", DEFINITION.VehicleKind.ARM,
		Vector2i(2, 2), 2.0, 10.0, 10.0, 20.0,
		PackedStringArray([DEFINITION.CAPABILITY_CAN_MOVE]), 1.0, 0
	):
		return null
	return definition

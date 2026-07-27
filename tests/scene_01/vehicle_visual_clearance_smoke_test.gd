extends SceneTree

const ARM_SCENE := preload("res://scenes/scene_01/vehicles/arm_vehicle_placeholder.tscn")
const TRANSPORT_SCENE := preload("res://scenes/scene_01/vehicles/transport_vehicle_placeholder.tscn")

const MINIMUM_CLEARANCE := 0.04

var failures: int = 0


func _init() -> void:
	_test_vehicle_clearance(ARM_SCENE, "Arm vehicle")
	_test_vehicle_clearance(TRANSPORT_SCENE, "Transport vehicle")

	if failures == 0:
		print("Vehicle visual clearance smoke tests passed.")
		quit(0)
		return
	push_error("Vehicle visual clearance tests failed: %d failure(s)." % failures)
	quit(1)


func _test_vehicle_clearance(scene_resource: PackedScene, context: String) -> void:
	var vehicle := scene_resource.instantiate()
	var body := vehicle.get_node_or_null("VisualRoot/Body") as MeshInstance3D
	var wheel := vehicle.get_node_or_null("VisualRoot/WheelFrontLeft") as MeshInstance3D
	_expect_true(body != null, "%s should contain a body mesh." % context)
	_expect_true(wheel != null, "%s should contain a wheel mesh." % context)
	if body == null or wheel == null:
		vehicle.free()
		return

	var body_mesh := body.mesh as BoxMesh
	var wheel_mesh := wheel.mesh as CylinderMesh
	_expect_true(body_mesh != null, "%s body should use BoxMesh." % context)
	_expect_true(wheel_mesh != null, "%s wheel should use CylinderMesh." % context)
	if body_mesh == null or wheel_mesh == null:
		vehicle.free()
		return

	var body_outer_x := absf(body.position.x) + body_mesh.size.x * 0.5
	var wheel_outer_x := absf(wheel.position.x) + wheel_mesh.height * 0.5
	var body_outer_z := absf(body.position.z) + body_mesh.size.z * 0.5
	var wheel_outer_z := absf(wheel.position.z) + wheel_mesh.top_radius
	_expect_true(
		wheel_outer_x - body_outer_x >= MINIMUM_CLEARANCE,
		"%s wheels should protrude beyond the chassis in X without coplanar overlap." % context
	)
	_expect_true(
		wheel_outer_z - body_outer_z >= MINIMUM_CLEARANCE,
		"%s wheels should protrude beyond the chassis in Z without coplanar overlap." % context
	)
	vehicle.free()


func _expect_true(value: bool, message: String) -> void:
	if value:
		return
	failures += 1
	push_error(message)
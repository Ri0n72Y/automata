extends SceneTree

const ARM_SCENE := preload("res://scenes/scene_01/vehicles/arm_vehicle_placeholder.tscn")
const TRANSPORT_SCENE := preload("res://scenes/scene_01/vehicles/transport_vehicle_placeholder.tscn")
const CONTRACT := preload("res://tests/support/contract_test.gd")

const MINIMUM_CLEARANCE := 0.04

var test := CONTRACT.new()


func _init() -> void:
	var cases: Array[Dictionary] = [
		{"name": "arm vehicle", "scene": ARM_SCENE},
		{"name": "transport vehicle", "scene": TRANSPORT_SCENE},
	]
	for case in cases:
		_test_vehicle_geometry(case["scene"], case["name"])
	test.finish(self, "Vehicle visual contract tests")


func _test_vehicle_geometry(scene_resource: PackedScene, context: String) -> void:
	var vehicle := scene_resource.instantiate()
	var body := vehicle.get_node_or_null("VisualRoot/Body") as MeshInstance3D
	var wheel_names := ["WheelFrontLeft", "WheelFrontRight", "WheelRearLeft", "WheelRearRight"]
	test.expect_true(body != null, "%s should contain a body mesh." % context)
	if body == null:
		vehicle.free()
		return
	var body_mesh := body.mesh as BoxMesh
	test.expect_true(body_mesh != null, "%s body should use BoxMesh." % context)
	if body_mesh == null:
		vehicle.free()
		return

	for wheel_name in wheel_names:
		var wheel := vehicle.get_node_or_null("VisualRoot/%s" % wheel_name) as MeshInstance3D
		test.expect_true(wheel != null, "%s should contain %s." % [context, wheel_name])
		if wheel == null:
			continue
		var wheel_mesh := wheel.mesh as CylinderMesh
		test.expect_true(wheel_mesh != null, "%s %s should use CylinderMesh." % [context, wheel_name])
		if wheel_mesh == null:
			continue
		var body_outer_x := absf(body.position.x) + body_mesh.size.x * 0.5
		var body_outer_z := absf(body.position.z) + body_mesh.size.z * 0.5
		var wheel_outer_x := absf(wheel.position.x) + wheel_mesh.height * 0.5
		var wheel_outer_z := absf(wheel.position.z) + wheel_mesh.top_radius
		test.expect_true(
			wheel_outer_x - body_outer_x >= MINIMUM_CLEARANCE,
			"%s %s should protrude beyond the chassis in X." % [context, wheel_name]
		)
		test.expect_true(
			wheel_outer_z - body_outer_z >= MINIMUM_CLEARANCE,
			"%s %s should protrude beyond the chassis in Z." % [context, wheel_name]
		)
	vehicle.free()

extends SceneTree

const MAIN_SCENE := preload("res://scenes/scene_01/scene_01_basic_packing.tscn")
const SHOWCASE_SCENE := preload("res://scenes/scene_01/scene_01_vehicle_showcase.tscn")
const ARM_SCENE := preload("res://scenes/scene_01/vehicles/arm_vehicle_placeholder.tscn")
const TRANSPORT_SCENE := preload("res://scenes/scene_01/vehicles/transport_vehicle_placeholder.tscn")
const CAMERA_SCENE := preload("res://scenes/scene_01/components/scene_01_camera_lighting.tscn")
const UI_SCENE := preload("res://scenes/scene_01/components/scene_01_manual_ui.tscn")
const CONTRACT := preload("res://tests/support/contract_test.gd")

var test := CONTRACT.new()


func _init() -> void:
	_test_resource_path_matrix()
	_test_vehicle_visual_structure()
	_test_camera_and_ui_structure()
	test.finish(self, "Scene 01 static resource contract tests")


func _test_resource_path_matrix() -> void:
	var cases: Array[Dictionary] = [
		{
			"name": "main scene",
			"scene": MAIN_SCENE,
			"paths": [
				"SceneRoot/GridRoot/GridTileView",
				"SceneRoot/RobotRoot/Scene01VehicleManager/ArmVehicle",
				"SceneRoot/RobotRoot/Scene01VehicleManager/TransportVehicle",
				"SceneRoot/CameraRoot/Scene01CameraRig",
				"UIRoot",
			],
		},
		{
			"name": "showcase scene",
			"scene": SHOWCASE_SCENE,
			"paths": ["ArmVehicle", "TransportVehicle", "Floor"],
		},
	]
	for case in cases:
		var instance := case["scene"].instantiate()
		for path in case["paths"]:
			test.expect_true(instance.get_node_or_null(path) != null, "%s should expose %s." % [case["name"], path])
		instance.free()


func _test_vehicle_visual_structure() -> void:
	var cases: Array[Dictionary] = [
		{
			"name": "arm",
			"scene": ARM_SCENE,
			"required": ["VisualRoot/Body", "VisualRoot/WheelFrontLeft", "VisualRoot/ArmColumn", "VisualRoot/ArmBeam", "VisualRoot/WorkHead", "VisualRoot/DirectionMarker"],
			"material_pair": ["VisualRoot/Body", "VisualRoot/ArmColumn"],
		},
		{
			"name": "transport",
			"scene": TRANSPORT_SCENE,
			"required": ["VisualRoot/Body", "VisualRoot/WheelFrontLeft", "VisualRoot/Tray", "VisualRoot/TrayRailLeft", "VisualRoot/DirectionMarker"],
			"material_pair": ["VisualRoot/Body", "VisualRoot/Tray"],
		},
	]
	var bodies: Array[MeshInstance3D] = []
	for case in cases:
		var vehicle := case["scene"].instantiate()
		for path in case["required"]:
			test.expect_true(vehicle.get_node_or_null(path) != null, "%s vehicle should expose %s." % [case["name"], path])
		var first := vehicle.get_node_or_null(case["material_pair"][0]) as MeshInstance3D
		var second := vehicle.get_node_or_null(case["material_pair"][1]) as MeshInstance3D
		_expect_materials_differ(first, second, "%s primary parts should be visually distinct." % case["name"])
		bodies.append(vehicle.get_node_or_null("VisualRoot/Body") as MeshInstance3D)
		vehicle.set_meta("deferred_free_for_test", true)
		vehicle.free()
	# Cross-preset distinction is checked by the retained resource colors before instances are freed.
	var arm := ARM_SCENE.instantiate()
	var transport := TRANSPORT_SCENE.instantiate()
	_expect_materials_differ(
		arm.get_node_or_null("VisualRoot/Body") as MeshInstance3D,
		transport.get_node_or_null("VisualRoot/Body") as MeshInstance3D,
		"Arm and transport chassis should be visually distinct."
	)
	arm.free()
	transport.free()


func _test_camera_and_ui_structure() -> void:
	var camera_scene := CAMERA_SCENE.instantiate()
	var camera := camera_scene.get_node_or_null("SceneCamera") as Camera3D
	test.expect_true(camera != null, "Camera resource should expose SceneCamera.")
	if camera != null:
		test.expect_equal(camera.projection, Camera3D.PROJECTION_ORTHOGONAL, "Static camera should be orthographic.")
	for path in ["KeyLight", "FillLight", "WorldEnvironment"]:
		test.expect_true(camera_scene.get_node_or_null(path) != null, "Camera resource should expose %s." % path)
	camera_scene.free()

	var ui := UI_SCENE.instantiate()
	for path in [
		"RootControl/Panel/Margin/VBox/RotateRow/RotateLeft",
		"RootControl/Panel/Margin/VBox/TransformRow/Scale",
		"RootControl/Panel/Margin/VBox/ResetRow/Reset",
	]:
		test.expect_true(ui.get_node_or_null(path) != null, "Manual UI should expose %s." % path)
	ui.free()


func _expect_materials_differ(first: MeshInstance3D, second: MeshInstance3D, message: String) -> void:
	test.expect_true(first != null and second != null, message + " Meshes should exist.")
	if first == null or second == null:
		return
	var first_material := first.material_override as StandardMaterial3D
	var second_material := second.material_override as StandardMaterial3D
	test.expect_true(
		first_material != null and second_material != null and first_material.albedo_color != second_material.albedo_color,
		message
	)

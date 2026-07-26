extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/scene_01/scene_01_basic_packing.tscn")
const SHOWCASE_SCENE: PackedScene = preload("res://scenes/scene_01/scene_01_vehicle_showcase.tscn")
const FIELD_SCENE: PackedScene = preload("res://scenes/scene_01/components/scene_01_field_12x8.tscn")
const ARM_SCENE: PackedScene = preload("res://scenes/scene_01/vehicles/arm_vehicle_placeholder.tscn")
const TRANSPORT_SCENE: PackedScene = preload("res://scenes/scene_01/vehicles/transport_vehicle_placeholder.tscn")
const CAMERA_SCENE: PackedScene = preload("res://scenes/scene_01/components/scene_01_camera_lighting.tscn")
const UI_SCENE: PackedScene = preload("res://scenes/scene_01/components/scene_01_manual_ui.tscn")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_main_scene_structure()
	_test_static_field()
	_test_vehicle_resources()
	_test_camera_and_ui_resources()
	_test_showcase_scene()

	if failures == 0:
		print("Scene 01 static resource smoke tests passed.")
		quit(0)
		return
	push_error("Scene 01 static resource smoke tests failed: %d failure(s)." % failures)
	quit(1)


func _test_main_scene_structure() -> void:
	var scene: Node = MAIN_SCENE.instantiate()
	_expect_node(scene, "SceneRoot/GridRoot/GridTileView", "Main scene should instance the static field.")
	_expect_node(scene, "SceneRoot/RobotRoot/Scene01VehicleManager/ArmVehicle", "Main scene should contain the static arm vehicle instance.")
	_expect_node(scene, "SceneRoot/RobotRoot/Scene01VehicleManager/TransportVehicle", "Main scene should contain the static transport vehicle instance.")
	_expect_node(scene, "SceneRoot/CameraRoot/Scene01CameraRig", "Main scene should instance static camera and lighting.")
	_expect_node(scene, "UIRoot", "Main scene should instance the static manual UI.")
	scene.free()


func _test_static_field() -> void:
	var field: Node = FIELD_SCENE.instantiate()
	var tile_count: int = 0
	for cell_y in range(8):
		for cell_x in range(12):
			var tile_path := "Tiles/Row_%d/Tile_%d" % [cell_y, cell_x]
			if field.get_node_or_null(tile_path) != null:
				tile_count += 1
	_expect_equal(tile_count, 96, "Static field should expose all 96 editor-visible tiles.")
	_expect_node(field, "GroundBody/GroundShape", "Static field should include ground collision.")
	field.free()


func _test_vehicle_resources() -> void:
	var arm: Node = ARM_SCENE.instantiate()
	var transport: Node = TRANSPORT_SCENE.instantiate()

	_expect_node(arm, "VisualRoot/Body", "Arm vehicle should have a chassis.")
	_expect_node(arm, "VisualRoot/WheelFrontLeft", "Arm vehicle should have visible wheels.")
	_expect_node(arm, "VisualRoot/ArmColumn", "Arm vehicle should have an arm column.")
	_expect_node(arm, "VisualRoot/ArmBeam", "Arm vehicle should have an arm beam.")
	_expect_node(arm, "VisualRoot/WorkHead", "Arm vehicle should have a work head.")
	_expect_node(arm, "VisualRoot/DirectionMarker", "Arm vehicle should expose its facing marker.")

	_expect_node(transport, "VisualRoot/Body", "Transport vehicle should have a chassis.")
	_expect_node(transport, "VisualRoot/WheelFrontLeft", "Transport vehicle should have visible wheels.")
	_expect_node(transport, "VisualRoot/Tray", "Transport vehicle should have a tray.")
	_expect_node(transport, "VisualRoot/TrayRailLeft", "Transport vehicle should have tray rails.")
	_expect_node(transport, "VisualRoot/DirectionMarker", "Transport vehicle should expose its facing marker.")

	var arm_body := arm.get_node_or_null("VisualRoot/Body") as MeshInstance3D
	var arm_column := arm.get_node_or_null("VisualRoot/ArmColumn") as MeshInstance3D
	var transport_body := transport.get_node_or_null("VisualRoot/Body") as MeshInstance3D
	var transport_tray := transport.get_node_or_null("VisualRoot/Tray") as MeshInstance3D
	_expect_materials_differ(arm_body, arm_column, "Arm chassis and work support should use different materials.")
	_expect_materials_differ(transport_body, transport_tray, "Transport chassis and tray should use different materials.")
	_expect_materials_differ(arm_body, transport_body, "The two vehicle chassis should be visually distinct.")

	arm.free()
	transport.free()


func _test_camera_and_ui_resources() -> void:
	var camera_scene: Node = CAMERA_SCENE.instantiate()
	var camera := camera_scene.get_node_or_null("SceneCamera") as Camera3D
	_expect_true(camera != null, "Static camera resource should include SceneCamera.")
	if camera != null:
		_expect_equal(camera.projection, Camera3D.PROJECTION_ORTHOGONAL, "Static camera should be orthographic.")
	_expect_node(camera_scene, "KeyLight", "Static camera resource should include a key light.")
	_expect_node(camera_scene, "FillLight", "Static camera resource should include a fill light.")
	_expect_node(camera_scene, "WorldEnvironment", "Static camera resource should include an environment.")
	camera_scene.free()

	var ui: Node = UI_SCENE.instantiate()
	_expect_node(ui, "RootControl/Panel/Margin/VBox/RotateRow/RotateLeft", "Manual UI should expose rotation controls.")
	_expect_node(ui, "RootControl/Panel/Margin/VBox/TransformRow/Scale", "Manual UI should expose scale controls.")
	_expect_node(ui, "RootControl/Panel/Margin/VBox/ResetRow/Reset", "Manual UI should expose reset controls.")
	ui.free()


func _test_showcase_scene() -> void:
	var showcase: Node = SHOWCASE_SCENE.instantiate()
	_expect_node(showcase, "ArmVehicle", "Showcase should contain the arm vehicle resource.")
	_expect_node(showcase, "TransportVehicle", "Showcase should contain the transport vehicle resource.")
	_expect_node(showcase, "Floor", "Showcase should contain a static floor.")
	showcase.free()


func _expect_materials_differ(first: MeshInstance3D, second: MeshInstance3D, message: String) -> void:
	if first == null or second == null:
		failures += 1
		push_error(message + " Missing mesh instance.")
		return
	var first_material := first.material_override as StandardMaterial3D
	var second_material := second.material_override as StandardMaterial3D
	if first_material != null and second_material != null and first_material.albedo_color != second_material.albedo_color:
		return
	failures += 1
	push_error(message)


func _expect_node(root_node: Node, path: String, message: String) -> void:
	if root_node != null and root_node.get_node_or_null(path) != null:
		return
	failures += 1
	push_error(message + " Missing path: " + path)


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

extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/scene_01/scene_01_basic_packing.tscn")
const SHOWCASE_SCENE: PackedScene = preload("res://scenes/scene_01/scene_01_vehicle_showcase.tscn")
const FIELD_SCENE: PackedScene = preload("res://scenes/scene_01/components/scene_01_field_12x8.tscn")
const ARM_SCENE: PackedScene = preload("res://scenes/scene_01/vehicles/arm_vehicle_placeholder.tscn")
const TRANSPORT_SCENE: PackedScene = preload("res://scenes/scene_01/vehicles/transport_vehicle_placeholder.tscn")
const CAMERA_SCENE: PackedScene = preload("res://scenes/scene_01/components/scene_01_camera_lighting.tscn")
const UI_SCENE: PackedScene = preload("res://scenes/scene_01/components/scene_01_manual_ui.tscn")
const GRID_MODEL_SCRIPT := preload("res://scripts/grid/grid_model.gd")
const VEHICLE_MANAGER_SCRIPT := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_main_scene_structure()
	_test_static_field()
	_test_dynamic_field_fallback()
	_test_vehicle_resources()
	_test_incomplete_static_manager_rejected()
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
	_expect_node(field, "Tiles/GroundBody/GroundShape", "Static field should include ground collision.")
	field.free()


func _test_dynamic_field_fallback() -> void:
	var field: Node = FIELD_SCENE.instantiate()
	var static_model := GRID_MODEL_SCRIPT.new()
	_expect_true(
		static_model.configure(12, 8, 1.0, Vector3.ZERO),
		"Default static-grid model should configure."
	)
	field.call("draw", static_model)
	_expect_true(bool(field.call("is_using_static_scene")), "A 12 x 8 model should use static tiles.")
	_expect_equal(int(field.call("get_tile_count")), 96, "Static mode should expose 96 tiles.")

	var large_model := GRID_MODEL_SCRIPT.new()
	_expect_true(
		large_model.configure(13, 8, 1.0, Vector3.ZERO),
		"A 13 x 8 model should configure for dynamic fallback."
	)
	field.call("draw", large_model)
	_expect_true(bool(field.call("is_using_dynamic_scene")), "A 13 x 8 model should use dynamic fallback.")
	_expect_equal(int(field.call("get_tile_count")), 104, "Dynamic fallback should expose every large-grid tile.")
	_expect_true(
		field.call("get_tile_node", Vector2i(12, 7)) != null,
		"Dynamic fallback queries should resolve cells outside the static capacity."
	)

	var static_tiles := field.get_node_or_null("Tiles") as Node3D
	var static_ground := field.get_node_or_null("Tiles/GroundBody") as StaticBody3D
	var active_ground := field.call("get_ground_body") as StaticBody3D
	_expect_true(static_tiles != null and not static_tiles.visible, "Inactive static tiles should be hidden.")
	_expect_true(static_ground != null and static_ground.collision_layer == 0, "Inactive static ground collision should be disabled.")
	_expect_true(active_ground != null and active_ground != static_ground, "Dynamic mode should expose its own active ground body.")
	if active_ground != null:
		_expect_equal(active_ground.collision_layer, 1, "Dynamic ground should own the active ground collision layer.")

	field.call("draw", static_model)
	_expect_true(bool(field.call("is_using_static_scene")), "Returning to 12 x 8 should reactivate static tiles.")
	_expect_true(static_tiles != null and static_tiles.visible, "Static tiles should become visible again.")
	_expect_true(static_ground != null and static_ground.collision_layer == 1, "Static ground collision should be restored.")
	_expect_true(field.call("get_ground_body") == static_ground, "Static queries should return the restored static ground body.")
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


func _test_incomplete_static_manager_rejected() -> void:
	var manager := VEHICLE_MANAGER_SCRIPT.new()
	var arm: Node = ARM_SCENE.instantiate()
	manager.add_child(arm)
	var controller := Node.new()
	var configured := bool(_call_with_expected_errors_suppressed(
		Callable(manager, "configure").bind(controller, 1.0)
	))
	_expect_false(configured, "A manager with only one static preset should reject configuration.")
	_expect_equal(manager.get_child_count(), 1, "Rejected static configuration should not add dynamic vehicles.")
	_expect_false(manager.has_pending_vehicle_batch(), "Rejected static configuration should not retain a dynamic batch.")
	controller.free()
	manager.free()


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
	_expect_node(ui, "RootControl/Panel/Margin/VBox/TransformRow/Offset", "Manual UI should expose offset controls.")
	_expect_node(ui, "RootControl/Panel/Margin/VBox/ResetRow/Reset", "Manual UI should expose reset controls.")
	ui.free()


func _test_showcase_scene() -> void:
	var showcase: Node = SHOWCASE_SCENE.instantiate()
	_expect_node(showcase, "ArmVehicle", "Showcase should contain the arm vehicle resource.")
	_expect_node(showcase, "TransportVehicle", "Showcase should contain the transport vehicle resource.")
	_expect_node(showcase, "Floor", "Showcase should contain a static floor.")
	showcase.free()


func _call_with_expected_errors_suppressed(callback: Callable) -> Variant:
	var previous_print_error_messages := Engine.print_error_messages
	Engine.print_error_messages = false
	var result: Variant = callback.call()
	Engine.print_error_messages = previous_print_error_messages
	return result


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


func _expect_false(value: bool, message: String) -> void:
	if not value:
		return
	failures += 1
	push_error(message)

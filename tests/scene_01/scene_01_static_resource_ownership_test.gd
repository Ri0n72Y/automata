extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const ARM_DEFINITION_PATH := "res://scenes/scene_01/vehicles/definitions/arm_vehicle_definition.tres"
const TRANSPORT_DEFINITION_PATH := "res://scenes/scene_01/vehicles/definitions/transport_vehicle_definition.tres"
const ManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const VehicleDefinitionScript := preload("res://scripts/vehicles/vehicle_definition.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var arm_resource := load(ARM_DEFINITION_PATH) as VehicleDefinitionScript
	var transport_resource := load(TRANSPORT_DEFINITION_PATH) as VehicleDefinitionScript
	_expect_true(arm_resource != null and arm_resource.is_configured(), "Arm definition should be a configured editor-visible Resource.")
	_expect_true(transport_resource != null and transport_resource.is_configured(), "Transport definition should be a configured editor-visible Resource.")
	if arm_resource != null:
		_expect_equal(arm_resource.resource_path, ARM_DEFINITION_PATH, "Arm definition should live in a .tres asset.")
	if transport_resource != null:
		_expect_equal(transport_resource.resource_path, TRANSPORT_DEFINITION_PATH, "Transport definition should live in a .tres asset.")

	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for static resource ownership.")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame

	var manager := scene.get_node_or_null("SceneRoot/RobotRoot/Scene01VehicleManager") as ManagerScript
	_expect_true(manager != null, "Scene 01 should expose the static vehicle manager.")
	if manager != null:
		var arm = manager.get_vehicle_by_id(ManagerScript.ARM_VEHICLE_ID)
		var transport = manager.get_vehicle_by_id(ManagerScript.TRANSPORT_VEHICLE_ID)
		_expect_true(arm != null and transport != null, "Static vehicle scenes should bind both definition resources.")
		if arm != null:
			_expect_equal(arm.definition.resource_path, ARM_DEFINITION_PATH, "Arm actor should keep the .tres definition bound in its scene.")
			_expect_true(arm.runtime_state != null and arm.runtime_state.definition == arm.definition, "Arm RuntimeState should reference the static definition instead of rebuilding it.")
		if transport != null:
			_expect_equal(transport.definition.resource_path, TRANSPORT_DEFINITION_PATH, "Transport actor should keep the .tres definition bound in its scene.")
			_expect_true(transport.runtime_state != null and transport.runtime_state.definition == transport.definition, "Transport RuntimeState should reference the static definition instead of rebuilding it.")

	scene.queue_free()
	await process_frame
	_finish()


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


func _finish() -> void:
	if failures == 0:
		print("Scene 01 static resource ownership tests passed.")
	quit(failures)

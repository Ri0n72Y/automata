extends SceneTree

const ASSEMBLY_CAPABILITIES_SCRIPT = preload("res://scripts/assembly/assembly_capabilities.gd")
const ADAPTER_SCRIPT = preload("res://scripts/scene_01/scene_01_assembly_definition_adapter.gd")
const VEHICLE_ACTOR_SCRIPT = preload("res://scripts/vehicles/vehicle_actor.gd")
const VEHICLE_DEFINITION_SCRIPT = preload("res://scripts/vehicles/vehicle_definition.gd")
const CONTRACT_TEST_SCRIPT = preload("res://tests/support/contract_test.gd")

var test = CONTRACT_TEST_SCRIPT.new()


func _init() -> void:
	_test_arm_preset_maps_to_compile_input()
	_test_transport_preset_maps_tray_interface_without_grab_drop()
	test.finish(self, "Scene 01 assembly definition adapter contract tests")


func _test_arm_preset_maps_to_compile_input() -> void:
	var actor = _make_actor(_make_arm_definition())
	var definition = ADAPTER_SCRIPT.new().build_definition(actor)
	test.expect_true(definition != null, "Configured arm preset should adapt to an assembly definition.")
	if definition == null:
		return
	test.expect_equal(definition.assembly_id, &"arm_vehicle", "Assembly id should preserve the vehicle id.")
	test.expect_equal(definition.revision, ADAPTER_SCRIPT.PRESET_REVISION, "Preset adapter should use a stable revision.")
	var components = definition.get_components()
	test.expect_equal(components.size(), 1, "Current preset bridge should emit one resolved component.")
	if components.size() != 1:
		return
	var component = components[0]
	test.expect_equal(component.occupied_cells.size(), 4, "2x2 arm preset should compile a four-cell envelope source.")
	test.expect_true(component.capabilities.has(ASSEMBLY_CAPABILITIES_SCRIPT.CAN_MOVE), "Arm preset should publish move capability.")
	test.expect_true(component.capabilities.has(ASSEMBLY_CAPABILITIES_SCRIPT.GRAB_DROP), "Arm preset should publish GrabDrop capability.")
	test.expect_equal(component.mass, 18.0, "Preset mass should map from VehicleDefinition total weight.")
	test.expect_equal(component.interaction_interfaces.size(), 1, "Arm preset should publish one GrabDrop interface template.")
	if component.interaction_interfaces.size() == 1:
		var interface_value = component.interaction_interfaces[0]
		test.expect_true(interface_value.is_component_local(), "Adapter output interface cells should be component-local.")
		test.expect_equal(interface_value.cells, [Vector2i(2, 0), Vector2i(2, 1)], "Arm interface template should match the east-facing 2x2 forward edge.")
		test.expect_equal(interface_value.metadata.get("orientation_mode"), "vehicle_facing", "Arm interface template should declare runtime facing rotation.")


func _test_transport_preset_maps_tray_interface_without_grab_drop() -> void:
	var actor = _make_actor(_make_transport_definition())
	var definition = ADAPTER_SCRIPT.new().build_definition(actor)
	test.expect_true(definition != null, "Configured transport preset should adapt to an assembly definition.")
	if definition == null:
		return
	var components = definition.get_components()
	if components.size() != 1:
		test.expect_equal(components.size(), 1, "Transport preset should emit one resolved component.")
		return
	var component = components[0]
	test.expect_true(component.capabilities.has(ASSEMBLY_CAPABILITIES_SCRIPT.CAN_MOVE), "Transport preset should publish move capability.")
	test.expect_false(component.capabilities.has(ASSEMBLY_CAPABILITIES_SCRIPT.GRAB_DROP), "Transport preset should not invent GrabDrop capability.")
	test.expect_equal(component.interaction_interfaces.size(), 1, "Transport preset should publish its tray interaction interface.")
	if component.interaction_interfaces.size() == 1:
		var interface_value = component.interaction_interfaces[0]
		test.expect_equal(interface_value.kind, ADAPTER_SCRIPT.TRAY_INTERFACE_KIND, "Transport interface should identify the tray interaction kind.")
		test.expect_true(interface_value.is_component_local(), "Tray interface cells should be component-local compile input.")
		test.expect_equal(
			interface_value.cells,
			[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
			"Tray interaction should cover the transport footprint."
		)
		test.expect_equal(interface_value.metadata.get("capacity"), 8, "Tray interface should preserve preset capacity.")


func _make_actor(definition):
	var actor = VEHICLE_ACTOR_SCRIPT.new()
	actor.definition = definition
	return actor


func _make_arm_definition():
	var definition = VEHICLE_DEFINITION_SCRIPT.new()
	test.expect_true(definition.configure(
		&"arm_vehicle",
		"Arm Vehicle",
		VEHICLE_DEFINITION_SCRIPT.VehicleKind.ARM,
		Vector2i(2, 2),
		2.0,
		18.0,
		20.0,
		30.0,
		PackedStringArray([
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_MOVE,
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_GRAB,
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_CARRY,
		]),
		0.25,
		0
	), "Arm fixture should configure.")
	return definition


func _make_transport_definition():
	var definition = VEHICLE_DEFINITION_SCRIPT.new()
	test.expect_true(definition.configure(
		&"transport_vehicle",
		"Transport Vehicle",
		VEHICLE_DEFINITION_SCRIPT.VehicleKind.TRANSPORT,
		Vector2i(2, 2),
		2.4,
		16.0,
		24.0,
		36.0,
		PackedStringArray([
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_MOVE,
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_CAN_CARRY,
			VEHICLE_DEFINITION_SCRIPT.CAPABILITY_HAS_TRAY,
		]),
		1.0,
		8
	), "Transport fixture should configure.")
	return definition

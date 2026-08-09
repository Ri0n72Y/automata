extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const VEHICLE_SELECTION_SCRIPT := preload("res://scripts/input/vehicle_selection_controller.gd")
const VEHICLE_MANAGER_SCRIPT := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const OBJECT_MANAGER_SCRIPT := preload("res://scripts/scene_01/scene_01_object_manager.gd")
const VEHICLE_RUNTIME_STATE_SCRIPT := preload("res://scripts/vehicles/vehicle_runtime_state.gd")

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for GrabDrop input routing.")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame

	var selection := scene.get_node_or_null(
		"SceneRoot/GridRoot/VehicleSelectionController"
	) as VEHICLE_SELECTION_SCRIPT
	var vehicle_manager := scene.get_node_or_null(
		"SceneRoot/RobotRoot/Scene01VehicleManager"
	) as VEHICLE_MANAGER_SCRIPT
	var object_manager := scene.get_node_or_null(
		"SceneRoot/ObjectRoot/Scene01ObjectManager"
	) as OBJECT_MANAGER_SCRIPT
	var status_label := scene.get_node_or_null(
		"UIRoot/RootControl/Panel/Margin/VBox/StatusLabel"
	) as Label
	_expect_true(selection != null, "Input test requires vehicle selection controller.")
	_expect_true(vehicle_manager != null, "Input test requires vehicle manager.")
	_expect_true(object_manager != null, "Input test requires object manager.")
	_expect_true(status_label != null, "Input test requires GrabDrop status feedback label.")
	if selection == null or vehicle_manager == null or object_manager == null:
		scene.queue_free()
		await process_frame
		_finish()
		return

	var arm = vehicle_manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.ARM_VEHICLE_ID)
	_expect_true(arm != null and arm.runtime_state != null, "Input test requires arm vehicle.")
	if arm == null or arm.runtime_state == null:
		scene.queue_free()
		await process_frame
		_finish()
		return
	_expect_true(selection.select_vehicle(arm), "Arm should be selected before Viewport input.")

	var initial_facing: int = arm.runtime_state.facing
	await _push_key(KEY_A)
	_expect_equal(
		arm.runtime_state.facing,
		posmod(initial_facing - 1, 4),
		"Viewport A should rotate selected arm counterclockwise."
	)
	await _push_key(KEY_D)
	_expect_equal(arm.runtime_state.facing, initial_facing, "Viewport D should restore clockwise facing.")

	var pile = object_manager.get_block_pile()
	var ground_field = object_manager.get_ground_block_field()
	_expect_true(pile != null, "Input test requires infinite block pile domain.")
	_expect_true(ground_field != null, "Input test requires ground block field.")
	if pile != null and ground_field != null:
		_place_vehicle(arm, Vector2i(1, 3), VEHICLE_RUNTIME_STATE_SCRIPT.Facing.WEST)
		var produced_before: int = pile.get_produced_count()
		var modifier_cases: Array[Dictionary] = [
			{"shift": true, "ctrl": false, "alt": false, "meta": false, "name": "Shift"},
			{"shift": false, "ctrl": true, "alt": false, "meta": false, "name": "Ctrl"},
			{"shift": false, "ctrl": false, "alt": true, "meta": false, "name": "Alt"},
			{"shift": false, "ctrl": false, "alt": false, "meta": true, "name": "Meta"},
		]
		for modifiers: Dictionary in modifier_cases:
			await _push_key(
				KEY_C,
				bool(modifiers["shift"]),
				bool(modifiers["ctrl"]),
				bool(modifiers["alt"]),
				bool(modifiers["meta"])
			)
			_expect_equal(
				pile.get_produced_count(),
				produced_before,
				"%s+C must not execute GrabDrop." % String(modifiers["name"])
			)
			_expect_false(
				arm.runtime_state.arm_has_item,
				"%s+C must preserve empty arm." % String(modifiers["name"])
			)

		await _push_key(KEY_C)
		_expect_equal(
			pile.get_produced_count(),
			produced_before + 1,
			"Viewport C should execute Grab from the forward pile."
		)
		_expect_true(arm.runtime_state.arm_has_item, "Viewport C should leave arm carrying a real block.")
		_expect_true(
			arm.runtime_state.carried_item != null
			and arm.runtime_state.carried_item.is_claimed_by(arm.runtime_state),
			"Viewport C cargo should be owned by arm runtime."
		)
		if status_label != null:
			_expect_equal(status_label.text, "Grab accepted", "Viewport C Grab should update manual feedback.")

		var carried = arm.runtime_state.carried_item
		var ground_cell := Vector2i(4, 1)
		_place_vehicle(arm, Vector2i(4, 2), VEHICLE_RUNTIME_STATE_SCRIPT.Facing.NORTH)
		await _push_key(KEY_C)
		_expect_false(arm.runtime_state.arm_has_item, "Viewport C should Drop carried block to legal ground.")
		_expect_true(ground_field.get_item(ground_cell) == carried, "Viewport ground Drop should preserve exact block identity.")
		if status_label != null:
			_expect_equal(status_label.text, "Drop accepted", "Viewport ground Drop should update manual feedback.")

		await _push_key(KEY_C)
		_expect_true(arm.runtime_state.carried_item == carried, "Second Viewport C should Grab same block from ground.")
		_expect_true(carried.is_claimed_by(arm.runtime_state), "Ground re-Grab through Viewport should restore arm ownership.")
		_expect_false(ground_field.has_item(ground_cell), "Ground cell should empty after Viewport re-Grab.")
		if status_label != null:
			_expect_equal(status_label.text, "Grab accepted", "Viewport ground Grab should update manual feedback.")

	scene.call("reset_scene")
	await process_frame
	_expect_false(arm.runtime_state.arm_has_item, "Scene Reset should clear cargo created through Viewport C.")

	scene.queue_free()
	await process_frame
	_finish()


func _push_key(
	keycode: int,
	shifted: bool = false,
	controlled: bool = false,
	alted: bool = false,
	metaed: bool = false
) -> void:
	root.push_input(_key_event(keycode, true, shifted, controlled, alted, metaed))
	await process_frame
	root.push_input(_key_event(keycode, false, shifted, controlled, alted, metaed))
	await process_frame


func _key_event(
	keycode: int,
	pressed: bool,
	shifted: bool = false,
	controlled: bool = false,
	alted: bool = false,
	metaed: bool = false
) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = pressed
	event.keycode = keycode
	event.shift_pressed = shifted
	event.ctrl_pressed = controlled
	event.alt_pressed = alted
	event.meta_pressed = metaed
	return event


func _place_vehicle(vehicle, anchor: Vector2i, facing: int) -> void:
	vehicle.runtime_state.anchor_cell = anchor
	vehicle.runtime_state.facing = facing
	vehicle.sync_from_state()


func _finish() -> void:
	if failures == 0:
		print("Vehicle GrabDrop input tests passed.")
		quit(0)
		return
	push_error("Vehicle GrabDrop input tests failed: %d failure(s)." % failures)
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

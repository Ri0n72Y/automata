extends SceneTree

const STANDARD_BLOCK_SCRIPT := preload("res://scripts/objects/standard_block.gd")
const VEHICLE_STATE_VISUAL_SCRIPT := preload("res://scripts/vehicles/vehicle_state_visual.gd")
const VEHICLE_MANAGER_SCRIPT := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const VEHICLE_MOVE_SCRIPT := preload("res://scripts/input/vehicle_move_controller.gd")
const VEHICLE_SELECTION_SCRIPT := preload("res://scripts/input/vehicle_selection_controller.gd")
const MOVE_COMMAND_SCRIPT := preload("res://scripts/vehicles/move_command.gd")
const VEHICLE_RUNTIME_STATE_SCRIPT := preload("res://scripts/vehicles/vehicle_runtime_state.gd")

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const VEHICLE_MANAGER_PATH := "SceneRoot/RobotRoot/Scene01VehicleManager"
const VEHICLE_MOVE_PATH := "SceneRoot/GridRoot/VehicleMoveController"
const VEHICLE_SELECTION_PATH := "SceneRoot/GridRoot/VehicleSelectionController"
const TRANSPORT_VEHICLE_ID := &"transport_vehicle"

var failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for transport tray integration.")
	if packed == null:
		_finish()
		return

	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame

	var manager := scene.get_node_or_null(VEHICLE_MANAGER_PATH) as VEHICLE_MANAGER_SCRIPT
	var move_controller := scene.get_node_or_null(VEHICLE_MOVE_PATH) as VEHICLE_MOVE_SCRIPT
	var vehicle_selection := scene.get_node_or_null(VEHICLE_SELECTION_PATH) as VEHICLE_SELECTION_SCRIPT
	_expect_true(manager != null, "Scene 01 should contain the vehicle manager.")
	_expect_true(move_controller != null, "Scene 01 should contain the move controller.")
	_expect_true(vehicle_selection != null, "Scene 01 should contain the vehicle selection controller.")
	if manager == null or move_controller == null or vehicle_selection == null:
		scene.queue_free()
		await process_frame
		_finish()
		return

	var arm = manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.ARM_VEHICLE_ID)
	var transport = manager.get_vehicle_by_id(TRANSPORT_VEHICLE_ID)
	_expect_true(arm != null, "Scene 01 should contain the arm vehicle.")
	_expect_true(transport != null, "Scene 01 should contain the transport vehicle.")
	if arm == null or transport == null or transport.runtime_state == null:
		scene.queue_free()
		await process_frame
		_finish()
		return

	var runtime = transport.runtime_state
	_expect_true(runtime.tray_state != null, "Transport runtime should own a real tray state.")
	if runtime.tray_state == null:
		scene.queue_free()
		await process_frame
		_finish()
		return
	_expect_equal(runtime.tray_state.get_capacity(), 8, "Transport tray capacity should come from definition.")
	_expect_equal(runtime.tray_count, 0, "Transport tray should start empty.")

	var block := STANDARD_BLOCK_SCRIPT.create()
	_expect_true(runtime.tray_state.put_item(block).is_success(), "Real tray should accept a standard block.")
	_expect_equal(runtime.tray_count, 1, "Runtime tray_count should derive from real inventory.")
	_expect_true(block.is_claimed_by(runtime.tray_state), "Inserted block should be owned by real tray state.")

	var visual := transport.get_node_or_null("VisualRoot") as VEHICLE_STATE_VISUAL_SCRIPT
	_expect_true(visual != null, "Transport vehicle should expose the existing tray visual presenter.")
	if visual != null:
		visual.refresh_visual(true)
		_expect_equal(visual.get_visible_tray_slot_count(), 1, "Tray visual should read real inventory count.")
		_expect_equal(visual.get_tray_count_label_text(), "1/8", "Tray visual label should read real inventory.")

	_test_move_and_stop_preserve_inventory(vehicle_selection, move_controller, transport, block)

	scene.call("reset_scene")
	await process_frame
	_expect_equal(runtime.tray_count, 0, "Scene Reset should clear real tray inventory.")
	_expect_false(block.is_claimed(), "Scene Reset should release tray item ownership.")
	if visual != null:
		visual.refresh_visual(true)
		_expect_equal(visual.get_visible_tray_slot_count(), 0, "Reset should clear tray visual slots.")
		_expect_equal(visual.get_tray_count_label_text(), "0/8", "Reset should clear tray visual label.")

	var collision_block := _test_collision_preserves_inventory(move_controller, arm, transport)
	scene.call("reset_scene")
	await process_frame
	if collision_block != null:
		_expect_false(collision_block.is_claimed(), "Reset after collision should release the tray item.")

	# Drop strong references before the successful rebuild lifecycle check.
	arm = null
	transport = null
	runtime = null
	visual = null
	await _test_vehicle_reinitialization_lifecycle(scene, manager)

	scene.queue_free()
	await process_frame
	_finish()


func _test_move_and_stop_preserve_inventory(
	vehicle_selection,
	move_controller,
	transport,
	block
) -> void:
	if not vehicle_selection.select_vehicle(transport):
		_expect_true(false, "Transport should be selectable with tray cargo.")
		return
	var target_anchor: Vector2i = transport.runtime_state.anchor_cell + Vector2i.LEFT
	if not move_controller.request_selected_vehicle_move(target_anchor):
		_expect_true(false, "Transport should accept a real MoveTo while carrying tray cargo.")
		return
	move_controller._physics_process(0.1)
	_expect_equal(
		transport.runtime_state.motion_state,
		VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.MOVING,
		"Short movement step should keep transport Moving."
	)
	_expect_equal(transport.runtime_state.tray_count, 1, "Move execution should preserve tray count.")
	_expect_true(block.is_claimed_by(transport.runtime_state.tray_state), "Move execution should preserve tray ownership.")
	if not move_controller.request_selected_vehicle_stop():
		_expect_true(false, "Selected moving transport should accept the same stop path used by X.")
		return
	_expect_equal(
		transport.runtime_state.motion_state,
		VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.BLOCKED,
		"Manual stop should leave transport Blocked."
	)
	_expect_equal(transport.runtime_state.tray_count, 1, "Manual stop should preserve tray count.")
	_expect_true(block.is_claimed_by(transport.runtime_state.tray_state), "Manual stop should preserve tray ownership.")


func _test_collision_preserves_inventory(move_controller, arm, transport):
	_place_vehicle(arm, Vector2i(3, 3))
	_place_vehicle(transport, Vector2i(6, 3))
	var block := STANDARD_BLOCK_SCRIPT.create()
	if not transport.runtime_state.tray_state.put_item(block).is_success():
		_expect_true(false, "Transport tray should accept collision-test cargo.")
		return null
	var arm_command = _command(Vector2i(4, 3), [Vector2i(3, 3), Vector2i(4, 3)])
	var transport_command = _command(Vector2i(5, 3), [Vector2i(6, 3), Vector2i(5, 3)])
	if arm_command == null or transport_command == null:
		return block
	if not arm.start_move(arm_command):
		_expect_true(false, "Arm collision task should start.")
		return block
	if not transport.start_move(transport_command):
		_expect_true(false, "Transport collision task should start with tray cargo.")
		arm.reset_actor()
		return block
	move_controller._physics_process(0.5)
	_expect_equal(
		transport.runtime_state.motion_state,
		VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.BLOCKED,
		"Collision coordination should block transport."
	)
	_expect_equal(transport.runtime_state.tray_count, 1, "Collision coordination should preserve tray count.")
	_expect_true(block.is_claimed_by(transport.runtime_state.tray_state), "Collision coordination should preserve tray ownership.")
	return block


func _test_vehicle_reinitialization_lifecycle(scene: Node, manager) -> void:
	var transport = manager.get_vehicle_by_id(TRANSPORT_VEHICLE_ID)
	_expect_true(transport != null and transport.runtime_state != null, "Lifecycle test requires transport runtime.")
	if transport == null or transport.runtime_state == null:
		return
	var tray = transport.runtime_state.tray_state
	_expect_true(tray != null, "Lifecycle test requires a real tray state.")
	if tray == null:
		return
	var block := STANDARD_BLOCK_SCRIPT.create()
	if not tray.put_item(block).is_success():
		_expect_true(false, "Lifecycle tray should accept one block.")
		return
	var original_width: int = scene.get("grid_width")
	var original_height: int = scene.get("grid_height")
	var original_actor_id: int = transport.get_instance_id()
	var original_tray_id: int = tray.get_instance_id()

	scene.set("grid_width", 4)
	scene.set("grid_height", 4)
	var initialized := bool(_quiet(Callable(scene, "initialize_grid")))
	_expect_false(initialized, "Invalid grid rebuild should reject before replacing transport.")
	var preserved = manager.get_vehicle_by_id(TRANSPORT_VEHICLE_ID)
	_expect_true(preserved == transport, "Rejected rebuild should preserve transport Actor identity.")
	if preserved == null or preserved.runtime_state == null or preserved.runtime_state.tray_state == null:
		_expect_true(false, "Rejected rebuild should preserve a complete transport runtime and tray.")
		scene.set("grid_width", original_width)
		scene.set("grid_height", original_height)
		return
	_expect_equal(
		preserved.runtime_state.tray_state.get_instance_id(),
		original_tray_id,
		"Rejected rebuild should preserve tray-state identity."
	)
	_expect_equal(preserved.runtime_state.tray_count, 1, "Rejected rebuild should preserve tray inventory.")
	_expect_true(block.is_claimed_by(tray), "Rejected rebuild should preserve tray ownership.")

	scene.set("grid_width", original_width)
	scene.set("grid_height", original_height)
	var tray_ref := weakref(tray)
	transport = null
	preserved = null
	tray = null
	if not bool(scene.call("initialize_grid")):
		_expect_true(false, "Valid grid rebuild should replace the vehicle batch.")
		return
	await process_frame
	await process_frame
	var replacement = manager.get_vehicle_by_id(TRANSPORT_VEHICLE_ID)
	_expect_true(replacement != null, "Valid rebuild should provide replacement transport.")
	if replacement != null:
		_expect_true(replacement.get_instance_id() != original_actor_id, "Valid rebuild should replace transport Actor identity.")
		_expect_true(replacement.runtime_state != null, "Replacement transport should own runtime state.")
		if replacement.runtime_state != null:
			_expect_true(replacement.runtime_state.tray_state != null, "Replacement transport should own a fresh tray state.")
			_expect_equal(replacement.runtime_state.tray_count, 0, "Replacement transport tray should start empty.")
	_expect_true(tray_ref.get_ref() == null, "Retired tray state should be released after vehicle replacement.")
	_expect_false(block.is_claimed(), "Vehicle replacement should not leave cargo claimed by a retired tray.")


func _place_vehicle(vehicle, anchor: Vector2i) -> void:
	vehicle.reset_actor()
	vehicle.runtime_state.anchor_cell = anchor
	vehicle.sync_from_state()


func _command(target: Vector2i, path: Array[Vector2i]):
	var command := MOVE_COMMAND_SCRIPT.new()
	if not command.configure(target, path):
		failures += 1
		push_error("Collision fixture command should configure.")
		return null
	return command


func _quiet(callback: Callable) -> Variant:
	var previous_print_error_messages := Engine.print_error_messages
	Engine.print_error_messages = false
	var result: Variant = callback.call()
	Engine.print_error_messages = previous_print_error_messages
	return result


func _finish() -> void:
	if failures == 0:
		print("Scene 01 transport tray smoke tests passed.")
		quit(0)
		return
	push_error("Scene 01 transport tray smoke tests failed: %d failure(s)." % failures)
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

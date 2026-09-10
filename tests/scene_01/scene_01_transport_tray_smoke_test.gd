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
	scene.call("run_scene")

	var manager := scene.get_node_or_null(VEHICLE_MANAGER_PATH) as VEHICLE_MANAGER_SCRIPT
	var move_controller := scene.get_node_or_null(VEHICLE_MOVE_PATH) as VEHICLE_MOVE_SCRIPT
	var vehicle_selection := scene.get_node_or_null(VEHICLE_SELECTION_PATH) as VEHICLE_SELECTION_SCRIPT
	_expect_true(manager != null and move_controller != null and vehicle_selection != null, "Scene exposes tray integration controllers.")
	if manager == null or move_controller == null or vehicle_selection == null:
		await _cleanup(scene)
		_finish()
		return

	var arm = manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.ARM_VEHICLE_ID)
	var transport = manager.get_vehicle_by_id(VEHICLE_MANAGER_SCRIPT.TRANSPORT_VEHICLE_ID)
	_expect_true(arm != null and transport != null, "Scene contains both preset vehicles.")
	if arm == null or transport == null or transport.runtime_state == null:
		await _cleanup(scene)
		_finish()
		return

	var runtime = transport.runtime_state
	_expect_true(runtime.tray_state != null, "Transport runtime owns a real tray state.")
	if runtime.tray_state == null:
		await _cleanup(scene)
		_finish()
		return
	_expect_equal(runtime.tray_state.get_capacity(), 8, "Transport tray capacity comes from definition.")
	_expect_equal(runtime.tray_count, 0, "Transport tray starts empty.")

	var block := STANDARD_BLOCK_SCRIPT.create()
	_expect_true(runtime.tray_state.put_item(block).is_success(), "Real tray accepts a standard block.")
	_expect_equal(runtime.tray_count, 1, "Runtime tray_count derives from real inventory.")
	_expect_true(block.is_claimed_by(runtime.tray_state), "Inserted block is tray-owned.")

	var visual := transport.get_node_or_null("VisualRoot") as VEHICLE_STATE_VISUAL_SCRIPT
	_expect_true(visual != null, "Transport exposes the tray visual presenter.")
	if visual != null:
		visual.refresh_visual(true)
		_expect_equal(visual.get_visible_tray_slot_count(), 1, "Tray visual reads real inventory count.")
		_expect_equal(visual.get_tray_count_label_text(), "1/8", "Tray visual label reads real inventory.")

	_test_move_and_stop_preserve_inventory(vehicle_selection, move_controller, transport, block)

	scene.call("reset_scene")
	await process_frame
	_expect_equal(runtime.tray_count, 0, "Scene Reset clears real tray inventory.")
	_expect_false(block.is_claimed(), "Scene Reset releases tray item ownership.")
	if visual != null:
		visual.refresh_visual(true)
		_expect_equal(visual.get_visible_tray_slot_count(), 0, "Reset clears tray visual slots.")
		_expect_equal(visual.get_tray_count_label_text(), "0/8", "Reset clears tray visual label.")
	scene.call("run_scene")

	var collision_block: Variant = _test_collision_preserves_inventory(move_controller, arm, transport)
	scene.call("reset_scene")
	await process_frame
	if collision_block != null:
		_expect_false(collision_block.is_claimed(), "Reset after collision releases tray cargo.")

	await _cleanup(scene)
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
		_expect_true(false, "Transport should accept MoveTo while carrying tray cargo.")
		return
	move_controller._physics_process(0.1)
	_expect_equal(
		transport.runtime_state.motion_state,
		VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.MOVING,
		"Short movement step keeps transport Moving."
	)
	_expect_equal(transport.runtime_state.tray_count, 1, "Move preserves tray count.")
	_expect_true(block.is_claimed_by(transport.runtime_state.tray_state), "Move preserves tray ownership.")
	if not move_controller.request_selected_vehicle_stop():
		_expect_true(false, "Selected moving transport should accept Stop.")
		return
	_expect_equal(
		transport.runtime_state.motion_state,
		VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.BLOCKED,
		"Manual stop leaves transport Blocked."
	)
	_expect_equal(transport.runtime_state.tray_count, 1, "Stop preserves tray count.")
	_expect_true(block.is_claimed_by(transport.runtime_state.tray_state), "Stop preserves tray ownership.")


func _test_collision_preserves_inventory(move_controller, arm, transport) -> Variant:
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
	if not arm.start_move(arm_command) or not transport.start_move(transport_command):
		_expect_true(false, "Collision fixture tasks should start.")
		return block
	move_controller._physics_process(0.5)
	_expect_equal(
		transport.runtime_state.motion_state,
		VEHICLE_RUNTIME_STATE_SCRIPT.MotionState.BLOCKED,
		"Collision coordination blocks transport."
	)
	_expect_equal(transport.runtime_state.tray_count, 1, "Collision preserves tray count.")
	_expect_true(block.is_claimed_by(transport.runtime_state.tray_state), "Collision preserves tray ownership.")
	return block


func _place_vehicle(vehicle, anchor: Vector2i) -> void:
	vehicle.reset_actor()
	vehicle.runtime_state.anchor_cell = anchor
	vehicle.sync_from_state()


func _command(target: Vector2i, path: Array[Vector2i]) -> Variant:
	var command := MOVE_COMMAND_SCRIPT.new()
	if not command.configure(target, path):
		failures += 1
		push_error("Collision fixture command should configure.")
		return null
	return command


func _cleanup(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
		await process_frame


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

extends SceneTree

const STANDARD_BLOCK_SCRIPT := preload("res://scripts/objects/standard_block.gd")
const VEHICLE_STATE_VISUAL_SCRIPT := preload("res://scripts/vehicles/vehicle_state_visual.gd")

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const VEHICLE_MANAGER_PATH := "SceneRoot/RobotRoot/Scene01VehicleManager"
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

	var manager := scene.get_node_or_null(VEHICLE_MANAGER_PATH) as Scene01VehicleManager
	_expect_true(manager != null, "Scene 01 should contain the vehicle manager.")
	if manager == null:
		scene.queue_free()
		await process_frame
		_finish()
		return

	var transport := manager.get_vehicle_by_id(TRANSPORT_VEHICLE_ID)
	_expect_true(transport != null, "Scene 01 should contain the transport vehicle.")
	if transport == null or transport.runtime_state == null:
		scene.queue_free()
		await process_frame
		_finish()
		return

	var runtime := transport.runtime_state
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

	var visual := transport.get_node_or_null("VisualRoot") as VehicleStateVisualScript
	_expect_true(visual != null, "Transport vehicle should expose the existing tray visual presenter.")
	if visual != null:
		visual.refresh_visual(true)
		_expect_equal(visual.get_visible_tray_slot_count(), 1, "Tray visual should read real inventory count.")
		_expect_equal(visual.get_tray_count_label_text(), "1/8", "Tray visual label should read real inventory.")

	_expect_true(runtime.begin_move_planning(), "Transport should be able to enter planning while carrying tray items.")
	_expect_equal(runtime.tray_count, 1, "Planning should not mutate tray inventory.")
	runtime.fail_move_planning()
	_expect_equal(runtime.tray_count, 1, "Blocked state should not mutate tray inventory.")
	runtime.clear_move_command()
	_expect_equal(runtime.tray_count, 1, "Clearing movement state should not mutate tray inventory.")

	scene.call("reset_scene")
	await process_frame
	_expect_equal(runtime.tray_count, 0, "Scene Reset should clear real tray inventory.")
	_expect_false(block.is_claimed(), "Scene Reset should release tray item ownership.")
	if visual != null:
		visual.refresh_visual(true)
		_expect_equal(visual.get_visible_tray_slot_count(), 0, "Reset should clear tray visual slots.")
		_expect_equal(visual.get_tray_count_label_text(), "0/8", "Reset should clear tray visual label.")

	scene.queue_free()
	await process_frame
	_finish()


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

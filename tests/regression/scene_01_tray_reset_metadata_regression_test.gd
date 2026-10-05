extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Regression fixture should load Scene 01.")
	if packed == null:
		_finish()
		return

	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame

	var manager := scene.get_node_or_null(
		"SceneRoot/RobotRoot/Scene01VehicleManager"
	) as VehicleManagerScript
	var transport = (
		manager.get_vehicle_by_id(VehicleManagerScript.TRANSPORT_VEHICLE_ID)
		if manager != null else null
	)
	_expect_true(transport != null and transport.runtime_state != null, "Transport runtime should exist.")
	if transport == null or transport.runtime_state == null:
		await _cleanup(scene)
		return

	_expect_true(bool(scene.call("reset_scene")), "Regression fixture Reset should succeed.")
	await process_frame

	var tray_state = transport.runtime_state.tray_state
	_expect_true(tray_state != null, "Transport tray state should survive Reset.")
	if tray_state != null:
		_expect_equal(
			tray_state.get_interaction_cells(),
			transport.get_occupied_cells(),
			"Reset must restore stationary tray interaction metadata."
		)
		_expect_true(
			transport.runtime_state.get_item_interaction_interfaces_readonly().has(tray_state),
			"Reset transport should expose its tray interaction interface."
		)

	await _cleanup(scene)


func _cleanup(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	_finish()


func _finish() -> void:
	if failures == 0:
		print("Tray reset metadata regression test passed.")
		quit(0)
		return
	push_error("Tray reset metadata regression test failed: %d failure(s)." % failures)
	quit(1)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures += 1
		push_error("%s Expected %s, got %s." % [message, str(expected), str(actual)])


func _expect_true(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

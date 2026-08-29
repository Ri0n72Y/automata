extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const LifecycleControllerScript := preload("res://scripts/scene_01/scene_01_lifecycle_controller.gd")
const LifecycleStateScript := preload("res://scripts/scene_01/scene_01_lifecycle_state.gd")
const ObjectManagerScript := preload("res://scripts/scene_01/scene_01_object_manager.gd")

var failures: int = 0
var _scene: LifecycleControllerScript
var _reentrant_action: StringName = &""
var _nested_gameplay_result: bool = true
var _reentrant_reset_result: bool = true
var _try_speed_mutation_during_reset: bool = false
var _reentrant_speed_result: bool = true
var _events: Array[String] = []
var _run_preparation_failures: Array[StringName] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect_true(packed != null, "Scene 01 should load for lifecycle boundary regression tests.")
	if packed == null:
		_finish()
		return

	_scene = packed.instantiate() as LifecycleControllerScript
	_expect_true(_scene != null, "Scene 01 should use the lifecycle controller.")
	if _scene == null:
		_finish()
		return
	_scene.lifecycle_state_changed.connect(_on_lifecycle_state_changed)
	_scene.simulation_speed_changed.connect(_on_simulation_speed_changed)
	_scene.lifecycle_reset_completed.connect(_on_lifecycle_reset_completed)
	root.add_child(_scene)
	await process_frame
	_expect_true(_scene.is_scene_initialized(), "Valid Scene 01 composition should initialize successfully.")

	_events.clear()
	_nested_gameplay_result = true
	_reentrant_action = &"nested_gameplay"
	_scene.run_scene()
	_expect_false(_nested_gameplay_result, "Gameplay must fail closed while a lifecycle event is being dispatched.")
	_expect_equal(_scene.get_lifecycle_state(), LifecycleStateScript.State.RUNNING, "Nested gameplay rejection must not alter RUNNING.")
	_expect_equal(_events, ["state:0>1"], "RUNNING should publish once without nested lifecycle events.")
	_expect_true(_scene.reset_scene(), "Reset should recover after nested gameplay coverage.")

	_events.clear()
	_reentrant_action = &"pause"
	_scene.run_scene()
	_expect_equal(_scene.get_lifecycle_state(), LifecycleStateScript.State.RUNNING, "Pause requested from a RUNNING subscriber must be rejected synchronously.")
	_expect_equal(_events, ["state:0>1"], "Subscriber Pause must not create a nested PAUSED transition.")
	_expect_true(_scene.reset_scene(), "Reset should recover after reentrant Pause coverage.")

	_events.clear()
	_reentrant_reset_result = true
	_reentrant_action = &"reset"
	_scene.run_scene()
	_expect_false(_reentrant_reset_result, "Reset requested from a RUNNING subscriber must fail closed, not become a deferred transaction.")
	_expect_equal(_scene.get_lifecycle_state(), LifecycleStateScript.State.RUNNING, "Rejected subscriber Reset must leave RUNNING intact.")
	_expect_equal(_events, ["state:0>1"], "Rejected subscriber Reset must not publish READY or reset-completed.")

	_expect_true(_scene.set_simulation_speed(4.0), "4x should be accepted before Reset speed reentrancy coverage.")
	_events.clear()
	_try_speed_mutation_during_reset = true
	_reentrant_speed_result = true
	_expect_true(_scene.reset_scene(), "Explicit Reset should succeed.")
	_try_speed_mutation_during_reset = false
	_expect_false(_reentrant_speed_result, "A speed mutation from Reset's speed notification must be rejected.")
	_expect_equal(_scene.get_lifecycle_state(), LifecycleStateScript.State.READY, "Reset should finish READY.")
	_expect_equal(_scene.get_simulation_speed(), 1.0, "Reset must finish at 1x.")
	_expect_equal(
		_events,
		["speed:4.0>1.0", "state:1>0", "reset"],
		"Reset should publish one stable speed, state, reset-completed sequence."
	)

	await _cleanup(_scene)
	_scene = null

	var invalid_scene := packed.instantiate() as LifecycleControllerScript
	_expect_true(invalid_scene != null, "Invalid composition fixture should instantiate.")
	if invalid_scene != null:
		var object_manager := invalid_scene.get_node_or_null("SceneRoot/ObjectRoot/Scene01ObjectManager") as ObjectManagerScript
		_expect_true(object_manager != null, "Invalid composition fixture requires ObjectManager.")
		if object_manager != null:
			object_manager.ground_block_field = null
		_run_preparation_failures.clear()
		invalid_scene.lifecycle_run_preparation_failed.connect(_on_run_preparation_failed)
		root.add_child(invalid_scene)
		await process_frame
		_expect_false(invalid_scene.is_scene_initialized(), "Missing required object composition must leave Scene 01 uninitialized.")
		invalid_scene.run_scene()
		_expect_equal(invalid_scene.get_lifecycle_state(), LifecycleStateScript.State.READY, "Uninitialized Scene 01 must not enter RUNNING.")
		_expect_equal(
			_run_preparation_failures,
			[&"scene_not_initialized"],
			"Run attempt on invalid composition should expose one stable lifecycle failure reason."
		)
		await _cleanup(invalid_scene)

	_finish()


func _on_lifecycle_state_changed(previous_state: int, current_state: int) -> void:
	_events.append("state:%d>%d" % [previous_state, current_state])
	if current_state != LifecycleStateScript.State.RUNNING or _scene == null:
		return
	var action := _reentrant_action
	_reentrant_action = &""
	match action:
		&"nested_gameplay":
			_nested_gameplay_result = _scene.ensure_gameplay_running()
		&"pause":
			_scene.pause_scene()
		&"reset":
			_reentrant_reset_result = _scene.reset_scene()


func _on_simulation_speed_changed(previous_speed: float, current_speed: float) -> void:
	_events.append("speed:%.1f>%.1f" % [previous_speed, current_speed])
	if _try_speed_mutation_during_reset and is_equal_approx(current_speed, 1.0) and _scene != null:
		_try_speed_mutation_during_reset = false
		_reentrant_speed_result = _scene.set_simulation_speed(2.0)


func _on_lifecycle_reset_completed() -> void:
	_events.append("reset")


func _on_run_preparation_failed(reason: StringName) -> void:
	_run_preparation_failures.append(reason)


func _cleanup(scene: Node) -> void:
	if scene != null and is_instance_valid(scene):
		scene.queue_free()
		await process_frame


func _finish() -> void:
	if failures == 0:
		print("Scene 01 lifecycle boundary regression tests passed.")
		quit(0)
		return
	push_error("Scene 01 lifecycle boundary regression tests failed: %d failure(s)." % failures)
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

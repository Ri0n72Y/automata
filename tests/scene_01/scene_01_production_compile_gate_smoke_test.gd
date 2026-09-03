extends SceneTree

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const ManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const LifecycleStateScript := preload("res://scripts/scene_01/scene_01_lifecycle_state.gd")

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_expect(packed != null, "Production Scene 01 should load.")
	if packed == null:
		_finish()
		return

	var scene := packed.instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame

	var gate := scene.get_node_or_null("SceneRoot/Scene01AssemblyCompileGate")
	var manager := scene.get_node_or_null("SceneRoot/RobotRoot/Scene01VehicleManager") as ManagerScript
	var selection := scene.get_node_or_null("SceneRoot/GridRoot/VehicleSelectionController")
	var move_controller := scene.get_node_or_null("SceneRoot/GridRoot/VehicleMoveController")

	_expect(gate != null, "Production scene embeds Scene01AssemblyCompileGate.")
	_expect(manager != null, "Production scene embeds Scene01VehicleManager.")
	_expect(selection != null and move_controller != null, "Production scene embeds selection/move controllers.")
	_expect(
		scene.get("run_preparation_gate_path") == NodePath("SceneRoot/Scene01AssemblyCompileGate"),
		"Lifecycle controller points at the production compile gate."
	)
	if gate == null or manager == null or selection == null or move_controller == null:
		scene.queue_free()
		await process_frame
		_finish()
		return

	_expect(
		gate.get("vehicle_manager_path") == NodePath("../RobotRoot/Scene01VehicleManager"),
		"Production compile gate points at the vehicle manager."
	)
	_expect(int(gate.call("get_compile_cache_size")) == 0, "Compile cache starts empty before first run.")
	_expect(gate.call("get_compile_result", &"arm_vehicle") == null, "No arm publication before first run.")
	_expect(gate.call("get_compile_result", &"transport_vehicle") == null, "No transport publication before first run.")

	# Explicit Play must compile the shipped vehicle presets before entering RUNNING.
	scene.call("run_scene")
	await process_frame
	_expect(
		int(scene.call("get_lifecycle_state")) == LifecycleStateScript.State.RUNNING,
		"Production Play enters RUNNING through the compile gate."
	)
	_expect(_compiled_success(gate, &"arm_vehicle"), "Arm vehicle compiled successfully through production wiring.")
	_expect(_compiled_success(gate, &"transport_vehicle"), "Transport vehicle compiled successfully through production wiring.")
	_expect(int(gate.call("get_compile_cache_size")) >= 2, "Production gate populated compiler cache for both vehicles.")

	# After Reset, a READY gameplay command must invoke the same production gate again.
	_expect(bool(scene.call("reset_scene")), "Production Reset succeeds.")
	await process_frame
	_expect(
		int(scene.call("get_lifecycle_state")) == LifecycleStateScript.State.READY,
		"Reset returns production scene to READY."
	)
	gate.call("clear_runtime_results")
	_expect(gate.call("get_compile_result", &"arm_vehicle") == null, "Runtime publication cleared for re-run probe.")

	var arm = manager.get_vehicle_by_id(ManagerScript.ARM_VEHICLE_ID)
	_expect(arm != null, "Arm vehicle exists for READY gameplay-command probe.")
	if arm != null:
		_expect(bool(selection.call("select_vehicle", arm)), "Arm can be selected after Reset.")
		_expect(
			bool(move_controller.call("request_selected_vehicle_move", Vector2i(5, 2))),
			"READY MoveTo is accepted through production lifecycle."
		)
		_expect(
			int(scene.call("get_lifecycle_state")) == LifecycleStateScript.State.RUNNING,
			"READY gameplay command starts production scene."
		)
		_expect(_compiled_success(gate, &"arm_vehicle"), "READY gameplay command republishes arm compile result.")
		_expect(_compiled_success(gate, &"transport_vehicle"), "READY gameplay command republishes transport compile result.")

	scene.queue_free()
	await process_frame
	_finish()


func _compiled_success(gate: Node, vehicle_id: StringName) -> bool:
	var result = gate.call("get_compile_result", vehicle_id)
	return result != null and result.has_method("is_success") and bool(result.call("is_success"))


func _expect(ok: bool, message: String) -> void:
	if ok:
		print("PASS: %s" % message)
		return
	_failures += 1
	push_error("FAIL: %s" % message)


func _finish() -> void:
	if _failures == 0:
		print("Scene 01 production compile-gate smoke test passed.")
		quit(0)
		return
	push_error("Scene 01 production compile-gate smoke test failed: %d failure(s)." % _failures)
	quit(1)

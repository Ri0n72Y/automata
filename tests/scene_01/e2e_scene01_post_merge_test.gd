extends SceneTree

# E2E post-merge suite for Scene 01 on test/scene-01-post-merge-e2e.
# Single continuous session on ONE scene instance (E2E-01 .. E2E-15):
#   compile gate -> lifecycle -> MoveTo -> Pause/Resume -> speeds -> no_path
#   -> manual logistics (pile/tray/ground/box) -> Pause+GrabDrop
#   -> dirty-state Reset (idempotent) -> run again after Reset.
#
# The production scene does not yet embed the compile gate; this suite wires a
# real Scene01AssemblyCompileGate under SceneRoot (the intended integration
# point) and counts every prepare_scene_run() through a probe subclass.

const SCENE_PATH := "res://scenes/scene_01/scene_01_basic_packing.tscn"
const GateScript := preload("res://scripts/scene_01/scene_01_assembly_compile_gate.gd")
const ManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const LifecycleStateScript := preload("res://scripts/scene_01/scene_01_lifecycle_state.gd")
const RuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const GrabDropResultScript := preload("res://scripts/vehicles/grab_drop_result.gd")
const StandardBlockScript := preload("res://scripts/objects/standard_block.gd")

var _failures: int = 0
var _scene: Node
var _manager: ManagerScript
var _arm: Node
var _transport: Node
var _selection: Node
var _move_controller: Node
var _grid_selection: Node
var _grab_drop: Node
var _object_manager: Node
var _gate: CompileGateProbe
var _prep_failures: Array[StringName] = []


class CompileGateProbe:
	extends GateScript
	var call_count: int = 0

	func prepare_scene_run() -> bool:
		call_count += 1
		return super.prepare_scene_run()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	_check("E2E-01", packed != null, "Scene 01 tscn loads.")
	if packed == null:
		_finish_suite()
		return
	_scene = packed.instantiate()
	if _scene.has_method("lifecycle_run_preparation_failed"):
		_scene.lifecycle_run_preparation_failed.connect(_on_prep_failed)
	root.add_child(_scene)
	await process_frame
	await physics_frame

	_manager = _scene.get_node_or_null("SceneRoot/RobotRoot/Scene01VehicleManager") as ManagerScript
	_selection = _scene.get_node_or_null("SceneRoot/GridRoot/VehicleSelectionController")
	_move_controller = _scene.get_node_or_null("SceneRoot/GridRoot/VehicleMoveController")
	_grid_selection = _scene.get_node_or_null("SceneRoot/GridRoot/GridSelectionController")
	_grab_drop = _scene.get_node_or_null("SceneRoot/GridRoot/VehicleGrabDropController")
	_object_manager = _scene.get_node_or_null("SceneRoot/ObjectRoot/Scene01ObjectManager")
	_check("E2E-01", _manager != null and _selection != null and _move_controller != null
		and _grid_selection != null and _grab_drop != null and _object_manager != null,
		"Scene 01 controllers/managers present.")
	if _manager == null or _selection == null or _move_controller == null or _object_manager == null:
		_finish_suite()
		return

	_arm = _manager.get_vehicle_by_id(ManagerScript.ARM_VEHICLE_ID)
	_transport = _manager.get_vehicle_by_id(ManagerScript.TRANSPORT_VEHICLE_ID)

	# Wire the real compile gate under SceneRoot (intended integration point).
	var scene_root: Node = _scene.get_node("SceneRoot")
	_gate = CompileGateProbe.new()
	_gate.name = "AssemblyCompileGate"
	_gate.vehicle_manager_path = NodePath("../RobotRoot/Scene01VehicleManager")
	scene_root.add_child(_gate)
	await process_frame
	_scene.set("run_preparation_gate_path", NodePath("SceneRoot/AssemblyCompileGate"))
	print("note: shipped scene_01_basic_packing.tscn does NOT embed AssemblyCompileGate; wired by E2E driver.")

	await _e2e01_phase0()
	await _e2e02_first_command_auto_run()
	await _e2e03_05_pause_resume()
	await _e2e06_speeds()
	await _e2e07_no_path_blocked()
	await _e2e08_11_logistics()
	await _e2e12_pause_grab_drop()
	await _e2e13_14_dirty_reset()
	await _e2e15_run_after_reset()

	await _cleanup_scene()
	_finish_suite()


# ---------------------------------------------------------------- E2E-01

func _e2e01_phase0() -> void:
	print("== E2E-01 Scene init + compile gate wiring ==")
	_check("E2E-01", bool(_scene.call("is_scene_initialized")), "Scene composition initializes.")
	_check("E2E-01", _arm != null and _transport != null, "Arm + Transport vehicles exist.")
	_check("E2E-01", _manager.get_vehicle_count() == ManagerScript.REQUIRED_VEHICLE_COUNT,
		"Exactly two vehicles.")
	var pile = _object_manager.get_block_pile()
	var box = _object_manager.get_standard_box()
	_check("E2E-01", pile != null and box != null, "Pile + StandardBox exist.")
	_check("E2E-01", int(box.get_current_count()) == 3, "StandardBox starts 3/8.")
	_check("E2E-01", int(_scene.call("get_lifecycle_state")) == LifecycleStateScript.State.READY,
		"Lifecycle READY.")
	_check("E2E-01", is_equal_approx(float(_scene.call("get_simulation_speed")), 1.0), "Speed 1x.")
	_check("E2E-01", _arm.runtime_state.anchor_cell == Vector2i(2, 2)
		and _transport.runtime_state.anchor_cell == Vector2i(7, 4), "Initial anchors (2,2)/(7,4).")
	_check("E2E-01", _arm.runtime_state.active_move_command == null
		and _transport.runtime_state.active_move_command == null, "No residual commands.")
	_check("E2E-01", not _arm.runtime_state.arm_has_item and _transport.runtime_state.tray_count == 0,
		"Arm empty / tray empty.")
	_check("E2E-01", _object_manager.get_ground_block_field().get_occupied_cells().size() == 0,
		"No ground blocks.")
	_check("E2E-01", _gate.call_count == 0 and _gate.get_compile_cache_size() == 0,
		"Nothing compiled before first gameplay command.")
	_check("E2E-01", _prep_failures.is_empty(), "No compile/run-preparation failure.")

	# Play-equivalent: READY -> RUNNING must pass the compile gate.
	_scene.call("run_scene")
	await process_frame
	var gate_ok := _gate.call_count == 1
	var arm_result = _gate.get_compile_result(&"arm_vehicle")
	var transport_result = _gate.get_compile_result(&"transport_vehicle")
	_check("E2E-01", int(_scene.call("get_lifecycle_state")) == LifecycleStateScript.State.RUNNING,
		"Play compiles both vehicles and enters RUNNING.")
	_check("E2E-01", gate_ok
		and (arm_result != null and arm_result.is_success())
		and (transport_result != null and transport_result.is_success())
		and _gate.get_compile_cache_size() >= 2,
		"AssemblyCompiler compiled arm + transport presets through adapter.")
	_check("E2E-01", _prep_failures.is_empty(), "No run-preparation failure on Play.")
	_scene.call("pause_scene")
	_scene.call("reset_scene")
	await process_frame
	_check("E2E-01", int(_scene.call("get_lifecycle_state")) == LifecycleStateScript.State.READY
		and is_equal_approx(float(_scene.call("get_simulation_speed")), 1.0),
		"Back to READY/1x after Play probe.")


# ---------------------------------------------------------------- E2E-02

func _e2e02_first_command_auto_run() -> void:
	print("== E2E-02 READY first gameplay command auto-run ==")
	_check("E2E-02", int(_scene.call("get_lifecycle_state")) == LifecycleStateScript.State.READY,
		"Precondition READY.")
	var calls_before: int = _gate.call_count
	_check("E2E-02", bool(_selection.call("select_vehicle", _arm)), "Select arm.")
	_check("E2E-02", bool(_move_controller.call("request_selected_vehicle_move", Vector2i(5, 2))),
		"READY MoveTo accepted.")
	_check("E2E-02", _gate.call_count == calls_before + 1, "Compile gate invoked exactly once.")
	_check("E2E-02", int(_scene.call("get_lifecycle_state")) == LifecycleStateScript.State.RUNNING,
		"READY -> RUNNING automatically.")
	_check("E2E-02", _arm.runtime_state.motion_state == RuntimeStateScript.MotionState.MOVING,
		"Arm starts moving.")


# ---------------------------------------------------------------- E2E-03/04/05

func _e2e03_05_pause_resume() -> void:
	print("== E2E-03/04/05 Pause/Resume while moving ==")
	var command_before = _arm.runtime_state.active_move_command
	_check("E2E-03", command_before != null, "Active MoveCommand exists while moving.")
	_move_controller._physics_process(0.25)
	var frozen_position: Vector3 = _arm.global_position
	var frozen_anchor: Vector2i = _arm.runtime_state.anchor_cell
	var timer_before: float = float(_scene.get("timer"))
	_scene.call("pause_scene")
	_check("E2E-03", int(_scene.call("get_lifecycle_state")) == LifecycleStateScript.State.PAUSED,
		"Pause -> PAUSED.")
	_move_controller._physics_process(1.0)
	await process_frame
	_check("E2E-03", _arm.global_position.is_equal_approx(frozen_position),
		"Vehicle position frozen while PAUSED.")
	_check("E2E-03", _arm.runtime_state.anchor_cell == frozen_anchor, "Anchor frozen.")
	_check("E2E-03", _arm.runtime_state.active_move_command == command_before,
		"MoveCommand identity preserved (not cancelled).")
	_check("E2E-03", is_equal_approx(float(_scene.get("timer")), timer_before),
		"Simulation timer frozen.")

	# E2E-04: PAUSED rejects gameplay input (key-level routing).
	var facing_before: int = _arm.runtime_state.facing
	await _press_key(KEY_M)
	_check("E2E-04", not bool(_grid_selection.call("is_live_target_mode")),
		"M rejected while PAUSED (no target mode).")
	_check("E2E-04", not bool(_move_controller.call("request_selected_vehicle_move", Vector2i(9, 2))),
		"MoveTo rejected while PAUSED.")
	await _press_key(KEY_X)
	_check("E2E-04", _arm.runtime_state.motion_state == RuntimeStateScript.MotionState.MOVING,
		"X rejected while PAUSED (still moving).")
	await _press_key(KEY_A)
	await _press_key(KEY_D)
	_check("E2E-04", _arm.runtime_state.facing == facing_before, "A/D rejected while PAUSED (facing unchanged).")
	await _press_key(KEY_C)
	_check("E2E-04", not _arm.runtime_state.arm_has_item, "C rejected while PAUSED (arm still empty).")
	_check("E2E-04", _arm.runtime_state.active_move_command == command_before,
		"PAUSED input attempts left command intact.")

	# E2E-05: Resume continues the SAME command.
	_scene.call("resume_scene")
	_check("E2E-05", int(_scene.call("get_lifecycle_state")) == LifecycleStateScript.State.RUNNING,
		"Resume -> RUNNING.")
	_check("E2E-05", _arm.runtime_state.active_move_command == command_before,
		"Original MoveCommand continues (same identity).")
	await _wait_arrival(_arm, Vector2i(5, 2), "E2E-05")
	_check("E2E-05", _arm.runtime_state.anchor_cell == Vector2i(5, 2)
		and _arm.runtime_state.motion_state == RuntimeStateScript.MotionState.WAITING,
		"Resumed command reaches the original destination.")


# ---------------------------------------------------------------- E2E-06

func _e2e06_speeds() -> void:
	print("== E2E-06 Simulation speed 0.5/1/2/4x ==")
	_scene.call("reset_scene")
	await process_frame

	var measured: Dictionary = {}
	for speed_value in [0.5, 1.0, 2.0, 4.0]:
		_check("E2E-06", bool(_scene.call("set_simulation_speed", speed_value)),
			"Speed %.1fx accepted." % speed_value)
		_place_vehicle(_arm, Vector2i(2, 2), RuntimeStateScript.Facing.EAST)
		_check("E2E-06", bool(_selection.call("select_vehicle", _arm)), "Select arm for speed sample.")
		_check("E2E-06", bool(_move_controller.call("request_selected_vehicle_move", Vector2i(3, 2))),
			"One-cell MoveTo accepted at %.1fx." % speed_value)
		measured[speed_value] = _measure_seconds_to_finish(Vector2i(3, 2))
		_scene.call("reset_scene")
		await process_frame

	var ratio_05_1: float = float(measured[0.5]) / float(measured[1.0])
	var ratio_1_2: float = float(measured[1.0]) / float(measured[2.0])
	var ratio_2_4: float = float(measured[2.0]) / float(measured[4.0])
	print("E2E-06 elapsed real seconds: 0.5x=%.3f 1x=%.3f 2x=%.3f 4x=%.3f ratios=%.2f/%.2f/%.2f"
		% [measured[0.5], measured[1.0], measured[2.0], measured[4.0],
		ratio_05_1, ratio_1_2, ratio_2_4])
	_check("E2E-06", _in_range(ratio_05_1, 1.4, 3.2), "0.5x takes ~2x the real time of 1x.")
	_check("E2E-06", _in_range(ratio_1_2, 1.4, 3.2), "1x takes ~2x the real time of 2x.")
	_check("E2E-06", _in_range(ratio_2_4, 1.4, 3.2), "2x takes ~2x the real time of 4x.")
	_check("E2E-06", is_equal_approx(float(Engine.time_scale), 1.0),
		"Engine.time_scale untouched (UI/camera not globally time-scaled).")

	# Mid-move speed switching must not cancel the command; 2x -> Pause -> Resume.
	_scene.call("reset_scene")
	await process_frame
	_check("E2E-06", bool(_scene.call("set_simulation_speed", 2.0)), "2x set for switching test.")
	_place_vehicle(_arm, Vector2i(2, 2), RuntimeStateScript.Facing.EAST)
	_check("E2E-06", bool(_selection.call("select_vehicle", _arm)), "Select arm for switching test.")
	_check("E2E-06", bool(_move_controller.call("request_selected_vehicle_move", Vector2i(7, 2))),
		"Long MoveTo accepted at 2x.")
	var switched_command = _arm.runtime_state.active_move_command
	_move_controller._physics_process(0.3)
	for speed_value in [4.0, 0.5, 2.0, 1.0]:
		_check("E2E-06", bool(_scene.call("set_simulation_speed", speed_value)),
			"Switch to %.1fx mid-move." % speed_value)
		_check("E2E-06", _arm.runtime_state.active_move_command == switched_command,
			"Command survives mid-move switch to %.1fx." % speed_value)
	_move_controller._physics_process(0.3)
	_scene.call("pause_scene")
	_move_controller._physics_process(1.0)
	var switched_frozen: Vector3 = _arm.global_position
	_scene.call("resume_scene")
	_move_controller._physics_process(0.2)
	_check("E2E-06", not _arm.global_position.is_equal_approx(switched_frozen),
		"2x -> Pause -> Resume still advances after resume.")
	await _wait_arrival(_arm, Vector2i(7, 2), "E2E-06")
	_check("E2E-06", _arm.runtime_state.anchor_cell == Vector2i(7, 2)
		and _arm.runtime_state.motion_state == RuntimeStateScript.MotionState.WAITING,
		"Switched-speed move reaches destination.")


# ---------------------------------------------------------------- E2E-07

func _e2e07_no_path_blocked() -> void:
	print("== E2E-07 no_path -> BLOCKED ==")
	_scene.call("reset_scene")
	await process_frame
	var calls_before: int = _gate.call_count
	_check("E2E-07", bool(_selection.call("select_vehicle", _arm)), "Select arm for no_path.")
	_check("E2E-07", not bool(_move_controller.call("request_selected_vehicle_move", Vector2i(-1, -1))),
		"Unreachable MoveTo rejected by the MoveTo service (no_path).")
	_check("E2E-07", _gate.call_count == calls_before + 1, "Compile gate ran for rejected move too.")
	_check("E2E-07", int(_scene.call("get_lifecycle_state")) == LifecycleStateScript.State.RUNNING,
		"Lifecycle not corrupted by path failure.")
	_check("E2E-07", _arm.runtime_state.motion_state == RuntimeStateScript.MotionState.BLOCKED,
		"no_path -> BLOCKED.")
	_check("E2E-07", _arm.runtime_state.active_move_command == null,
		"No residual command after no_path.")
	_check("E2E-07", String(_move_controller.call("get_last_rejection_reason")) == "no_path",
		"Rejection reason is no_path.")
	_move_controller._physics_process(0.5)
	_check("E2E-07", _arm.runtime_state.motion_state == RuntimeStateScript.MotionState.BLOCKED,
		"No fake movement while BLOCKED.")
	_check("E2E-07", bool(_move_controller.call("request_selected_vehicle_move", Vector2i(5, 2))),
		"Recovery: a new legal MoveTo is accepted.")
	await _wait_arrival(_arm, Vector2i(5, 2), "E2E-07")
	_check("E2E-07", _arm.runtime_state.anchor_cell == Vector2i(5, 2)
		and _arm.runtime_state.motion_state == RuntimeStateScript.MotionState.WAITING,
		"Vehicle recovers after BLOCKED.")


# ---------------------------------------------------------------- E2E-08..11 logistics

func _e2e08_11_logistics() -> void:
	print("== E2E-08..11 Manual logistics regression ==")
	_scene.call("reset_scene")
	await process_frame
	var pile = _object_manager.get_block_pile()
	var box = _object_manager.get_standard_box()
	var ground_field = _object_manager.get_ground_block_field()
	_check("E2E-08", pile != null and box != null and ground_field != null,
		"Logistics domains ready.")
	if pile == null or box == null or ground_field == null:
		return
	var produced_base: int = pile.get_produced_count()

	# E2E-08: Pile -> Arm through the real key route (C) after a REAL move to the pile.
	_check("E2E-08", bool(_selection.call("select_vehicle", _arm)), "Select arm for pile grab.")
	_check("E2E-08", bool(_move_controller.call("request_selected_vehicle_move", Vector2i(1, 3))),
		"Real MoveTo to pile station accepted.")
	await _wait_arrival(_arm, Vector2i(1, 3), "E2E-08")
	await _face_west()
	await _press_key(KEY_C)
	_check("E2E-08", pile.get_produced_count() == produced_base + 1, "Pile produced exactly one block.")
	_check("E2E-08", _arm.runtime_state.arm_has_item, "Arm carries a real block.")
	_check("E2E-08", _arm.runtime_state.carried_item != null
		and _arm.runtime_state.carried_item.is_claimed_by(_arm.runtime_state),
		"Ownership on arm runtime.")
	var block_a = _arm.runtime_state.carried_item

	# E2E-10: Arm -> Ground -> Arm (round trip at (4,2) facing NORTH).
	_place_vehicle(_arm, Vector2i(4, 2), RuntimeStateScript.Facing.NORTH)
	_check("E2E-10", _arm.runtime_state.carried_item == block_a,
		"Reposition fixture preserves carried block identity.")
	var ground_primary := Vector2i(4, 1)
	await _press_key(KEY_C)
	_check("E2E-10", ground_field.get_item(ground_primary) == block_a, "Ground Drop keeps block identity.")
	_check("E2E-10", block_a.is_claimed_by(ground_field), "Ground field owns dropped block.")
	_check("E2E-10", not _arm.runtime_state.arm_has_item, "Arm empty after Ground Drop.")
	await _press_key(KEY_C)
	_check("E2E-10", _arm.runtime_state.carried_item == block_a, "Ground re-Grab restores identity.")
	_check("E2E-10", not ground_field.has_item(ground_primary), "Ground cell empty after re-Grab.")

	# E2E-09: Arm -> Tray then Tray -> Arm.
	_place_vehicle(_arm, Vector2i(5, 4), RuntimeStateScript.Facing.EAST)
	_check("E2E-09", int(_transport.runtime_state.tray_count) == 0, "Tray empty before Drop.")
	await _press_key(KEY_C)
	_check("E2E-09", _transport.runtime_state.tray_count == 1, "Tray 1/8 after Drop.")
	_check("E2E-09", not _arm.runtime_state.arm_has_item, "Arm empty after Tray Drop.")
	_check("E2E-09", block_a.is_claimed_by(_transport.runtime_state.tray_state),
		"Tray owns dropped block.")
	await _press_key(KEY_C)
	_check("E2E-09", _transport.runtime_state.tray_count == 0, "Tray re-Grab empties tray.")
	_check("E2E-09", _arm.runtime_state.carried_item == block_a, "Tray -> Arm restores identity.")

	# E2E-11: Arm -> Box (4/8).
	_place_vehicle(_arm, Vector2i(9, 3), RuntimeStateScript.Facing.EAST)
	var box_before: int = box.get_current_count()
	await _press_key(KEY_C)
	_check("E2E-11", box.get_current_count() == box_before + 1, "Box incremented after Drop.")
	_check("E2E-11", not _arm.runtime_state.arm_has_item, "Arm empty after Box Drop.")
	_check("E2E-11", box.contains_item(block_a), "Box owns the exact dropped block.")

	# Fill StandardBox to 8/8 through repeated pile -> box transfers.
	var guard := 0
	while box.get_current_count() < 8 and guard < 12:
		_place_vehicle(_arm, Vector2i(1, 3), RuntimeStateScript.Facing.WEST)
		var grab_result = _grab_drop.call("request_selected_grab_drop")
		_check("E2E-11", grab_result != null
			and grab_result.status == GrabDropResultScript.Status.ACCEPTED, "Pile supplies filler block.")
		if grab_result == null or not grab_result.is_success():
			break
		_place_vehicle(_arm, Vector2i(9, 3), RuntimeStateScript.Facing.EAST)
		var drop_result = _grab_drop.call("request_selected_grab_drop")
		_check("E2E-11", drop_result != null
			and drop_result.status == GrabDropResultScript.Status.ACCEPTED, "Filler block dropped into box.")
		if drop_result == null or not drop_result.is_success():
			break
		guard += 1
	_check("E2E-11", box.get_current_count() == 8, "StandardBox reached 8/8.")
	_check("E2E-11", int(box.get_capacity()) == 8, "Box capacity consistent.")

	# Full-box rejection: loaded arm facing a full box must not corrupt state.
	_place_vehicle(_arm, Vector2i(1, 3), RuntimeStateScript.Facing.WEST)
	var full_grab = _grab_drop.call("request_selected_grab_drop")
	_check("E2E-11", full_grab != null and full_grab.is_success() and _arm.runtime_state.arm_has_item,
		"Arm loaded for full-box rejection probe.")
	if full_grab != null and full_grab.is_success():
		_place_vehicle(_arm, Vector2i(9, 3), RuntimeStateScript.Facing.EAST)
		var rejected = _grab_drop.call("request_selected_grab_drop")
		_check("E2E-11", rejected != null and rejected.status == GrabDropResultScript.Status.FULL,
			"Full box rejects Drop (FULL).")
		_check("E2E-11", box.get_current_count() == 8 and _arm.runtime_state.arm_has_item,
			"Rejected Drop keeps box 8/8 and arm cargo.")
		_check("E2E-11", _arm.runtime_state.carried_item.is_claimed_by(_arm.runtime_state),
			"Rejected Drop preserves ownership.")


# ---------------------------------------------------------------- E2E-12

func _e2e12_pause_grab_drop() -> void:
	print("== E2E-12 Pause + GrabDrop ==")
	var box = _object_manager.get_standard_box()
	var ground_field = _object_manager.get_ground_block_field()
	if box == null or ground_field == null:
		return
	_place_vehicle(_arm, Vector2i(1, 3), RuntimeStateScript.Facing.WEST)
	_check("E2E-12", _arm.runtime_state.arm_has_item and _arm.runtime_state.carried_item != null,
		"Arm holds block before Pause probe.")
	if not _arm.runtime_state.arm_has_item:
		return
	var carried = _arm.runtime_state.carried_item
	var facing_before: int = _arm.runtime_state.facing
	_scene.call("pause_scene")
	_check("E2E-12", int(_scene.call("get_lifecycle_state")) == LifecycleStateScript.State.PAUSED,
		"PAUSED before A/D/C attempts.")
	await _press_key(KEY_A)
	_check("E2E-12", _arm.runtime_state.facing == facing_before, "A rejected while PAUSED.")
	await _press_key(KEY_D)
	_check("E2E-12", _arm.runtime_state.facing == facing_before, "D rejected while PAUSED.")
	await _press_key(KEY_C)
	_check("E2E-12", _arm.runtime_state.arm_has_item and _arm.runtime_state.carried_item == carried,
		"C rejected while PAUSED: block unchanged.")
	_check("E2E-12", carried.is_claimed_by(_arm.runtime_state), "Ownership unchanged while PAUSED.")
	_scene.call("resume_scene")
	await process_frame
	_place_vehicle(_arm, Vector2i(4, 2), RuntimeStateScript.Facing.NORTH)
	var resume_drop = _grab_drop.call("request_selected_grab_drop")
	_check("E2E-12", resume_drop != null and resume_drop.is_success(),
		"C after Resume completes normally.")
	_check("E2E-12", not _arm.runtime_state.arm_has_item, "Post-resume Drop emptied arm.")
	_check("E2E-12", ground_field.get_item(Vector2i(4, 1)) == carried,
		"Post-resume Drop transferred exact block to ground.")


# ---------------------------------------------------------------- E2E-13/14

func _e2e13_14_dirty_reset() -> void:
	print("== E2E-13/14 Dirty-state Reset + idempotence ==")
	var pile = _object_manager.get_block_pile()
	var box = _object_manager.get_standard_box()
	var ground_field = _object_manager.get_ground_block_field()
	if pile == null or box == null or ground_field == null:
		return

	# Dirty: RUNNING 2x, arm holds a block, tray 1/8, ground 1 block, box 8/8, transport moved.
	_check("E2E-13", bool(_scene.call("set_simulation_speed", 2.0)), "Dirty: speed 2x.")
	_place_vehicle(_arm, Vector2i(1, 3), RuntimeStateScript.Facing.WEST)
	var held_grab = _grab_drop.call("request_selected_grab_drop")
	_check("E2E-13", held_grab != null and held_grab.is_success() and _arm.runtime_state.arm_has_item,
		"Dirty: arm holds block.")
	var held_block = _arm.runtime_state.carried_item if held_grab != null and held_grab.is_success() else null
	_place_vehicle(_transport, Vector2i(6, 3), RuntimeStateScript.Facing.WEST)
	var tray_cargo := StandardBlockScript.create()
	_check("E2E-13", _transport.runtime_state.tray_state.put_item(tray_cargo).is_success(),
		"Dirty: tray accepts real cargo.")
	_check("E2E-13", ground_field.get_occupied_cells().size() == 1, "Dirty: ground block from E2E-12 remains.")
	_check("E2E-13", box.get_current_count() == 8, "Dirty: box 8/8.")
	_check("E2E-13", int(_scene.call("get_lifecycle_state")) == LifecycleStateScript.State.RUNNING,
		"Dirty: lifecycle RUNNING.")

	var clean := _expected_clean_invariants()
	_check("E2E-13", bool(_scene.call("reset_scene")), "Explicit Reset succeeds.")
	await process_frame
	_check("E2E-13", _matches_invariants(clean),
		"Reset restored READY/1x/world (anchors, commands, ownership, counts).")
	if held_block != null and is_instance_valid(held_block):
		_check("E2E-13", not held_block.is_claimed(), "Former arm cargo released.")
	if is_instance_valid(tray_cargo):
		_check("E2E-13", not tray_cargo.is_claimed(), "Former tray cargo released.")
	_check("E2E-13", not bool(_selection.call("has_selected_vehicle")), "Selection cancelled.")
	_check("E2E-13", not bool(_grid_selection.call("is_live_target_mode")), "Target mode cancelled.")
	_check("E2E-13", is_equal_approx(float(Engine.time_scale), 1.0), "Engine.time_scale stays 1.")

	var snapshot_first := _snapshot_invariants()
	_check("E2E-14", bool(_scene.call("reset_scene")), "Second consecutive Reset succeeds.")
	await process_frame
	_check("E2E-14", _matches_invariants(snapshot_first),
		"Second Reset idempotent (state identical, no extra blocks).")
	_check("E2E-14", _matches_invariants(clean), "Second Reset still equals clean initial state.")
	_check("E2E-14", _prep_failures.is_empty(), "No compile failure across Resets.")


# ---------------------------------------------------------------- E2E-15

func _e2e15_run_after_reset() -> void:
	print("== E2E-15 Run again after Reset (no scene restart) ==")
	var calls_before: int = _gate.call_count
	_check("E2E-15", int(_scene.call("get_lifecycle_state")) == LifecycleStateScript.State.READY,
		"READY after Resets.")
	_check("E2E-15", bool(_selection.call("select_vehicle", _arm)), "Select arm post-Reset.")
	_check("E2E-15", bool(_move_controller.call("request_selected_vehicle_move", Vector2i(5, 2))),
		"MoveTo accepted post-Reset (auto RUNNING).")
	_check("E2E-15", _gate.call_count == calls_before + 1, "Compile gate still live post-Reset.")
	_check("E2E-15", int(_scene.call("get_lifecycle_state")) == LifecycleStateScript.State.RUNNING,
		"Lifecycle RUNNING post-Reset.")
	await _wait_arrival(_arm, Vector2i(5, 2), "E2E-15")
	_check("E2E-15", _arm.runtime_state.anchor_cell == Vector2i(5, 2), "Move completes post-Reset.")
	_place_vehicle(_arm, Vector2i(1, 3), RuntimeStateScript.Facing.WEST)
	await _face_west()
	var grab_result = _grab_drop.call("request_selected_grab_drop")
	_check("E2E-15", grab_result != null and grab_result.is_success() and _arm.runtime_state.arm_has_item,
		"Pile Grab works post-Reset.")
	if grab_result != null and grab_result.is_success():
		_place_vehicle(_arm, Vector2i(4, 2), RuntimeStateScript.Facing.NORTH)
		var drop_result = _grab_drop.call("request_selected_grab_drop")
		_check("E2E-15", drop_result != null and drop_result.is_success(),
			"Ground Drop works post-Reset.")
	_check("E2E-15", _prep_failures.is_empty(), "No compile/lifecycle failure post-Reset.")


# ---------------------------------------------------------------- helpers

func _expected_clean_invariants() -> Dictionary:
	return {
		"state": int(LifecycleStateScript.State.READY),
		"speed": 1.0,
		"arm_anchor": Vector2i(2, 2),
		"transport_anchor": Vector2i(7, 4),
		"arm_motion": int(RuntimeStateScript.MotionState.WAITING),
		"transport_motion": int(RuntimeStateScript.MotionState.WAITING),
		"arm_command_null": true,
		"transport_command_null": true,
		"arm_has_item": false,
		"tray_count": 0,
		"box_count": 3,
		"pile_produced": 0,
		"ground_occupied": 0,
	}


func _snapshot_invariants() -> Dictionary:
	var ground = _object_manager.get_ground_block_field()
	return {
		"state": int(_scene.call("get_lifecycle_state")),
		"speed": float(_scene.call("get_simulation_speed")),
		"arm_anchor": _arm.runtime_state.anchor_cell,
		"transport_anchor": _transport.runtime_state.anchor_cell,
		"arm_motion": int(_arm.runtime_state.motion_state),
		"transport_motion": int(_transport.runtime_state.motion_state),
		"arm_command_null": _arm.runtime_state.active_move_command == null,
		"transport_command_null": _transport.runtime_state.active_move_command == null,
		"arm_has_item": _arm.runtime_state.arm_has_item,
		"tray_count": int(_transport.runtime_state.tray_count),
		"box_count": int(_object_manager.get_standard_box().get_current_count()),
		"pile_produced": int(_object_manager.get_block_pile().get_produced_count()),
		"ground_occupied": ground.get_occupied_cells().size(),
	}


func _matches_invariants(snapshot: Dictionary) -> bool:
	var current := _snapshot_invariants()
	var matched := true
	for key in snapshot.keys():
		if current.get(key) != snapshot[key]:
			matched = false
			_check("RESET-INV", false, "Invariant %s expected %s got %s."
				% [str(key), str(snapshot[key]), str(current.get(key))])
	return matched


func _measure_seconds_to_finish(target: Vector2i) -> float:
	var elapsed := 0.0
	var steps := 0
	while _arm.runtime_state.motion_state == RuntimeStateScript.MotionState.MOVING and steps < 6000:
		_move_controller._physics_process(0.02)
		elapsed += 0.02
		steps += 1
	return elapsed


func _wait_arrival(vehicle: Node, target: Vector2i, context: String) -> void:
	var steps := 0
	while vehicle.runtime_state.motion_state == RuntimeStateScript.MotionState.MOVING and steps < 4000:
		_move_controller._physics_process(0.05)
		steps += 1
		if steps % 400 == 0:
			await process_frame
	_check(context, vehicle.runtime_state.anchor_cell == target, "%s: arrival at %s."
		% [context, str(target)])


func _place_vehicle(vehicle: Node, anchor: Vector2i, facing: int) -> void:
	vehicle.runtime_state.anchor_cell = anchor
	vehicle.runtime_state.facing = facing
	vehicle.sync_from_state()


func _face_west() -> void:
	var guard := 0
	while _arm.runtime_state.facing != RuntimeStateScript.Facing.WEST and guard < 4:
		_grab_drop.call("rotate_selected_arm", -1)
		guard += 1


func _press_key(keycode: int) -> void:
	root.push_input(_key_event(keycode, true))
	await process_frame
	root.push_input(_key_event(keycode, false))
	await process_frame


func _key_event(keycode: int, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = pressed
	event.keycode = keycode
	return event


func _on_prep_failed(reason: StringName) -> void:
	_prep_failures.append(reason)


func _cleanup_scene() -> void:
	if _scene != null and is_instance_valid(_scene):
		_scene.queue_free()
		await process_frame


func _in_range(value: float, low: float, high: float) -> bool:
	return value >= low and value <= high


func _finish_suite() -> void:
	if _failures == 0:
		print("Scene 01 post-merge E2E suite passed.")
		quit(0)
		return
	push_error("Scene 01 post-merge E2E suite failed: %d failure(s)." % _failures)
	quit(1)


func _check(id: String, ok: bool, message: String) -> void:
	if ok:
		print("[%s] PASS %s" % [id, message])
		return
	_failures += 1
	push_error("[%s] FAIL %s" % [id, message])

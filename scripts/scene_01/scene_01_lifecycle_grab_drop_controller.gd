class_name Scene01LifecycleGrabDropController
extends "res://scripts/input/vehicle_grab_drop_controller.gd"

const GAMEPLAY_START_ACCEPTED := &"accepted"
const GAMEPLAY_START_PREFLIGHT_REJECTED := &"command_preflight_rejected"

@export var scene_controller_path: NodePath = NodePath("../../..")

var _scene_controller: Node


func _ready() -> void:
	_scene_controller = get_node_or_null(scene_controller_path)
	super._ready()
	var input_router := get_node_or_null("../VehicleGrabDropInputRouter")
	if input_router != null:
		# The router is the single input owner in Scene 01. It forwards each event
		# explicitly, so the engine callback on this controller must stay disabled.
		set_process_unhandled_input(false)
	if not _has_lifecycle_contract():
		push_error("Scene01LifecycleGrabDropController requires a lifecycle scene controller.")
	refresh_interaction_preview()


func _unhandled_input(event: InputEvent) -> void:
	if _is_lifecycle_paused():
		return
	super._unhandled_input(event)


func request_selected_grab_drop() -> GrabDropResultScript:
	if _is_lifecycle_paused():
		return _reject_for_lifecycle_pause()
	if _get_selected_vehicle() == null:
		return super.request_selected_grab_drop()

	var start_result := _try_start_gameplay_command(
		Callable(self, "_can_execute_selected_grab_drop")
	)
	if start_result == GAMEPLAY_START_ACCEPTED:
		return super.request_selected_grab_drop()
	if start_result == GAMEPLAY_START_PREFLIGHT_REJECTED:
		return super.request_selected_grab_drop()
	return _reject_for_run_preparation()


func rotate_selected_arm(direction: int) -> bool:
	if _is_lifecycle_paused():
		return false
	var step := clampi(direction, -1, 1)
	if step == 0 or _get_selected_vehicle() == null:
		return false

	var start_result := _try_start_gameplay_command(
		Callable(self, "_can_rotate_selected_arm_after_preparation")
	)
	if start_result != GAMEPLAY_START_ACCEPTED:
		return false
	return super.rotate_selected_arm(direction)


func refresh_interaction_preview() -> void:
	if _is_lifecycle_paused():
		_hide_interaction_preview()
		return
	super.refresh_interaction_preview()


func sync_lifecycle_state() -> void:
	refresh_interaction_preview()


func _can_rotate_selected_arm_after_preparation() -> bool:
	var vehicle := _get_selected_vehicle()
	return vehicle != null and _can_rotate(vehicle)


func _can_execute_selected_grab_drop() -> bool:
	var vehicle := _get_selected_vehicle()
	if vehicle == null or vehicle.definition == null or vehicle.runtime_state == null:
		return false
	if not vehicle.definition.has_capability(VehicleDefinitionScript.CAPABILITY_CAN_GRAB):
		return false
	if (
		vehicle.runtime_state.motion_state == VehicleRuntimeStateScript.MotionState.PLANNING
		or vehicle.runtime_state.motion_state == VehicleRuntimeStateScript.MotionState.MOVING
	):
		return false
	var target: Variant = resolve_target_for_vehicle(vehicle)
	return target != null and _is_target_ready(vehicle.runtime_state, target)


func _reject_for_lifecycle_pause() -> GrabDropResultScript:
	return _emit_lifecycle_rejection(GrabDropResultScript.Status.BUSY)


func _reject_for_run_preparation() -> GrabDropResultScript:
	return _emit_lifecycle_rejection(GrabDropResultScript.Status.RUN_PREPARATION_FAILED)


func _emit_lifecycle_rejection(status: int) -> GrabDropResultScript:
	var vehicle := _get_selected_vehicle()
	var action := GrabDropResultScript.Action.NONE
	var vehicle_id: StringName = &""
	if vehicle != null:
		vehicle_id = vehicle.get_vehicle_id()
		if vehicle.runtime_state != null:
			action = (
				GrabDropResultScript.Action.DROP
				if vehicle.runtime_state.arm_has_item
				else GrabDropResultScript.Action.GRAB
			)
	var result := GrabDropResultScript.rejected(action, status)
	grab_drop_completed.emit(vehicle_id, result.action, result.status)
	return result


func _try_start_gameplay_command(preflight: Callable) -> StringName:
	if not _has_lifecycle_contract():
		return &"invalid_gameplay_start"
	return StringName(_scene_controller.call("try_start_gameplay_command", preflight))


func _is_lifecycle_paused() -> bool:
	if not _has_lifecycle_contract():
		return true
	return bool(_scene_controller.call("is_scene_paused"))


func _has_lifecycle_contract() -> bool:
	return (
		_scene_controller != null
		and is_instance_valid(_scene_controller)
		and _scene_controller.has_method("try_start_gameplay_command")
		and _scene_controller.has_method("is_scene_paused")
	)

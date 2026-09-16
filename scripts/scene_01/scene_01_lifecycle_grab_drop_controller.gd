class_name Scene01LifecycleGrabDropController
extends "res://scripts/input/vehicle_grab_drop_controller.gd"

@export var scene_controller_path: NodePath = NodePath("../../..")

var _scene_controller: Node
var _command_vehicle_override: VehicleActor
var _has_command_vehicle_override := false


func _ready() -> void:
	_scene_controller = get_node_or_null(scene_controller_path)
	super._ready()
	if not _has_lifecycle_contract():
		push_error("Scene01LifecycleGrabDropController requires a lifecycle scene controller.")
	refresh_interaction_preview()


func _unhandled_input(event: InputEvent) -> void:
	if _is_lifecycle_paused():
		return
	super._unhandled_input(event)


func request_selected_grab_drop() -> GrabDropResultScript:
	return request_vehicle_grab_drop(super._get_selected_vehicle())


func request_vehicle_grab_drop(vehicle: VehicleActor) -> GrabDropResultScript:
	if _is_lifecycle_paused():
		return null
	if vehicle != null and not _ensure_gameplay_running():
		return null
	_command_vehicle_override = vehicle
	_has_command_vehicle_override = true
	var result := super.request_selected_grab_drop()
	_has_command_vehicle_override = false
	_command_vehicle_override = null
	return result


func rotate_selected_arm(direction: int) -> bool:
	if _is_lifecycle_paused():
		return false
	var step := clampi(direction, -1, 1)
	if step == 0 or _get_selected_vehicle() == null:
		return false
	if not _ensure_gameplay_running():
		return false
	return super.rotate_selected_arm(direction)


func refresh_interaction_preview() -> void:
	if _is_lifecycle_paused():
		_hide_interaction_preview()
		return
	super.refresh_interaction_preview()


func sync_lifecycle_state() -> void:
	refresh_interaction_preview()


func _get_selected_vehicle():
	if _has_command_vehicle_override:
		return _command_vehicle_override
	return super._get_selected_vehicle()


func _ensure_gameplay_running() -> bool:
	if not _has_lifecycle_contract():
		return false
	return bool(_scene_controller.call("ensure_gameplay_running"))


func _is_lifecycle_paused() -> bool:
	if not _has_lifecycle_contract():
		return true
	return bool(_scene_controller.call("is_scene_paused"))


func _has_lifecycle_contract() -> bool:
	return (
		_scene_controller != null
		and is_instance_valid(_scene_controller)
		and _scene_controller.has_method("ensure_gameplay_running")
		and _scene_controller.has_method("is_scene_paused")
	)

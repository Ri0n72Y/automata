class_name Scene01LifecycleGrabDropController
extends "res://scripts/input/vehicle_grab_drop_controller.gd"

@export var scene_controller_path: NodePath = NodePath("../../..")

var _scene_controller: Node


func _ready() -> void:
	_scene_controller = get_node_or_null(scene_controller_path)
	super._ready()
	if not _has_lifecycle_contract():
		push_error("Scene01LifecycleGrabDropController requires a lifecycle scene controller.")
	refresh_interaction_preview()


func _physics_process(delta: float) -> void:
	if not _is_lifecycle_running():
		return
	super._physics_process(maxf(delta, 0.0) * _get_lifecycle_speed())


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
	var result := super.request_vehicle_grab_drop(vehicle) as GrabDropResultScript
	refresh_interaction_preview()
	return result


func request_vehicle_turn(vehicle: VehicleActor, direction: int) -> bool:
	if _is_lifecycle_paused():
		return false
	if vehicle != null and not _ensure_gameplay_running():
		return false
	return super.request_vehicle_turn(vehicle, direction)


func rotate_selected_arm(direction: int) -> bool:
	return request_vehicle_turn(super._get_selected_vehicle(), direction)


func refresh_interaction_preview() -> void:
	if _is_lifecycle_paused():
		_hide_interaction_preview()
		return
	super.refresh_interaction_preview()


func sync_lifecycle_state() -> void:
	refresh_interaction_preview()


func _ensure_gameplay_running() -> bool:
	if not _has_lifecycle_contract():
		return false
	return bool(_scene_controller.call("ensure_gameplay_running"))


func _is_lifecycle_running() -> bool:
	if not _has_lifecycle_contract():
		return false
	return bool(_scene_controller.call("is_gameplay_running"))


func _get_lifecycle_speed() -> float:
	if not _has_lifecycle_contract() or not _scene_controller.has_method("get_simulation_speed"):
		return 0.0
	return maxf(float(_scene_controller.call("get_simulation_speed")), 0.0)


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

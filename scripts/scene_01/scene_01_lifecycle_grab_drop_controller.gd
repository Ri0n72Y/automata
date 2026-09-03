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


func _unhandled_input(event: InputEvent) -> void:
	if _is_lifecycle_paused():
		return
	super._unhandled_input(event)


func request_selected_grab_drop() -> GrabDropResultScript:
	if _is_lifecycle_paused():
		return null
	if _get_selected_vehicle() == null:
		return super.request_selected_grab_drop()
	if not _ensure_gameplay_running():
		return null
	return super.request_selected_grab_drop()


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

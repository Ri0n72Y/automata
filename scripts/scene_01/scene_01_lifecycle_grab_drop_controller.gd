class_name Scene01LifecycleGrabDropController
extends "res://scripts/input/vehicle_grab_drop_controller.gd"

const BaseGrabDropControllerScript := preload("res://scripts/input/vehicle_grab_drop_controller.gd")
const CommandSelectionProxyScript := preload("res://scripts/scene_01/scene_01_command_vehicle_selection_proxy.gd")

@export var scene_controller_path: NodePath = NodePath("../../..")

var _scene_controller: Node
var _command_delegate: BaseGrabDropControllerScript
var _command_selection: Scene01CommandVehicleSelectionProxy


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
	_prepare_command_delegate(vehicle)
	var result := _command_delegate.request_selected_grab_drop() as GrabDropResultScript
	_command_selection.clear_command_vehicle()
	refresh_interaction_preview()
	if result != null:
		var vehicle_id := vehicle.get_vehicle_id() if vehicle != null else &""
		grab_drop_completed.emit(vehicle_id, result.action, result.status)
	return result


func rotate_selected_arm(direction: int) -> bool:
	if _is_lifecycle_paused():
		return false
	var step := clampi(direction, -1, 1)
	if step == 0 or super._get_selected_vehicle() == null:
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


func _prepare_command_delegate(vehicle: VehicleActor) -> void:
	if _command_selection == null:
		_command_selection = CommandSelectionProxyScript.new()
	if _command_delegate == null:
		_command_delegate = BaseGrabDropControllerScript.new()
	_command_selection.set_command_vehicle(vehicle)
	_command_delegate.vehicle_selection_controller = _command_selection
	_command_delegate.vehicle_manager = vehicle_manager
	_command_delegate.object_manager = object_manager


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

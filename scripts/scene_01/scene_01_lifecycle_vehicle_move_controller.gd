class_name Scene01LifecycleVehicleMoveController
extends "res://scripts/input/vehicle_move_controller.gd"

const BaseMoveControllerScript := preload("res://scripts/input/vehicle_move_controller.gd")
const CommandSelectionProxyScript := preload("res://scripts/scene_01/scene_01_command_vehicle_selection_proxy.gd")

var _command_delegate: BaseMoveControllerScript
var _command_selection: Scene01CommandVehicleSelectionProxy


func _physics_process(delta: float) -> void:
	if not _is_lifecycle_running():
		return
	super._physics_process(maxf(delta, 0.0) * _get_lifecycle_speed())


func _unhandled_input(event: InputEvent) -> void:
	if _is_lifecycle_paused():
		return
	super._unhandled_input(event)


func request_selected_vehicle_move(target_anchor: Vector2i) -> bool:
	return request_vehicle_move(super._get_selected_vehicle(), target_anchor)


func request_vehicle_move(vehicle: VehicleActor, target_anchor: Vector2i) -> bool:
	if vehicle != null and not _ensure_gameplay_running():
		return false
	_prepare_command_delegate(vehicle)
	var vehicle_id := vehicle.get_vehicle_id() if vehicle != null else &""
	move_requested.emit(vehicle_id, target_anchor)
	var accepted := _command_delegate.request_selected_vehicle_move(target_anchor)
	var rejection := _command_delegate.get_last_rejection_reason()
	_command_selection.clear_command_vehicle()
	_last_rejection_reason = &"" if accepted else rejection
	if accepted:
		move_accepted.emit(vehicle_id, target_anchor)
		_clear_grid_target()
		_face_vehicle_for_final_step(vehicle)
	else:
		move_rejected.emit(vehicle_id, target_anchor, rejection)
	_sync_live_target_mode()
	return accepted


func request_selected_vehicle_stop() -> bool:
	if not _is_lifecycle_running():
		return false
	return super.request_selected_vehicle_stop()


func sync_lifecycle_state() -> void:
	_sync_live_target_mode()


func _prepare_command_delegate(vehicle: VehicleActor) -> void:
	if _command_selection == null:
		_command_selection = CommandSelectionProxyScript.new()
	if _command_delegate == null:
		_command_delegate = BaseMoveControllerScript.new()
	_command_selection.set_command_vehicle(vehicle)
	_command_delegate.controller = controller
	_command_delegate.vehicle_selection_controller = _command_selection
	_command_delegate.vehicle_manager = vehicle_manager
	_command_delegate.grid_selection_controller = null


func _sync_live_target_mode() -> void:
	super._sync_live_target_mode()
	if grid_selection_controller == null or not _is_lifecycle_paused():
		return
	var vehicle := super._get_selected_vehicle()
	var footprint := Vector2i.ONE
	if vehicle != null and vehicle.definition != null:
		footprint = vehicle.definition.footprint
	grid_selection_controller.set_live_target_mode(false, footprint)
	_hide_prediction()


func _face_vehicle_for_final_step(vehicle: VehicleActor) -> void:
	if vehicle == null or vehicle.runtime_state == null:
		return
	var command = vehicle.runtime_state.active_move_command
	if command == null or command.path.size() < 2:
		return
	var step: Vector2i = command.path[command.path.size() - 1] - command.path[command.path.size() - 2]
	if step == Vector2i(1, 0):
		vehicle.runtime_state.facing = VehicleRuntimeStateScript.Facing.EAST
	elif step == Vector2i(-1, 0):
		vehicle.runtime_state.facing = VehicleRuntimeStateScript.Facing.WEST
	elif step == Vector2i(0, 1):
		vehicle.runtime_state.facing = VehicleRuntimeStateScript.Facing.SOUTH
	elif step == Vector2i(0, -1):
		vehicle.runtime_state.facing = VehicleRuntimeStateScript.Facing.NORTH
	vehicle.sync_from_state()


func _ensure_gameplay_running() -> bool:
	if controller == null or not controller.has_method("ensure_gameplay_running"):
		return false
	return bool(controller.call("ensure_gameplay_running"))


func _is_lifecycle_running() -> bool:
	if controller == null or not controller.has_method("is_gameplay_running"):
		return false
	return bool(controller.call("is_gameplay_running"))


func _is_lifecycle_paused() -> bool:
	if controller == null or not controller.has_method("is_scene_paused"):
		return true
	return bool(controller.call("is_scene_paused"))


func _get_lifecycle_speed() -> float:
	if controller == null or not controller.has_method("get_simulation_speed"):
		return 0.0
	return maxf(float(controller.call("get_simulation_speed")), 0.0)

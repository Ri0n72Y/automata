class_name Scene01ObservableState
extends Node

signal vehicle_state_changed(vehicle_id: StringName, previous_state: int, current_state: int)
signal arm_has_item_changed(previous_value: bool, current_value: bool)
signal tray_count_changed(previous_count: int, current_count: int)
signal standard_box_count_changed(previous_count: int, current_count: int)
signal mission_state_changed(previous_state: int, current_state: int)

const VehicleManagerScript := preload("res://scripts/scene_01/scene_01_vehicle_manager.gd")
const ObjectManagerScript := preload("res://scripts/scene_01/scene_01_object_manager.gd")
const VehicleRuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const StandardBoxScript := preload("res://scripts/objects/standard_box.gd")
const TransportTrayStateScript := preload("res://scripts/vehicles/transport_tray_state.gd")

var _mission_controller: Node
var _arm_runtime: VehicleRuntimeStateScript
var _transport_runtime: VehicleRuntimeStateScript
var _tray_state: TransportTrayStateScript
var _standard_box: StandardBoxScript
var _configured: bool = false


func configure(
	vehicle_manager: VehicleManagerScript,
	object_manager: ObjectManagerScript,
	mission_controller: Node
) -> bool:
	if _configured:
		return true
	if vehicle_manager == null or object_manager == null or mission_controller == null:
		return false
	if not mission_controller.has_method("get_mission_state"):
		return false
	if not mission_controller.has_signal("mission_state_changed"):
		return false

	var arm = vehicle_manager.get_vehicle_by_id(VehicleManagerScript.ARM_VEHICLE_ID)
	var transport = vehicle_manager.get_vehicle_by_id(VehicleManagerScript.TRANSPORT_VEHICLE_ID)
	if arm == null or transport == null:
		return false
	if arm.runtime_state == null or transport.runtime_state == null:
		return false
	var standard_box := object_manager.get_standard_box()
	if standard_box == null or transport.runtime_state.tray_state == null:
		return false

	_mission_controller = mission_controller
	_arm_runtime = arm.runtime_state
	_transport_runtime = transport.runtime_state
	_tray_state = transport.runtime_state.tray_state
	_standard_box = standard_box

	_arm_runtime.motion_state_changed.connect(
		_on_vehicle_state_changed.bind(VehicleManagerScript.ARM_VEHICLE_ID)
	)
	_transport_runtime.motion_state_changed.connect(
		_on_vehicle_state_changed.bind(VehicleManagerScript.TRANSPORT_VEHICLE_ID)
	)
	_arm_runtime.arm_has_item_changed.connect(_on_arm_has_item_changed)
	_tray_state.count_changed.connect(_on_tray_count_changed)
	_standard_box.count_changed.connect(_on_standard_box_count_changed)
	_mission_controller.connect("mission_state_changed", _on_mission_state_changed)

	_configured = true
	return true


func is_configured() -> bool:
	return _configured


func get_vehicle_state(vehicle_id: StringName) -> int:
	var runtime := _get_vehicle_runtime(vehicle_id)
	if runtime == null:
		push_error("Scene 01 observable state does not expose vehicle %s." % String(vehicle_id))
		return -1
	return runtime.motion_state


func get_arm_has_item() -> bool:
	return _arm_runtime.arm_has_item if _arm_runtime != null else false


func get_tray_count() -> int:
	return _tray_state.get_current_count() if _tray_state != null else 0


func get_standard_box_count() -> int:
	return _standard_box.get_current_count() if _standard_box != null else 0


func get_mission_state() -> int:
	if _mission_controller == null:
		return -1
	return int(_mission_controller.call("get_mission_state"))


func _get_vehicle_runtime(vehicle_id: StringName) -> VehicleRuntimeStateScript:
	match vehicle_id:
		VehicleManagerScript.ARM_VEHICLE_ID:
			return _arm_runtime
		VehicleManagerScript.TRANSPORT_VEHICLE_ID:
			return _transport_runtime
		_:
			return null


func _on_vehicle_state_changed(
	previous_state: int,
	current_state: int,
	vehicle_id: StringName
) -> void:
	vehicle_state_changed.emit(vehicle_id, previous_state, current_state)


func _on_arm_has_item_changed(previous_value: bool, current_value: bool) -> void:
	arm_has_item_changed.emit(previous_value, current_value)


func _on_tray_count_changed(previous_count: int, current_count: int) -> void:
	tray_count_changed.emit(previous_count, current_count)


func _on_standard_box_count_changed(previous_count: int, current_count: int) -> void:
	standard_box_count_changed.emit(previous_count, current_count)


func _on_mission_state_changed(previous_state: int, current_state: int) -> void:
	mission_state_changed.emit(previous_state, current_state)

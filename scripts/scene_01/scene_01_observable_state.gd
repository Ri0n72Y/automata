class_name Scene01ObservableState
extends Node

signal configured()
signal vehicle_state_changed(vehicle_id: StringName, previous_state: int, current_state: int)
signal vehicle_pose_changed(vehicle_id: StringName)
signal vehicle_turning_changed(vehicle_id: StringName, is_turning: bool)
signal vehicle_cargo_changed(vehicle_id: StringName, has_item: bool)
signal vehicle_tray_count_changed(vehicle_id: StringName, count: int)
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
var _vehicle_manager: VehicleManagerScript
var _arm_runtime: VehicleRuntimeStateScript
var _transport_runtime: VehicleRuntimeStateScript
var _tray_state: TransportTrayStateScript
var _standard_box: StandardBoxScript
## Blueprint-deployed vehicles: registered after the fixed preset pair so HUD /
## program consumers can observe them without duplicating the preset contract.
var _dynamic_runtimes: Dictionary = {}


func configure(
	vehicle_manager: VehicleManagerScript,
	object_manager: ObjectManagerScript,
	mission_controller: Node
) -> bool:
	if is_configured():
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
	_vehicle_manager = vehicle_manager
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
	_arm_runtime.anchor_cell_changed.connect(
		_on_vehicle_anchor_cell_changed.bind(VehicleManagerScript.ARM_VEHICLE_ID)
	)
	_transport_runtime.anchor_cell_changed.connect(
		_on_vehicle_anchor_cell_changed.bind(VehicleManagerScript.TRANSPORT_VEHICLE_ID)
	)
	_arm_runtime.facing_changed.connect(
		_on_vehicle_facing_changed.bind(VehicleManagerScript.ARM_VEHICLE_ID)
	)
	_transport_runtime.facing_changed.connect(
		_on_vehicle_facing_changed.bind(VehicleManagerScript.TRANSPORT_VEHICLE_ID)
	)
	arm.turning_changed.connect(
		_on_vehicle_turning_changed.bind(VehicleManagerScript.ARM_VEHICLE_ID)
	)
	transport.turning_changed.connect(
		_on_vehicle_turning_changed.bind(VehicleManagerScript.TRANSPORT_VEHICLE_ID)
	)
	_arm_runtime.arm_has_item_changed.connect(_on_arm_has_item_changed)
	_tray_state.count_changed.connect(_on_tray_count_changed)
	_standard_box.count_changed.connect(_on_standard_box_count_changed)
	_mission_controller.connect("mission_state_changed", _on_mission_state_changed)
	register_dynamic_vehicles()
	configured.emit()
	return true


## Subscribe any newly deployed blueprint vehicles. Idempotent: existing
## registrations are skipped, so controller reconfiguration is safe.
func refresh_vehicles() -> void:
	if _vehicle_manager == null or not is_instance_valid(_vehicle_manager):
		return
	if register_dynamic_vehicles():
		configured.emit()


func register_dynamic_vehicles() -> bool:
	if _vehicle_manager == null:
		return false
	var added := false
	for vehicle_node in _vehicle_manager.get_vehicles():
		var vehicle = vehicle_node
		if vehicle == null or vehicle.runtime_state == null:
			continue
		var vehicle_id: StringName = vehicle.get_vehicle_id()
		if vehicle_id == &"":
			continue
		if (
			vehicle_id == VehicleManagerScript.ARM_VEHICLE_ID
			or vehicle_id == VehicleManagerScript.TRANSPORT_VEHICLE_ID
		):
			continue
		if _dynamic_runtimes.has(vehicle_id):
			continue
		var runtime: VehicleRuntimeStateScript = vehicle.runtime_state
		_dynamic_runtimes[vehicle_id] = runtime
		runtime.motion_state_changed.connect(
			_on_vehicle_state_changed.bind(vehicle_id)
		)
		runtime.anchor_cell_changed.connect(
			_on_vehicle_anchor_cell_changed.bind(vehicle_id)
		)
		runtime.facing_changed.connect(
			_on_vehicle_facing_changed.bind(vehicle_id)
		)
		vehicle.turning_changed.connect(
			_on_vehicle_turning_changed.bind(vehicle_id)
		)
		runtime.arm_has_item_changed.connect(
			_on_dynamic_cargo_changed.bind(vehicle_id)
		)
		if runtime.tray_state != null:
			runtime.tray_state.count_changed.connect(
				_on_dynamic_tray_count_changed.bind(vehicle_id)
			)
		added = true
	return added


func get_vehicle_has_item(vehicle_id: StringName) -> bool:
	var runtime := _get_vehicle_runtime(vehicle_id)
	return runtime.arm_has_item if runtime != null else false


func get_vehicle_tray_count(vehicle_id: StringName) -> int:
	var runtime := _get_vehicle_runtime(vehicle_id)
	if runtime == null or runtime.tray_state == null:
		return 0
	return runtime.tray_state.get_current_count()


func is_configured() -> bool:
	return _mission_controller != null


func get_vehicle_state(vehicle_id: StringName) -> int:
	var runtime := _get_vehicle_runtime(vehicle_id)
	return runtime.motion_state if runtime != null else -1


func get_vehicle_anchor_cell(vehicle_id: StringName) -> Vector2i:
	var runtime := _get_vehicle_runtime(vehicle_id)
	return runtime.anchor_cell if runtime != null else Vector2i(-1, -1)


func get_vehicle_facing(vehicle_id: StringName) -> int:
	var runtime := _get_vehicle_runtime(vehicle_id)
	return runtime.facing if runtime != null else -1


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
	if _dynamic_runtimes.has(vehicle_id):
		return _dynamic_runtimes[vehicle_id]
	if _vehicle_manager != null and is_instance_valid(_vehicle_manager):
		var vehicle = _vehicle_manager.get_vehicle_by_id(vehicle_id)
		if vehicle != null and vehicle.runtime_state != null:
			return vehicle.runtime_state
	return null


func _on_vehicle_state_changed(
	previous_state: int,
	current_state: int,
	vehicle_id: StringName
) -> void:
	vehicle_state_changed.emit(vehicle_id, previous_state, current_state)


func _on_vehicle_anchor_cell_changed(
	_previous_cell: Vector2i,
	_current_cell: Vector2i,
	vehicle_id: StringName
) -> void:
	vehicle_pose_changed.emit(vehicle_id)


func _on_vehicle_facing_changed(
	_previous_facing: int,
	_current_facing: int,
	vehicle_id: StringName
) -> void:
	vehicle_pose_changed.emit(vehicle_id)


func _on_vehicle_turning_changed(is_turning: bool, vehicle_id: StringName) -> void:
	vehicle_turning_changed.emit(vehicle_id, is_turning)


func _on_arm_has_item_changed(previous_value: bool, current_value: bool) -> void:
	arm_has_item_changed.emit(previous_value, current_value)


func _on_tray_count_changed(previous_count: int, current_count: int) -> void:
	tray_count_changed.emit(previous_count, current_count)


func _on_standard_box_count_changed(previous_count: int, current_count: int) -> void:
	standard_box_count_changed.emit(previous_count, current_count)


func _on_mission_state_changed(previous_state: int, current_state: int) -> void:
	mission_state_changed.emit(previous_state, current_state)


func _on_dynamic_cargo_changed(previous_value: bool, current_value: bool, vehicle_id: StringName) -> void:
	vehicle_cargo_changed.emit(vehicle_id, current_value)


func _on_dynamic_tray_count_changed(
	_previous_count: int,
	current_count: int,
	vehicle_id: StringName
) -> void:
	vehicle_tray_count_changed.emit(vehicle_id, current_count)

class_name Scene01CommandVehicleSelectionProxy
extends "res://scripts/input/vehicle_selection_controller.gd"

const VehicleActorScript := preload("res://scripts/vehicles/vehicle_actor.gd")

var _command_vehicle: VehicleActorScript


func set_command_vehicle(vehicle: VehicleActorScript) -> void:
	_command_vehicle = vehicle


func clear_command_vehicle() -> void:
	_command_vehicle = null


func get_selected_vehicle() -> VehicleActorScript:
	if _command_vehicle == null or not is_instance_valid(_command_vehicle):
		return null
	return _command_vehicle

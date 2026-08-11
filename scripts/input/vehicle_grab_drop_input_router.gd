class_name VehicleGrabDropInputRouter
extends Node

const VehicleGrabDropControllerScript := preload("res://scripts/input/vehicle_grab_drop_controller.gd")

@export var grab_drop_controller_path: NodePath = NodePath("../VehicleGrabDropController")


func _input(event: InputEvent) -> void:
	var controller := _get_grab_drop_controller()
	if controller == null:
		return
	controller._unhandled_input(event)


func _get_grab_drop_controller() -> VehicleGrabDropControllerScript:
	if grab_drop_controller_path.is_empty():
		return null
	return get_node_or_null(grab_drop_controller_path) as VehicleGrabDropControllerScript

class_name AssemblyMetrics
extends RefCounted

var cost: int = 0
var mass: float = 0.0


func _init(total_cost: int = 0, total_mass: float = 0.0) -> void:
	cost = total_cost
	mass = total_mass

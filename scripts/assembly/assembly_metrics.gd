class_name AssemblyMetrics
extends RefCounted

var _cost: int = 0
var _mass: float = 0.0


func _init(total_cost: int = 0, total_mass: float = 0.0) -> void:
	_cost = total_cost
	_mass = total_mass


func get_cost() -> int:
	return _cost


func get_mass() -> float:
	return _mass


func duplicate_metrics() -> AssemblyMetrics:
	return AssemblyMetrics.new(_cost, _mass)

extends "res://scripts/vehicles/vehicle_runtime_state.gd"

const StandardBlockScript := preload("res://scripts/objects/standard_block.gd")


func claim_carried_item(_block: StandardBlockScript) -> bool:
	return false

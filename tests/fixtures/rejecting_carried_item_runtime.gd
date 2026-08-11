extends "res://scripts/vehicles/vehicle_runtime_state.gd"

const StandardBlockScript := preload("res://scripts/objects/standard_block.gd")

var reject_carried_item_claims: bool = true


func claim_carried_item(block: StandardBlockScript) -> bool:
	if reject_carried_item_claims:
		return false
	return super.claim_carried_item(block)

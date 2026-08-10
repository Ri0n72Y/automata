extends RefCounted
class_name GrabDropInteractionPolicy

const VehicleRuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const ItemSourceInterfaceScript := preload("res://scripts/objects/item_source_interface.gd")
const ItemReceiverInterfaceScript := preload("res://scripts/objects/item_receiver_interface.gd")


static func get_forward_interaction_cells(
	runtime: VehicleRuntimeStateScript
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if runtime == null or runtime.definition == null:
		return result
	var anchor: Vector2i = runtime.anchor_cell
	var footprint: Vector2i = runtime.definition.footprint
	match runtime.facing:
		VehicleRuntimeStateScript.Facing.NORTH:
			for offset_x in range(footprint.x):
				result.append(anchor + Vector2i(offset_x, -1))
		VehicleRuntimeStateScript.Facing.EAST:
			for offset_y in range(footprint.y):
				result.append(anchor + Vector2i(footprint.x, offset_y))
		VehicleRuntimeStateScript.Facing.SOUTH:
			for offset_x in range(footprint.x):
				result.append(anchor + Vector2i(offset_x, footprint.y))
		VehicleRuntimeStateScript.Facing.WEST:
			for offset_y in range(footprint.y):
				result.append(anchor + Vector2i(-1, offset_y))
	return result


static func get_primary_interaction_cell(runtime: VehicleRuntimeStateScript) -> Vector2i:
	if runtime == null or runtime.definition == null:
		return Vector2i(-1, -1)
	var anchor: Vector2i = runtime.anchor_cell
	var footprint: Vector2i = runtime.definition.footprint
	match runtime.facing:
		VehicleRuntimeStateScript.Facing.NORTH:
			return anchor + Vector2i(0, -1)
		VehicleRuntimeStateScript.Facing.EAST:
			return anchor + Vector2i(footprint.x, 0)
		VehicleRuntimeStateScript.Facing.SOUTH:
			return anchor + Vector2i(footprint.x - 1, footprint.y)
		VehicleRuntimeStateScript.Facing.WEST:
			return anchor + Vector2i(-1, footprint.y - 1)
	return Vector2i(-1, -1)


static func get_target_interaction_cells(target: Variant) -> Array[Vector2i]:
	var source := target as ItemSourceInterfaceScript
	if source != null:
		return source.get_interaction_cells()
	var receiver := target as ItemReceiverInterfaceScript
	if receiver != null:
		return receiver.get_interaction_cells()
	var empty_cells: Array[Vector2i] = []
	return empty_cells


static func is_target_in_range(runtime: VehicleRuntimeStateScript, target: Variant) -> bool:
	if runtime == null or runtime.definition == null or target == null:
		return false
	var target_cells := get_target_interaction_cells(target)
	if target_cells.is_empty():
		return false
	var receiver := target as ItemReceiverInterfaceScript
	if receiver != null and receiver.uses_primary_interaction_cell():
		return target_cells.has(get_primary_interaction_cell(runtime))
	for cell in get_forward_interaction_cells(runtime):
		if target_cells.has(cell):
			return true
	return false

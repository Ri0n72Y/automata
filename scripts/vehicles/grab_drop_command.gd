extends RefCounted
class_name GrabDropCommand

const VehicleDefinitionScript := preload("res://scripts/vehicles/vehicle_definition.gd")
const VehicleRuntimeStateScript := preload("res://scripts/vehicles/vehicle_runtime_state.gd")
const GrabDropResultScript := preload("res://scripts/vehicles/grab_drop_result.gd")
const ItemSourceInterfaceScript := preload("res://scripts/objects/item_source_interface.gd")
const ItemReceiverInterfaceScript := preload("res://scripts/objects/item_receiver_interface.gd")
const ItemTransferResultScript := preload("res://scripts/objects/item_transfer_result.gd")
const StandardBlockScript := preload("res://scripts/objects/standard_block.gd")


func execute(runtime: VehicleRuntimeStateScript, target: Variant) -> GrabDropResultScript:
	if runtime == null or runtime.definition == null:
		return GrabDropResultScript.rejected(
			GrabDropResultScript.Action.NONE,
			GrabDropResultScript.Status.NO_CAPABILITY
		)
	if not runtime.definition.has_capability(VehicleDefinitionScript.CAPABILITY_CAN_GRAB):
		return GrabDropResultScript.rejected(
			GrabDropResultScript.Action.NONE,
			GrabDropResultScript.Status.NO_CAPABILITY
		)
	if (
		runtime.motion_state == VehicleRuntimeStateScript.MotionState.PLANNING
		or runtime.motion_state == VehicleRuntimeStateScript.MotionState.MOVING
	):
		return GrabDropResultScript.rejected(
			GrabDropResultScript.Action.NONE,
			GrabDropResultScript.Status.BUSY
		)
	if target == null:
		return GrabDropResultScript.rejected(
			GrabDropResultScript.Action.DROP if runtime.arm_has_item else GrabDropResultScript.Action.GRAB,
			GrabDropResultScript.Status.NO_TARGET
		)
	if runtime.arm_has_item:
		return _execute_drop(runtime, target)
	return _execute_grab(runtime, target)


func _execute_grab(runtime: VehicleRuntimeStateScript, target: Variant) -> GrabDropResultScript:
	var transfer := _take_from_target(target)
	if transfer == null:
		return GrabDropResultScript.rejected(
			GrabDropResultScript.Action.GRAB,
			GrabDropResultScript.Status.INVALID_TARGET
		)
	if not transfer.is_success():
		return GrabDropResultScript.rejected(
			GrabDropResultScript.Action.GRAB,
			_map_transfer_status(transfer.status)
		)
	var block := transfer.item
	if block == null or not runtime.claim_carried_item(block):
		_rollback_grab_target(target, block)
		return GrabDropResultScript.rejected(
			GrabDropResultScript.Action.GRAB,
			GrabDropResultScript.Status.OWNERSHIP_CONFLICT
		)
	return GrabDropResultScript.accepted(GrabDropResultScript.Action.GRAB, block)


func _execute_drop(runtime: VehicleRuntimeStateScript, target: Variant) -> GrabDropResultScript:
	var receiver := target as ItemReceiverInterfaceScript
	if receiver == null:
		return GrabDropResultScript.rejected(
			GrabDropResultScript.Action.DROP,
			GrabDropResultScript.Status.INVALID_TARGET
		)
	var block := runtime.release_carried_item()
	if block == null:
		return GrabDropResultScript.rejected(
			GrabDropResultScript.Action.DROP,
			GrabDropResultScript.Status.OWNERSHIP_CONFLICT
		)
	var transfer := receiver.put_item(block)
	if transfer.is_success():
		return GrabDropResultScript.accepted(GrabDropResultScript.Action.DROP, block)
	if not runtime.claim_carried_item(block):
		return GrabDropResultScript.rejected(
			GrabDropResultScript.Action.DROP,
			GrabDropResultScript.Status.OWNERSHIP_CONFLICT
		)
	return GrabDropResultScript.rejected(
		GrabDropResultScript.Action.DROP,
		_map_transfer_status(transfer.status)
	)


func _take_from_target(target: Variant) -> ItemTransferResultScript:
	var source := target as ItemSourceInterfaceScript
	if source != null:
		return source.take_item()
	var receiver := target as ItemReceiverInterfaceScript
	if receiver != null and receiver.can_take_item():
		return receiver.take_item()
	return null


func _rollback_grab_target(target: Variant, block: StandardBlockScript) -> void:
	if block == null:
		return
	var receiver := target as ItemReceiverInterfaceScript
	if receiver != null and receiver.can_take_item() and not block.is_claimed():
		receiver.put_item(block)


func _map_transfer_status(status: int) -> int:
	match status:
		ItemTransferResultScript.Status.EMPTY:
			return GrabDropResultScript.Status.EMPTY
		ItemTransferResultScript.Status.FULL:
			return GrabDropResultScript.Status.FULL
		ItemTransferResultScript.Status.TYPE_MISMATCH:
			return GrabDropResultScript.Status.TYPE_MISMATCH
		ItemTransferResultScript.Status.ALREADY_CONTAINED:
			return GrabDropResultScript.Status.ALREADY_CONTAINED
		ItemTransferResultScript.Status.INVALID_TARGET:
			return GrabDropResultScript.Status.INVALID_TARGET
		_:
			return GrabDropResultScript.Status.INVALID_TARGET

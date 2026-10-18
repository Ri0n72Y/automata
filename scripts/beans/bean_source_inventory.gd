class_name BeanSourceInventory
extends ItemSourceInterface

## Finite bean source. One Grab takes min(GRAB_LIMIT_GRAMS, remaining) grams
## and produces a BeanBatch; the source itself never claims the batch.

signal grams_changed(remaining_grams: int)

const GRAB_LIMIT_GRAMS := 300

var bean_type: StringName = BeanBatch.TYPE_SOYBEAN
var remaining_grams: int = 0
var capacity_grams: int = 1000


func configure(p_bean_type: StringName, p_grams: int, interaction_cell: Vector2i) -> void:
	bean_type = p_bean_type
	capacity_grams = maxi(p_grams, 0)
	remaining_grams = capacity_grams
	set_interaction_cells([interaction_cell])


func is_available() -> bool:
	return remaining_grams > 0


func is_infinite() -> bool:
	return false


func get_output_item_type() -> StringName:
	return bean_type


func take_item() -> ItemTransferResult:
	if remaining_grams <= 0:
		return ItemTransferResult.rejected(ItemTransferResult.Status.EMPTY)
	var grams := mini(GRAB_LIMIT_GRAMS, remaining_grams)
	remaining_grams -= grams
	var batch := BeanBatch.make_batch(bean_type, grams)
	grams_changed.emit(remaining_grams)
	return ItemTransferResult.accepted(batch)


func reset() -> void:
	remaining_grams = capacity_grams
	grams_changed.emit(remaining_grams)

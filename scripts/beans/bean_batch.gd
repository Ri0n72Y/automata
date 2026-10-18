class_name BeanBatch
extends StandardBlock

## Bean Sorting payload: a discrete, weighed batch of one bean type.
## Extends StandardBlock so the existing GrabDrop ownership/claim pipeline
## (ItemSourceInterface / ItemReceiverInterface / VehicleRuntimeState) is reused
## without a parallel transfer path.

const TYPE_SOYBEAN: StringName = &"soybean"
const TYPE_MUNG_BEAN: StringName = &"mung_bean"
const TYPE_WHITE_BEAN: StringName = &"white_bean"

const ALL_BEAN_TYPES: PackedStringArray = ["soybean", "mung_bean", "white_bean"]
const DISPLAY_NAMES := {
	TYPE_SOYBEAN: "黄豆",
	TYPE_MUNG_BEAN: "绿豆",
	TYPE_WHITE_BEAN: "白豆",
}
const VISUAL_COLORS := {
	TYPE_SOYBEAN: Color(0.85, 0.68, 0.26, 1),
	TYPE_MUNG_BEAN: Color(0.36, 0.62, 0.30, 1),
	TYPE_WHITE_BEAN: Color(0.92, 0.89, 0.80, 1),
}

var bean_type: StringName = TYPE_SOYBEAN
var grams: int = 0


static func make_batch(p_bean_type: StringName, p_grams: int) -> BeanBatch:
	var batch := BeanBatch.new()
	batch._block_id = _next_id
	_next_id += 1
	batch.bean_type = p_bean_type
	batch.grams = maxi(p_grams, 0)
	return batch


static func display_name_for(bean_type_value: StringName) -> String:
	return DISPLAY_NAMES.get(bean_type_value, String(bean_type_value))


static func color_for(bean_type_value: StringName) -> Color:
	return VISUAL_COLORS.get(bean_type_value, Color.WHITE)


func get_item_type() -> StringName:
	return bean_type


func get_grams() -> int:
	return grams

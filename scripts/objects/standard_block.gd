extends RefCounted
class_name StandardBlock

const TYPE_ID: StringName = &"standard_block"

static var _next_id: int = 1

var block_id: int = 0
var item_type: StringName = TYPE_ID


static func create() -> StandardBlock:
	var block := StandardBlock.new()
	block.block_id = _next_id
	_next_id += 1
	return block


func is_valid() -> bool:
	return block_id > 0 and item_type == TYPE_ID

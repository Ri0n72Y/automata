extends RefCounted
class_name StandardBlock

const TYPE_ID: StringName = &"standard_block"

static var _next_id: int = 1

var _block_id: int = 0
var _owner_id: int = 0


static func create() -> StandardBlock:
	var block := StandardBlock.new()
	block._block_id = _next_id
	_next_id += 1
	return block


func get_block_id() -> int:
	return _block_id


func get_item_type() -> StringName:
	return TYPE_ID


func is_valid() -> bool:
	return _block_id > 0


func is_claimed() -> bool:
	return _owner_id > 0


func is_claimed_by(owner_id: int) -> bool:
	return owner_id > 0 and _owner_id == owner_id


func try_claim(owner_id: int) -> bool:
	if not is_valid() or owner_id <= 0 or is_claimed():
		return false
	_owner_id = owner_id
	return true


func release_claim(owner_id: int) -> bool:
	if not is_claimed_by(owner_id):
		return false
	_owner_id = 0
	return true

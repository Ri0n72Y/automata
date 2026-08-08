extends RefCounted
class_name StandardBlock

const TYPE_ID: StringName = &"standard_block"

static var _next_id: int = 1

var _block_id: int = 0
var _owner_ref: WeakRef


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
	return _get_owner() != null


func is_claimed_by(owner: Object) -> bool:
	return owner != null and _get_owner() == owner


func try_claim(owner: Object) -> bool:
	if not is_valid() or owner == null or is_claimed():
		return false
	_owner_ref = weakref(owner)
	return true


func release_claim(owner: Object) -> bool:
	if not is_claimed_by(owner):
		return false
	_owner_ref = null
	return true


func _get_owner() -> Object:
	if _owner_ref == null:
		return null
	return _owner_ref.get_ref()

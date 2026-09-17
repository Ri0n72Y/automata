class_name Scene01Program
extends RefCounted

const NO_STATEMENT_INDEX := -1

enum StatementType {
	MOVE_TO = 1,
	GRAB_DROP = 2,
	REPEAT = 3,
}

var _statements: Array[Dictionary] = []


func reset() -> void:
	_statements.clear()


func append_statement(statement_type: int) -> int:
	if not _is_valid_type(statement_type):
		return NO_STATEMENT_INDEX
	_statements.append({
		"type": statement_type,
		"vehicle_id": &"",
		"target_anchor": Vector2i(-1, -1),
		"repeat_count": 1,
		"repeat_target_index": NO_STATEMENT_INDEX,
	})
	return _statements.size() - 1


func set_statement_vehicle(index: int, vehicle_id: StringName) -> bool:
	if not _has_index(index):
		return false
	var statement_type := int(_statements[index].get("type", -1))
	if statement_type != StatementType.MOVE_TO and statement_type != StatementType.GRAB_DROP:
		return false
	_statements[index]["vehicle_id"] = vehicle_id
	return true


func set_move_target(index: int, target_anchor: Vector2i) -> bool:
	if not _has_index(index) or int(_statements[index].get("type", -1)) != StatementType.MOVE_TO:
		return false
	_statements[index]["target_anchor"] = target_anchor
	return true


func set_repeat(index: int, repeat_count: int, target_index: int) -> bool:
	if not _has_index(index) or int(_statements[index].get("type", -1)) != StatementType.REPEAT:
		return false
	_statements[index]["repeat_count"] = repeat_count
	_statements[index]["repeat_target_index"] = target_index
	return true


func get_statement(index: int) -> Dictionary:
	return _statements[index].duplicate(true) if _has_index(index) else {}


func get_statements() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for statement in _statements:
		result.append(statement.duplicate(true))
	return result


func get_statement_count() -> int:
	return _statements.size()


func duplicate_program() -> Scene01Program:
	var copy := Scene01Program.new()
	copy._statements = get_statements()
	return copy


func _has_index(index: int) -> bool:
	return index >= 0 and index < _statements.size()


func _is_valid_type(statement_type: int) -> bool:
	return statement_type in [
		StatementType.MOVE_TO,
		StatementType.GRAB_DROP,
		StatementType.REPEAT,
	]
